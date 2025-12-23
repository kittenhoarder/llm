//
//  FileReaderAgent.swift
//  FoundationChatCore
//
//  Agent specialized in reading and processing files
//

import Foundation
import UniformTypeIdentifiers

/// Agent that reads and processes various file formats
///
/// **Status**: ✅ Fully Functional
/// - Can read files from the file system
/// - Requires file path to be provided in task parameters or context
/// - Supports text files, markdown, Swift code, JSON, CSV
/// - Full PDF text extraction with PDFKit
/// - File size limit: 10MB
///
/// **Tool Wiring**: ⚠️ No tools wired - reads files directly via FileManager
/// - TODO: Consider adding a file picker tool for better UX
@available(macOS 26.0, iOS 26.0, *)
public class FileReaderAgent: BaseAgent, @unchecked Sendable {
    /// Maximum file size to read
    private let maxFileSize: Int64 = AppConstants.maxFileSizeBytes
    
    /// Cache of file contents
    private var fileCache: [String: String] = [:]
    
    public init() {
        super.init(
            id: AgentId.fileReader,
            name: AgentName.fileReader,
            description: "Reads and processes files from the file system. Supports text files, markdown, Swift code, JSON, CSV, and full PDF text extraction.",
            capabilities: [.fileReading],
            tools: []
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Extract file path from task
        guard let filePath = task.parameters["filePath"] ?? context.fileReferences.first else {
            // No file specified, ask for clarification
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "No file path specified. Please provide a file path in the task parameters or context.",
                success: false,
                error: "Missing file path"
            )
        }
        
        // Check if file is an image - if so, return early and suggest using VisionAgent
        let fileURL = URL(fileURLWithPath: filePath)
        if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.conforms(to: .image) {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "This is an image file. Please use the Vision Agent to analyze images. The Vision Agent can describe images, identify objects, read text in images, and answer questions about visual content.",
                success: false,
                error: "Image files should be processed by VisionAgent"
            )
        }
        
        // Check if RAG is enabled
        let useRAG = UserDefaults.standard.bool(forKey: UserDefaultsKey.useRAG)
        
        // Try to extract conversationId from context metadata or file path
        var conversationId: UUID? = nil
        if let conversationIdString = context.metadata["conversationId"],
           let uuid = UUID(uuidString: conversationIdString) {
            conversationId = uuid
        } else {
            // Try to extract from file path (files are stored in conversation-specific directories)
            // Path format: .../FoundationChat/Files/{conversationId}/{fileId}/filename
            let pathComponents = (filePath as NSString).pathComponents
            if let filesIndex = pathComponents.firstIndex(of: "Files"),
               filesIndex + 1 < pathComponents.count,
               let uuid = UUID(uuidString: pathComponents[filesIndex + 1]) {
                conversationId = uuid
            }
        }
        
        // Try RAG search if enabled and conversationId is available
        var fileContent: String? = nil
        var ragChunks: [DocumentChunk] = []
        
        if useRAG, let conversationId = conversationId {
            do {
                let ragService = RAGService.shared
                // Extract query from task description
                let query = task.description.isEmpty ? "file content" : task.description
                
                // Search for relevant chunks
                let topK = UserDefaults.standard.integer(forKey: UserDefaultsKey.ragTopK) > 0
                    ? UserDefaults.standard.integer(forKey: UserDefaultsKey.ragTopK)
                    : 5
                
                ragChunks = try await ragService.searchRelevantChunks(
                    query: query,
                    fileIds: nil, // Search all files in conversation
                    conversationId: conversationId,
                    topK: topK
                )
                
                if !ragChunks.isEmpty {
                    // Use RAG chunks instead of full file
                    Log.debug("🔍 FileReaderAgent: Using RAG - found \(ragChunks.count) relevant chunks")
                    fileContent = formatRAGChunks(ragChunks)
                } else {
                    Log.warn("⚠️ FileReaderAgent: RAG search returned no results, falling back to full file read")
                }
            } catch {
                Log.warn("⚠️ FileReaderAgent: RAG search failed: \(error.localizedDescription), falling back to full file read")
            }
        }
        
        // Track original file size for token savings calculation
        var originalFileContentTokens: Int? = nil
        var actualFileContentTokens: Int? = nil
        
