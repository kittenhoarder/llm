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
    
    /// Check if a file is a PDF based on extension or MIME type
    /// - Parameters:
    ///   - attachment: The file attachment
    ///   - url: The file URL
    /// - Returns: True if the file is a PDF
    private func isPDFFile(attachment: FileAttachment, url: URL) -> Bool {
        // Check by file extension
        let fileExtension = (attachment.originalName as NSString).pathExtension.lowercased()
        if fileExtension == "pdf" {
            return true
        }
        
        // Check by MIME type if available
        if let mimeType = attachment.mimeType, mimeType.lowercased() == "application/pdf" {
            return true
        }
        
        // Check by content type
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           contentType.conforms(to: .pdf) {
            return true
        }
        
        return false
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
        
        // Detect if file is a PDF
        let isPDF = isPDFFile(attachment: attachment, url: fileURL)
        
        // Extract file content based on type
        let fileContent: String
        if isPDF {
            // Extract text from PDF using PDFTextExtractor
            do {
                let pdfContent = try await PDFTextExtractor.extractText(from: fileURL)
                // Format with metadata for better context
                fileContent = pdfContent.formatted()
                print("📄 RAGService: Extracted text from PDF (\(pdfContent.metadata.pageCount) pages): \(attachment.originalName)")
            } catch PDFExtractionError.passwordProtected {
                print("⚠️ RAGService: PDF is password-protected, skipping indexing: \(attachment.originalName)")
                throw RAGError.unsupportedFileType("Password-protected PDF: \(attachment.originalName)")
            } catch {
                print("⚠️ RAGService: Failed to extract text from PDF: \(attachment.originalName), error: \(error.localizedDescription)")
                throw RAGError.unsupportedFileType("PDF extraction failed: \(attachment.originalName)")
            }
        } else {
            // Read file content as text for non-PDF files
            guard let textContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
                // Try other encodings or skip non-text files
                print("⚠️ RAGService: Could not read file as UTF-8 text: \(attachment.originalName)")
                throw RAGError.unsupportedFileType(attachment.originalName)
            }
            fileContent = textContent
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
        // Filter out message chunks - only return document chunks (those with [file: prefix)
        var chunks: [DocumentChunk] = []
        
        for result in searchResults {
            var resultText = result.text
            
            // Skip message chunks - only process document chunks
            if resultText.hasPrefix("[message:") {
                continue
            }
            
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
    
    /// Index a single message for RAG retrieval
    /// - Parameters:
    ///   - message: The message to index
    ///   - conversationId: The conversation this message belongs to
    /// - Throws: RAGError if indexing fails
    public func indexMessage(_ message: Message, conversationId: UUID) async throws {
        // Skip empty messages
        guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ RAGService: Skipping empty message \(message.id)")
            return
        }
        
        // Get or create collection for this conversation
        let collectionName = "conversation_\(conversationId.uuidString)"
        let collection: Collection
        
        do {
            if let existingCollection = svdb.getCollection(collectionName) {
                collection = existingCollection
            } else {
                collection = try svdb.collection(collectionName)
            }
        } catch {
            if let existingCollection = svdb.getCollection(collectionName) {
                collection = existingCollection
            } else {
                throw RAGError.indexingFailed("Failed to get or create collection: \(error.localizedDescription)")
            }
        }
        
        // Prepare message text: include role and content
        let messageText = "\(message.role.rawValue.capitalized): \(message.content)"
        
        // Check if message needs chunking (if it exceeds chunk size)
        let messageTokens = messageText.count / 4 // Rough token estimate
        let needsChunking = messageTokens > chunkSize
        
        if needsChunking {
            // Chunk the message content
            let chunks = chunker.chunk(text: message.content, chunkSize: chunkSize, overlap: chunkOverlap)
            
            guard !chunks.isEmpty else {
                throw RAGError.chunkingFailed("No chunks created from message")
            }
            
            // Generate embeddings for all chunks
            let embeddings = try await embeddingService.embedBatch(texts: chunks)
            
            guard embeddings.count == chunks.count else {
                throw RAGError.embeddingMismatch("Generated \(embeddings.count) embeddings for \(chunks.count) chunks")
            }
            
            // Store each chunk in SVDB
            for (index, (chunk, embedding)) in zip(chunks, embeddings).enumerated() {
                let doubleEmbedding = embedding.map { Double($0) }
                
                // Encode metadata in the document text prefix
                // Format: [message:{messageId}|role:{role}|chunk:{index}|timestamp:{timestamp}|conversation:{conversationId}]
                let timestampString = ISO8601DateFormatter().string(from: message.timestamp)
                let metadataPrefix = "[message:\(message.id.uuidString)|role:\(message.role.rawValue)|chunk:\(index)|timestamp:\(timestampString)|conversation:\(conversationId.uuidString)]"
                let documentWithMetadata = "\(metadataPrefix)\n\(chunk)"
                
                collection.addDocument(
                    id: UUID(),
                    text: documentWithMetadata,
                    embedding: doubleEmbedding
                )
            }
            
            print("✅ RAGService: Successfully indexed message \(message.id) as \(chunks.count) chunks")
        } else {
            // Message fits in one chunk, index as-is
            // Embed the full message text (including role) for better semantic matching
            let embedding = try await embeddingService.embed(text: messageText)
            let doubleEmbedding = embedding.map { Double($0) }
            
            // Encode metadata in the document text prefix
            let timestampString = ISO8601DateFormatter().string(from: message.timestamp)
            let metadataPrefix = "[message:\(message.id.uuidString)|role:\(message.role.rawValue)|chunk:0|timestamp:\(timestampString)|conversation:\(conversationId.uuidString)]"
            let documentWithMetadata = "\(metadataPrefix)\n\(messageText)"
            
            collection.addDocument(
                id: UUID(),
                text: documentWithMetadata,
                embedding: doubleEmbedding
            )
            
            print("✅ RAGService: Successfully indexed message \(message.id)")
        }
    }
    
    /// Index all messages in a conversation's history
    /// - Parameters:
    ///   - messages: Array of messages to index
    ///   - conversationId: The conversation ID
    /// - Throws: RAGError if indexing fails
    public func indexConversationHistory(_ messages: [Message], conversationId: UUID) async throws {
        guard !messages.isEmpty else {
            print("ℹ️ RAGService: No messages to index for conversation \(conversationId)")
            return
        }
        
        print("📝 RAGService: Indexing \(messages.count) messages for conversation \(conversationId)")
        
        var indexedCount = 0
        var errorCount = 0
        
        for message in messages {
            do {
                try await indexMessage(message, conversationId: conversationId)
                indexedCount += 1
            } catch {
                errorCount += 1
                print("⚠️ RAGService: Failed to index message \(message.id): \(error.localizedDescription)")
                // Continue with other messages even if one fails
            }
        }
        
        print("✅ RAGService: Indexed \(indexedCount)/\(messages.count) messages (\(errorCount) errors)")
    }
    
    /// Search for relevant messages based on query
    /// - Parameters:
    ///   - query: The search query
    ///   - conversationId: The conversation to search within
    ///   - topK: Number of results to return (default: uses instance topK)
    /// - Returns: Array of relevant message chunks sorted by relevance
    /// - Throws: RAGError if search fails
    public func searchRelevantMessages(
        query: String,
        conversationId: UUID,
        topK: Int? = nil
    ) async throws -> [MessageChunk] {
        let k = topK ?? self.topK
        let collectionName = "conversation_\(conversationId.uuidString)"
        
        // Generate embedding for query
        let queryEmbedding = try await embeddingService.embed(text: query)
        let doubleQueryEmbedding = queryEmbedding.map { Double($0) }
        
        // Get collection for this conversation
        guard let collection = svdb.getCollection(collectionName) else {
            // Collection doesn't exist, return empty results
            return []
        }
        
        // Search SVDB
        let searchResults = collection.search(
            query: doubleQueryEmbedding,
            num_results: k * 2 // Get more results to filter for messages only
        )
        
        // Convert SearchResult objects to MessageChunk objects
        var messageChunks: [MessageChunk] = []
        
        for result in searchResults {
            var resultText = result.text
            var messageId = UUID()
            var role = MessageRole.user
            var timestamp = Date()
            var chunkIndex = 0
            
            // Parse metadata from text prefix if present
            if resultText.hasPrefix("[message:") {
                let lines = resultText.components(separatedBy: "\n")
                if let metadataLine = lines.first {
                    // Parse metadata: [message:{messageId}|role:{role}|chunk:{index}|timestamp:{timestamp}|conversation:{conversationId}]
                    let components = metadataLine
                        .replacingOccurrences(of: "[message:", with: "")
                        .replacingOccurrences(of: "]", with: "")
                        .components(separatedBy: "|")
                    
                    for component in components {
                        if component.hasPrefix("message:") {
                            let messageIdString = String(component.dropFirst(8))
                            if let uuid = UUID(uuidString: messageIdString) {
                                messageId = uuid
                            }
                        } else if component.hasPrefix("role:") {
                            let roleString = String(component.dropFirst(5))
                            role = MessageRole(rawValue: roleString) ?? .user
                        } else if component.hasPrefix("chunk:") {
                            let chunkIndexString = String(component.dropFirst(6))
                            chunkIndex = Int(chunkIndexString) ?? 0
                        } else if component.hasPrefix("timestamp:") {
                            let timestampString = String(component.dropFirst(11))
                            if let date = ISO8601DateFormatter().date(from: timestampString) {
                                timestamp = date
                            }
                        }
                    }
                }
                
                // Remove metadata line from content
                if lines.count > 1 {
                    resultText = lines.dropFirst().joined(separator: "\n")
                } else {
                    resultText = ""
                }
            } else {
                // Not a message chunk, skip it (might be a file chunk)
                continue
            }
            
            let chunk = MessageChunk(
                id: result.id,
                messageId: messageId,
                conversationId: conversationId,
                chunkIndex: chunkIndex,
                role: role,
                content: resultText,
                timestamp: timestamp,
                embedding: queryEmbedding,
                metadata: [
                    "messageId": messageId.uuidString,
                    "role": role.rawValue,
                    "chunkIndex": String(chunkIndex),
                    "score": String(result.score)
                ]
            )
            
            messageChunks.append(chunk)
        }
        
        // Limit to topK and sort by score (highest first)
        messageChunks.sort { chunk1, chunk2 in
            let score1 = Double(chunk1.metadata["score"] ?? "0") ?? 0
            let score2 = Double(chunk2.metadata["score"] ?? "0") ?? 0
            return score1 > score2
        }
        
        return Array(messageChunks.prefix(k))
    }
    
    /// Index all existing conversations in the database
    /// This is a migration method to retroactively index conversation history
    /// - Parameter conversationService: The conversation service to load conversations from
    /// - Returns: Migration result with counts of indexed conversations and messages
    public func indexExistingConversations(conversationService: ConversationService) async throws -> (conversationsIndexed: Int, messagesIndexed: Int, errors: Int) {
        print("🔄 RAGService: Starting migration to index existing conversations...")
        
        var conversationsIndexed = 0
        var messagesIndexed = 0
        var errors = 0
        
        do {
            let conversations = try conversationService.loadConversations()
            print("📝 RAGService: Found \(conversations.count) conversations to index")
            
            for conversation in conversations {
                guard !conversation.isEphemeral else {
                    continue
                }
                
                guard !conversation.messages.isEmpty else {
                    continue
                }
                
                do {
                    try await indexConversationHistory(conversation.messages, conversationId: conversation.id)
                    conversationsIndexed += 1
                    messagesIndexed += conversation.messages.count
                    print("✅ RAGService: Indexed conversation \(conversation.id) (\(conversation.messages.count) messages)")
                } catch {
                    errors += 1
                    print("⚠️ RAGService: Failed to index conversation \(conversation.id): \(error.localizedDescription)")
                }
            }
            
            print("✅ RAGService: Migration complete - \(conversationsIndexed) conversations, \(messagesIndexed) messages indexed, \(errors) errors")
        } catch {
            print("❌ RAGService: Migration failed: \(error.localizedDescription)")
            throw RAGError.indexingFailed("Failed to load conversations: \(error.localizedDescription)")
        }
        
        return (conversationsIndexed: conversationsIndexed, messagesIndexed: messagesIndexed, errors: errors)
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

