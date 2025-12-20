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
/// **Status**: ⚠️ Partially Functional
/// - Can read files from the file system
/// - Requires file path to be provided in task parameters or context
/// - Supports text files, markdown, Swift code, JSON, CSV
/// - PDF reading is limited (basic text extraction not yet implemented)
/// - File size limit: 10MB
///
/// **Tool Wiring**: ⚠️ No tools wired - reads files directly via FileManager
/// - TODO: Consider adding a file picker tool for better UX
/// - TODO: Improve PDF text extraction support
@available(macOS 26.0, iOS 26.0, *)
public class FileReaderAgent: BaseAgent, @unchecked Sendable {
    /// Maximum file size to read (10MB)
    private let maxFileSize: Int64 = 10 * 1024 * 1024
    
    /// Cache of file contents
    private var fileCache: [String: String] = [:]
    
    public init() {
        super.init(
            name: "File Reader",
            description: "Reads and processes files from the file system. Supports text files, markdown, Swift code, JSON, CSV, and basic PDF reading.",
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
        
        // Check if RAG is enabled
        let useRAG = UserDefaults.standard.bool(forKey: "useRAG")
        
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
                let topK = UserDefaults.standard.integer(forKey: "ragTopK") > 0 
                    ? UserDefaults.standard.integer(forKey: "ragTopK") 
                    : 5
                
                ragChunks = try await ragService.searchRelevantChunks(
                    query: query,
                    fileIds: nil, // Search all files in conversation
                    conversationId: conversationId,
                    topK: topK
                )
                
                if !ragChunks.isEmpty {
                    // Use RAG chunks instead of full file
                    print("🔍 FileReaderAgent: Using RAG - found \(ragChunks.count) relevant chunks")
                    fileContent = formatRAGChunks(ragChunks)
                } else {
                    print("⚠️ FileReaderAgent: RAG search returned no results, falling back to full file read")
                }
            } catch {
                print("⚠️ FileReaderAgent: RAG search failed: \(error.localizedDescription), falling back to full file read")
            }
        }
        
        // Fallback to full file read if RAG didn't provide content
        if fileContent == nil {
            do {
                let fullContent = try await readFile(at: filePath)
                fileContent = processFileContent(fullContent, filePath: filePath)
            } catch {
                return AgentResult(
                    agentId: id,
                    taskId: task.id,
                    content: "Failed to read file at \(filePath): \(error.localizedDescription)",
                    success: false,
                    error: error.localizedDescription
                )
            }
        }
        
        // Build context for model
        var updatedContext = context
        updatedContext.fileReferences.append(filePath)
        updatedContext.ragChunks = ragChunks
        updatedContext.toolResults["fileContent:\(filePath)"] = fileContent ?? ""
        
        // Create a task for the model to analyze the file
        let contentLabel = !ragChunks.isEmpty ? "relevant file chunks" : "file content"
        let analysisTask = AgentTask(
            description: """
            Analyze the following \(contentLabel):
            
            File: \(filePath)
            \(!ragChunks.isEmpty ? "Retrieved \(ragChunks.count) relevant chunks from RAG search.\n" : "")
            Content:
            \(fileContent ?? "")
            
            User request: \(task.description)
            """,
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
            content = try decodeFile(data: data, type: type)
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
    private func decodeFile(data: Data, type: UTType) throws -> String {
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
        
        // PDF - basic text extraction (limited)
        if type.conforms(to: .pdf) {
            // For now, return a placeholder - full PDF parsing would require additional libraries
            return "[PDF file - basic text extraction not yet implemented. File size: \(data.count) bytes]"
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
    private func processFileContent(_ content: String, filePath: String) -> String {
        // Truncate if too long (keep first 50k characters)
        let maxLength = 50_000
        if content.count > maxLength {
            let truncated = String(content.prefix(maxLength))
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