        // Fallback to full file read if RAG didn't provide content
        if fileContent == nil {
            do {
                let fullContent = try await readFile(at: filePath)
                // Count original file tokens (before truncation)
                let tokenCounter = TokenCounter()
                originalFileContentTokens = await tokenCounter.countTokens(fullContent)
                
                fileContent = await processFileContent(fullContent, filePath: filePath)
                
                // Count actual tokens used (after truncation/processing)
                if let processed = fileContent {
                    actualFileContentTokens = await tokenCounter.countTokens(processed)
                }
            } catch {
                return AgentResult(
                    agentId: id,
                    taskId: task.id,
                    content: "Failed to read file at \(filePath): \(error.localizedDescription)",
                    success: false,
                    error: error.localizedDescription
                )
            }
        } else if !ragChunks.isEmpty {
            // RAG chunks were used - calculate savings
            let tokenCounter = TokenCounter()
            
            // To get accurate savings, we need to estimate the original file size
            // Option 1: Read the full file (expensive but accurate)
            // Option 2: Estimate based on file size and chunk count
            // We'll try to read the file to get accurate count, but catch errors gracefully
            do {
                let fullContent = try await readFile(at: filePath)
                originalFileContentTokens = await tokenCounter.countTokens(fullContent)
            } catch {
                // If reading fails, estimate based on file size
                // Get file size from file system
                if let fileSize = try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64 {
                    // Estimate: file size in bytes / 4 ≈ characters / 4 ≈ tokens
                    // For PDFs, this is conservative since PDFs have overhead
                    originalFileContentTokens = Int(fileSize) / 4
                } else {
                    // Fallback: estimate based on chunk count
                    // From logs: 398 chunks indexed, each ~1000 chars = ~398k chars ≈ 99.5k tokens
                    let avgChunkSize = 1000 // characters per chunk
                    let estimatedChunks = 400 // Conservative estimate for large PDFs
                    originalFileContentTokens = (estimatedChunks * avgChunkSize) / 4
                }
            }
            
            // Count actual tokens in RAG chunks
            if let ragContent = fileContent {
                actualFileContentTokens = await tokenCounter.countTokens(ragContent)
            }
        }
        
        // Build context for model
        var updatedContext = context
        updatedContext.fileReferences.append(filePath)
        updatedContext.ragChunks = ragChunks
        updatedContext.toolResults["fileContent:\(filePath)"] = fileContent ?? ""
        
        // Store file content token savings in metadata
        if let original = originalFileContentTokens,
           let actual = actualFileContentTokens,
           original > actual {
            let savings = original - actual
            updatedContext.metadata["tokens_file_content_original"] = String(original)
            updatedContext.metadata["tokens_file_content_actual"] = String(actual)
            updatedContext.metadata["tokens_file_content_saved"] = String(savings)
            
            // #region debug log
            await DebugLogger.shared.log(
                location: "FileReaderAgent.swift:process",
                message: "File content token savings calculated",
                hypothesisId: "A",
                data: [
                    "originalTokens": original,
                    "actualTokens": actual,
                    "savings": savings,
                    "savingsPercentage": Double(savings) / Double(original) * 100.0,
                    "usedRAG": !ragChunks.isEmpty
                ]
            )
            // #endregion
        }
        
