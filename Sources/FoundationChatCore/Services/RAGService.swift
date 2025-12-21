//
//  RAGService.swift
//  FoundationChatCore
//
//  Service for RAG (Retrieval-Augmented Generation) using SVDB
//

import Foundation
import SVDB

/// Service for managing RAG operations with SVDB vector database
@available(macOS 26.0, iOS 26.0, *)
public actor RAGService {
    /// Shared singleton instance
    public static let shared = RAGService()
    
    /// SVDB instance
    private let svdb: SVDB
    
    /// Embedding service
    private let embeddingService = EmbeddingService.shared
    
    /// Text chunker
    private let chunker = TextChunker.self
    
    /// Get chunk size from UserDefaults or use default
    private var chunkSize: Int {
        let value = UserDefaults.standard.integer(forKey: UserDefaultsKey.ragChunkSize)
        return value > 0 ? value : TextChunker.defaultChunkSize
    }
    
    /// Default chunk overlap (20% of chunk size)
    private var chunkOverlap: Int {
        return max(100, chunkSize / 5) // 20% overlap, minimum 100
    }
    
    /// Get topK from UserDefaults or use default
    private var topK: Int {
        let value = UserDefaults.standard.integer(forKey: UserDefaultsKey.ragTopK)
        return value > 0 ? value : 5
    }
    
    /// Storage directory for SVDB
    private let storageDirectory: URL
    
    /// File manager
    private let fileManager = FileManager.default
    
    /// Initialize the RAG service
    private init() {
        // Get Application Support directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = "FoundationChat"
        let ragDir = appSupport.appendingPathComponent(appName).appendingPathComponent("RAG", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: ragDir, withIntermediateDirectories: true)
        
        self.storageDirectory = ragDir
        self.svdb = SVDB.shared
        
        print("🔍 RAGService initialized. Storage: \(ragDir.path)")
    }
    
    /// Index a file for RAG retrieval
    /// - Parameters:
    ///   - attachment: The file attachment to index
    ///   - conversationId: The conversation this file belongs to
    /// - Throws: RAGError if indexing fails
    public func indexFile(attachment: FileAttachment, conversationId: UUID) async throws {
        // Read file content
        let fileURL = URL(fileURLWithPath: attachment.sandboxPath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw RAGError.fileNotFound(attachment.sandboxPath)
        }
        
        // Read file content as text
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            // Try other encodings or skip non-text files
            print("⚠️ RAGService: Could not read file as UTF-8 text: \(attachment.originalName)")
            throw RAGError.unsupportedFileType(attachment.originalName)
        }
        
        // Skip empty files
        guard !fileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ RAGService: File is empty: \(attachment.originalName)")
            return
        }
        
        // Chunk the content
        let chunks = chunker.chunk(text: fileContent, chunkSize: chunkSize, overlap: chunkOverlap)
        
        guard !chunks.isEmpty else {
            throw RAGError.chunkingFailed("No chunks created from file")
        }
        
        print("📄 RAGService: Indexing \(chunks.count) chunks from \(attachment.originalName)")
        
        // Generate embeddings for all chunks
        let embeddings = try await embeddingService.embedBatch(texts: chunks)
        
        guard embeddings.count == chunks.count else {
            throw RAGError.embeddingMismatch("Generated \(embeddings.count) embeddings for \(chunks.count) chunks")
        }
        
        // Get or create collection for this conversation
        let collectionName = "conversation_\(conversationId.uuidString)"
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "RAGService.swift:indexFile",
            message: "indexFile: Getting or creating collection",
            hypothesisId: "D",
            data: ["collectionName": collectionName, "conversationId": conversationId.uuidString, "fileName": attachment.originalName]
        )
        // #endregion
        
        let collection: Collection
        do {
            // Try to get existing collection first
            if let existingCollection = svdb.getCollection(collectionName) {
                collection = existingCollection
                // #region debug log
                await DebugLogger.shared.log(
                    location: "RAGService.swift:indexFile",
                    message: "Found existing collection",
                    hypothesisId: "D",
                    data: ["collectionName": collectionName]
                )
                // #endregion
            } else {
                // Create new collection if it doesn't exist
                collection = try svdb.collection(collectionName)
                // #region debug log
                await DebugLogger.shared.log(
                    location: "RAGService.swift:indexFile",
                    message: "Created new collection",
                    hypothesisId: "D",
                    data: ["collectionName": collectionName]
                )
                // #endregion
            }
        } catch {
            // If collection already exists, get it
            if let existingCollection = svdb.getCollection(collectionName) {
                collection = existingCollection
            } else {
                throw RAGError.indexingFailed("Failed to get or create collection: \(error.localizedDescription)")
            }
        }
        
        // Store each chunk in SVDB
        for (index, (chunk, embedding)) in zip(chunks, embeddings).enumerated() {
            // Convert Float array to Double array for SVDB
            let doubleEmbedding = embedding.map { Double($0) }
            
            // Encode metadata in the document text prefix
            // Format: [file:{fileId}|chunk:{index}|conversation:{conversationId}]
            let metadataPrefix = "[file:\(attachment.id.uuidString)|chunk:\(index)|conversation:\(conversationId.uuidString)]"
            let documentWithMetadata = "\(metadataPrefix)\n\(chunk)"
            
            // Add document to SVDB collection
            collection.addDocument(
                id: UUID(), // Generate unique ID for this chunk
                text: documentWithMetadata,
                embedding: doubleEmbedding
            )
        }
        
        print("✅ RAGService: Successfully indexed \(chunks.count) chunks from \(attachment.originalName)")
    }
    
    /// Search for relevant chunks based on query
    /// - Parameters:
    ///   - query: The search query
    ///   - fileIds: Optional array of file IDs to limit search to
    ///   - conversationId: The conversation to search within
    ///   - topK: Number of results to return (default: uses instance topK)
    /// - Returns: Array of relevant document chunks sorted by relevance
    /// - Throws: RAGError if search fails
    public func searchRelevantChunks(
        query: String,
        fileIds: [UUID]? = nil,
        conversationId: UUID,
        topK: Int? = nil
    ) async throws -> [DocumentChunk] {
        // #region debug log
        let collectionName = "conversation_\(conversationId.uuidString)"
        await DebugLogger.shared.log(
            location: "RAGService.swift:searchRelevantChunks",
            message: "searchRelevantChunks called",
            hypothesisId: "B,E",
            data: ["query": String(query.prefix(50)), "conversationId": conversationId.uuidString, "collectionName": collectionName]
        )
        // #endregion
        
        let k = topK ?? self.topK
        
        // Generate embedding for query
        let queryEmbedding = try await embeddingService.embed(text: query)
        let doubleQueryEmbedding = queryEmbedding.map { Double($0) }
        
        // Get collection for this conversation
        guard let collection = svdb.getCollection(collectionName) else {
            // #region debug log
            await DebugLogger.shared.log(
                location: "RAGService.swift:searchRelevantChunks",
                message: "Collection not found, returning empty",
                hypothesisId: "D,E",
                data: ["collectionName": collectionName]
            )
            // #endregion
            // Collection doesn't exist, return empty results
            return []
        }
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "RAGService.swift:searchRelevantChunks",
            message: "Collection found, performing search",
            hypothesisId: "D",
            data: ["collectionName": collectionName, "topK": k]
        )
        // #endregion
        
        // Search SVDB - returns [SearchResult] with id, text, and score
        let searchResults = collection.search(
            query: doubleQueryEmbedding,
            num_results: k
        )
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "RAGService.swift:searchRelevantChunks",
            message: "Search completed",
            hypothesisId: "E",
            data: ["resultsCount": searchResults.count]
        )
        // #endregion
        
        // Convert SearchResult objects to DocumentChunk objects
        var chunks: [DocumentChunk] = []
        
        for result in searchResults {
            var resultText = result.text
            var fileId = UUID()
            var chunkIndex = 0
            
            // Parse metadata from text prefix if present
            if resultText.hasPrefix("[file:") {
                let lines = resultText.components(separatedBy: "\n")
                if let metadataLine = lines.first {
                    // Parse metadata: [file:{fileId}|chunk:{index}|conversation:{conversationId}]
                    let components = metadataLine
                        .replacingOccurrences(of: "[file:", with: "")
                        .replacingOccurrences(of: "]", with: "")
                        .components(separatedBy: "|")
                    
                    for component in components {
                        if component.hasPrefix("file:") {
                            let fileIdString = String(component.dropFirst(5))
                            if let uuid = UUID(uuidString: fileIdString) {
                                fileId = uuid
                            }
                        } else if component.hasPrefix("chunk:") {
                            let chunkIndexString = String(component.dropFirst(6))
                            chunkIndex = Int(chunkIndexString) ?? 0
                        }
                    }
                }
                
                // Remove metadata line from content
                if lines.count > 1 {
                    resultText = lines.dropFirst().joined(separator: "\n")
                } else {
                    resultText = ""
                }
            }
            
            // Filter by fileIds if specified
            if let fileIds = fileIds, !fileIds.contains(fileId) {
                continue
            }
            
            let chunk = DocumentChunk(
                id: result.id,
                fileId: fileId,
                conversationId: conversationId,
                chunkIndex: chunkIndex,
                content: resultText,
                embedding: queryEmbedding, // We don't store the original embedding, use query as placeholder
                metadata: [
                    "fileId": fileId.uuidString,
                    "chunkIndex": String(chunkIndex),
                    "score": String(result.score)
                ]
            )
            
            chunks.append(chunk)
        }
        
        return chunks
    }
    
    /// Delete all indexes for a specific file
    /// - Parameters:
    ///   - attachmentId: The file attachment ID
    ///   - conversationId: The conversation ID to search within
    /// - Throws: RAGError if deletion fails
    public func deleteFileIndex(attachmentId: UUID, conversationId: UUID) async throws {
        let collectionName = "conversation_\(conversationId.uuidString)"
        
        guard let collection = svdb.getCollection(collectionName) else {
            // Collection doesn't exist, nothing to delete
            return
        }
        
        // Search for all documents with this file ID in their metadata
        // We need to search through all documents to find ones matching this file
        // Since SVDB doesn't support metadata filtering, we'll need to:
        // 1. Get all documents (by searching with a dummy query that returns all)
        // 2. Filter by parsing metadata
        // 3. Remove matching documents
        
        // For now, we'll use a broad search to get documents, then filter
        // Note: This is inefficient but SVDB doesn't support metadata queries
        let dummyQuery = Array(repeating: 0.0, count: 300) // Default embedding dimension
        let allResults = collection.search(query: dummyQuery, num_results: 1000)
        
        var documentsToRemove: [UUID] = []
        
        for result in allResults {
            // Parse metadata from text prefix
            if result.text.hasPrefix("[file:") {
                let lines = result.text.components(separatedBy: "\n")
                if let metadataLine = lines.first {
                    let components = metadataLine
                        .replacingOccurrences(of: "[file:", with: "")
                        .replacingOccurrences(of: "]", with: "")
                        .components(separatedBy: "|")
                    
                    for component in components {
                        if component.hasPrefix("file:") {
                            let fileIdString = String(component.dropFirst(5))
                            if let fileId = UUID(uuidString: fileIdString),
                               fileId == attachmentId {
                                documentsToRemove.append(result.id)
                                break
                            }
                        }
                    }
                }
            }
        }
        
        // Remove all matching documents
        for documentId in documentsToRemove {
            collection.removeDocument(byId: documentId)
        }
        
        print("🗑️ RAGService: Deleted \(documentsToRemove.count) chunks for file \(attachmentId.uuidString)")
    }
    
    /// Delete all indexes for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Throws: RAGError if deletion fails
    public func deleteConversationIndexes(conversationId: UUID) async throws {
        let collectionName = "conversation_\(conversationId.uuidString)"
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "RAGService.swift:deleteConversationIndexes",
            message: "deleteConversationIndexes called",
            hypothesisId: "C",
            data: ["conversationId": conversationId.uuidString, "collectionName": collectionName]
        )
        // #endregion
        
        // Get collection if it exists
        if let collection = svdb.getCollection(collectionName) {
            // Clear all documents from the collection
            collection.clear()
            print("🗑️ RAGService: Cleared all documents from collection \(collectionName)")
        }
        
        // Release the collection from SVDB
        svdb.releaseCollection(collectionName)
        print("🗑️ RAGService: Released collection \(collectionName)")
    }
}

/// Errors for RAG operations
@available(macOS 26.0, iOS 26.0, *)
public enum RAGError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case unsupportedFileType(String)
    case chunkingFailed(String)
    case embeddingMismatch(String)
    case searchFailed(String)
    case indexingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupportedFileType(let filename):
            return "Unsupported file type: \(filename)"
        case .chunkingFailed(let reason):
            return "Chunking failed: \(reason)"
        case .embeddingMismatch(let reason):
            return "Embedding mismatch: \(reason)"
        case .searchFailed(let reason):
            return "Search failed: \(reason)"
        case .indexingFailed(let reason):
            return "Indexing failed: \(reason)"
        }
    }
}