        // Create a task for the model to analyze the file
        let contentLabel = !ragChunks.isEmpty ? "relevant file chunks" : "file content"
        let fileContentLength = fileContent?.count ?? 0
        let analysisTaskDescription = """
            Analyze the following \(contentLabel):
            
            File: \(filePath)
            \(!ragChunks.isEmpty ? "Retrieved \(ragChunks.count) relevant chunks from RAG search.\n" : "")
            Content:
            \(fileContent ?? "")
            
            User request: \(task.description)
            """
        let analysisTaskDescriptionLength = analysisTaskDescription.count
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "FileReaderAgent.swift:process",
            message: "Creating analysis task with file content",
            hypothesisId: "A,B,C",
            data: [
                "fileContentLength": fileContentLength,
                "analysisTaskDescriptionLength": analysisTaskDescriptionLength,
                "estimatedTokens": analysisTaskDescriptionLength / 4,
                "hasRAGChunks": !ragChunks.isEmpty,
                "ragChunkCount": ragChunks.count
            ]
        )
        // #endregion
        
        let analysisTask = AgentTask(
            description: analysisTaskDescription,
            requiredCapabilities: [],
            parameters: task.parameters
        )
        
        // Get response from model
        let service = await modelService
        let response = try await service.respond(to: analysisTask.description)
        
        return AgentResult(
            agentId: id,
            taskId: task.id,
            content: response.content,
            success: true,
            toolCalls: response.toolCalls,
            updatedContext: updatedContext
        )
    }
    
    /// Format RAG chunks for LLM consumption
    /// - Parameter chunks: The document chunks to format
    /// - Returns: Formatted string with chunk content and metadata
    private func formatRAGChunks(_ chunks: [DocumentChunk]) -> String {
        var formatted = "=== Relevant File Chunks (from RAG search) ===\n\n"
        
        for (index, chunk) in chunks.enumerated() {
            formatted += "--- Chunk \(index + 1) of \(chunks.count) ---\n"
            if let fileId = chunk.metadata["fileId"] {
                formatted += "File ID: \(fileId)\n"
            }
            if let chunkIndex = chunk.metadata["chunkIndex"] {
                formatted += "Chunk Index: \(chunkIndex)\n"
            }
            formatted += "\n\(chunk.content)\n\n"
        }
        
        formatted += "=== End of Relevant Chunks ===\n"
        return formatted
    }
    
    /// Read a file from the file system
    /// - Parameter filePath: Path to the file
    /// - Returns: File content as string
    private func readFile(at filePath: String) async throws -> String {
        // Check cache first
        if let cached = fileCache[filePath] {
            return cached
        }
        
        let url: URL
        if filePath.hasPrefix("/") || filePath.hasPrefix("file://") {
            url = URL(fileURLWithPath: filePath.replacingOccurrences(of: "file://", with: ""))
        } else {
            // Assume relative path
            let currentDir = FileManager.default.currentDirectoryPath
            url = URL(fileURLWithPath: filePath, relativeTo: URL(fileURLWithPath: currentDir))
        }
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileReaderError.fileNotFound(filePath)
        }
        
        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? Int64, size > maxFileSize {
            throw FileReaderError.fileTooLarge(size, maxFileSize)
        }
        
        // Read file content
        let data = try Data(contentsOf: url)
        
        // Detect file type and decode accordingly
        let content: String
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            content = try await decodeFile(data: data, type: type)
        } else {
            // Fallback to UTF-8
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileReaderError.unsupportedEncoding
            }
            content = text
        }
        
        // Cache the content
        fileCache[filePath] = content
        
        return content
    }
    
    /// Decode file data based on type
    /// - Parameters:
    ///   - data: File data
    ///   - type: Content type
    /// - Returns: Decoded string
    private func decodeFile(data: Data, type: UTType) async throws -> String {
        // Text-based types
        if type.conforms(to: .text) || type.conforms(to: .plainText) {
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileReaderError.unsupportedEncoding
            }
            return text
        }
        
        // JSON
        if type.conforms(to: .json) {
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                  let text = String(data: jsonData, encoding: .utf8) else {
                throw FileReaderError.invalidJSON
            }
            return text
        }
        
        // CSV - basic parsing
        if type.identifier == "public.comma-separated-values-text" {
            guard let text = String(data: data, encoding: .utf8) else {
                throw FileReaderError.unsupportedEncoding
            }
            return text
        }
        
        // Image files - delegate to VisionAgent
        if type.conforms(to: .image) {
            // Return placeholder - VisionAgent will handle actual analysis
            return "[Image file - Use VisionAgent to analyze this image. File size: \(data.count) bytes]"
        }
        
        // PDF - extract text using PDFTextExtractor
        if type.conforms(to: .pdf) {
            do {
                let pdfContent = try await PDFTextExtractor.extractText(from: data)
                // Format with metadata for better context
                return pdfContent.formatted()
            } catch PDFExtractionError.passwordProtected {
                return "[PDF file - password-protected. Cannot extract text. File size: \(data.count) bytes]"
            } catch PDFExtractionError.invalidPDF(let reason) {
                return "[PDF file - invalid or corrupted: \(reason). File size: \(data.count) bytes]"
            } catch {
                return "[PDF file - extraction failed: \(error.localizedDescription). File size: \(data.count) bytes]"
            }
        }
        
        // Default: try UTF-8
        guard let text = String(data: data, encoding: .utf8) else {
            throw FileReaderError.unsupportedFileType(type.identifier)
        }
        return text
    }
    
    /// Process file content for better LLM consumption
    /// - Parameters:
    ///   - content: Raw file content
    ///   - filePath: File path
    /// - Returns: Processed content
    private func processFileContent(_ content: String, filePath: String) async -> String {
        // #region debug log
        await DebugLogger.shared.log(
            location: "FileReaderAgent.swift:processFileContent",
            message: "Processing file content",
            hypothesisId: "A,B,C",
            data: [
                "originalLength": content.count,
                "estimatedTokens": content.count / 4,
                "filePath": filePath
            ]
        )
        // #endregion
        
        // Truncate if too long (keep first 50k characters)
        // Note: 50k chars ≈ 12.5k tokens, but context window is 4096 tokens
        // So we should truncate to ~16k characters (4096 * 4)
        let maxLength = 16_000  // Reduced from 50k to fit 4096 token limit
        if content.count > maxLength {
            let truncated = String(content.prefix(maxLength))
            // #region debug log
            await DebugLogger.shared.log(
                location: "FileReaderAgent.swift:processFileContent",
                message: "Truncated file content",
                hypothesisId: "A",
                data: [
                    "originalLength": content.count,
                    "truncatedLength": truncated.count,
                    "estimatedTokens": truncated.count / 4
                ]
            )
            // #endregion
            return "\(truncated)\n\n[File truncated - original length: \(content.count) characters]"
        }
        
        return content
    }
    
    /// Clear file cache
    public func clearCache() {
        fileCache.removeAll()
    }
}

/// Errors for file reading
@available(macOS 26.0, iOS 26.0, *)
public enum FileReaderError: Error, Sendable {
    case fileNotFound(String)
    case fileTooLarge(Int64, Int64)
    case unsupportedEncoding
    case unsupportedFileType(String)
    case invalidJSON
    case permissionDenied
}
