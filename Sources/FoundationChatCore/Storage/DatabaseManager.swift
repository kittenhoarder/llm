//
//  DatabaseManager.swift
//  FoundationChatCore
//
//  SQLite database manager for conversations and file metadata
//

import Foundation
import SQLite

/// Manager for SQLite database operations
/// Thread-safe: SQLite connections are safe for concurrent reads, writes are serialized
@available(macOS 26.0, iOS 26.0, *)
public class DatabaseManager {
    /// The SQLite database connection
    private let db: Connection
    
    /// Path to the database file
    private let dbPath: String
    
    /// Tables
    private let conversations = Table("conversations")
    private let messages = Table("messages")
    private let files = Table("files")
    
    /// Conversation table columns
    private let conversationId = Expression<UUID>("id")
    private let conversationTitle = Expression<String>("title")
    private let conversationCreatedAt = Expression<Date>("created_at")
    private let conversationUpdatedAt = Expression<Date>("updated_at")
    private let conversationIsEphemeral = Expression<Bool>("is_ephemeral")
    private let conversationAgentConfig = Expression<String?>("agent_configuration")
    private let conversationSummary = Expression<String?>("summary")
    private let conversationTokenUsage = Expression<Int?>("token_usage")
    
    /// Message table columns
    private let messageId = Expression<UUID>("id")
    private let messageConversationId = Expression<UUID>("conversation_id")
    private let messageRole = Expression<String>("role")
    private let messageContent = Expression<String>("content")
    private let messageTimestamp = Expression<Date>("timestamp")
    private let messageToolCalls = Expression<String?>("tool_calls")
    private let messageAttachments = Expression<String?>("attachments")
    
    /// File table columns
    private let fileId = Expression<UUID>("id")
    private let fileFilename = Expression<String>("filename")
    private let fileFilepath = Expression<String>("filepath")
    private let fileFileType = Expression<String>("file_type")
    private let fileIndexedAt = Expression<Date>("indexed_at")
    private let fileEmbeddingCount = Expression<Int>("embedding_count")
    private let fileIsIndexed = Expression<Bool>("is_indexed")
    private let fileFileSize = Expression<Int64>("file_size")
    
    /// Initialize the database manager
    /// - Parameter dbPath: Path to the database file (defaults to app support directory)
    public init(dbPath: String? = nil) throws {
        print("🗄️ DatabaseManager init starting...")
        let resolvedPath: String
        if let dbPath = dbPath {
            resolvedPath = dbPath
            print("🗄️ Using provided dbPath: \(dbPath)")
        } else {
            print("🗄️ Getting app support directory...")
            // Default to app support directory
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appName = "FoundationChat"
            let appDir = appSupport.appendingPathComponent(appName)
            
            print("🗄️ Creating directory if needed: \(appDir.path)")
            // Create directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            
            resolvedPath = appDir.appendingPathComponent("foundationchat.db").path
            print("🗄️ Resolved path: \(resolvedPath)")
        }
        
        self.dbPath = resolvedPath
        print("🗄️ Creating SQLite connection...")
        self.db = try Connection(resolvedPath)
        print("🗄️ SQLite connection created, initializing database...")
        try initializeDatabase()
        print("✅ DatabaseManager init complete")
    }
    
    /// Initialize the database and create tables if they don't exist
    private func initializeDatabase() throws {
        
        // Create conversations table
        try db.run(conversations.create(ifNotExists: true) { t in
            t.column(conversationId, primaryKey: true)
            t.column(conversationTitle)
            t.column(conversationCreatedAt)
            t.column(conversationUpdatedAt)
            t.column(conversationIsEphemeral)
            t.column(conversationAgentConfig)
            t.column(conversationSummary)
            t.column(conversationTokenUsage)
        })
        
        // Migrate existing databases: add new columns if they don't exist
        do {
            try db.run("ALTER TABLE conversations ADD COLUMN agent_configuration TEXT")
        } catch {
            // Column already exists, ignore
        }
        
        do {
            try db.run("ALTER TABLE conversations ADD COLUMN summary TEXT")
        } catch {
            // Column already exists, ignore
        }
        
        do {
            try db.run("ALTER TABLE conversations ADD COLUMN token_usage INTEGER")
        } catch {
            // Column already exists, ignore
        }
        
        // Create messages table
        try db.run(messages.create(ifNotExists: true) { t in
            t.column(messageId, primaryKey: true)
            t.column(messageConversationId)
            t.column(messageRole)
            t.column(messageContent)
            t.column(messageTimestamp)
            t.column(messageToolCalls)
            t.foreignKey(messageConversationId, references: conversations, conversationId, delete: .cascade)
        })
        
        // Migrate existing databases: add attachments column if it doesn't exist
        do {
            try db.run("ALTER TABLE messages ADD COLUMN attachments TEXT")
        } catch {
            // Column already exists, ignore
        }
        
        // Create files table
        try db.run(files.create(ifNotExists: true) { t in
            t.column(fileId, primaryKey: true)
            t.column(fileFilename)
            t.column(fileFilepath)
            t.column(fileFileType)
            t.column(fileIndexedAt)
            t.column(fileEmbeddingCount)
            t.column(fileIsIndexed, defaultValue: false)
            t.column(fileFileSize)
        })
        
        // Migrate existing databases: add is_indexed column if it doesn't exist
        do {
            try db.run("ALTER TABLE files ADD COLUMN is_indexed INTEGER DEFAULT 0")
        } catch {
            // Column already exists, ignore
        }
        
        // Create indexes
        try db.run(messages.createIndex(messageConversationId, ifNotExists: true))
        try db.run(conversations.createIndex(conversationUpdatedAt, ifNotExists: true))
    }
    
    /// Save a conversation to the database
    /// - Parameter conversation: The conversation to save
    public func saveConversation(_ conversation: Conversation) throws {
        // Encode agent configuration to JSON string
        let agentConfigJson: String?
        if let config = conversation.agentConfiguration {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(config),
               let jsonString = String(data: data, encoding: .utf8) {
                agentConfigJson = jsonString
            } else {
                agentConfigJson = nil
            }
        } else {
            agentConfigJson = nil
        }
        
        // Try to update first, if that fails, insert
        let updateQuery = conversations.filter(conversationId == conversation.id)
        let update = updateQuery.update(
            conversationTitle <- conversation.title,
            conversationUpdatedAt <- conversation.updatedAt,
            conversationIsEphemeral <- conversation.isEphemeral,
            conversationAgentConfig <- agentConfigJson,
            conversationSummary <- conversation.summary,
            conversationTokenUsage <- conversation.tokenUsage
        )
        
        if try db.run(update) == 0 {
            // No rows updated, so insert
            let insert = conversations.insert(
                conversationId <- conversation.id,
                conversationTitle <- conversation.title,
                conversationCreatedAt <- conversation.createdAt,
                conversationUpdatedAt <- conversation.updatedAt,
                conversationIsEphemeral <- conversation.isEphemeral,
                conversationAgentConfig <- agentConfigJson,
                conversationSummary <- conversation.summary,
                conversationTokenUsage <- conversation.tokenUsage
            )
            try db.run(insert)
        }
    }
    
    /// Load all conversations from the database
    /// - Returns: Array of conversations sorted by updated date (newest first)
    public func loadConversations() throws -> [Conversation] {
        
        var result: [Conversation] = []
        
        for row in try db.prepare(conversations.order(conversationUpdatedAt.desc)) {
            let id = row[conversationId]
            let title = row[conversationTitle]
            let createdAt = row[conversationCreatedAt]
            let updatedAt = row[conversationUpdatedAt]
            let isEphemeral = row[conversationIsEphemeral]
            let agentConfigJson = try? row.get(conversationAgentConfig)
            let summary = try? row.get(conversationSummary)
            let tokenUsage = try? row.get(conversationTokenUsage)
            
            // Decode agent configuration from JSON
            let agentConfig: AgentConfiguration?
            if let jsonString = agentConfigJson,
               let data = jsonString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(AgentConfiguration.self, from: data) {
                agentConfig = decoded
            } else {
                agentConfig = nil
            }
            
            // Load messages for this conversation
            let conversationMessages = try loadMessages(for: id)
            
            let conversation = Conversation(
                id: id,
                title: title,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isEphemeral: isEphemeral,
                messages: conversationMessages,
                agentConfiguration: agentConfig,
                summary: summary,
                tokenUsage: tokenUsage
            )
            
            result.append(conversation)
        }
        
        return result
    }
    
    /// Load a specific conversation by ID
    /// - Parameter id: The conversation ID
    /// - Returns: The conversation if found, nil otherwise
    public func loadConversation(id: UUID) throws -> Conversation? {
        
        let query = conversations.filter(conversationId == id)
        guard let row = try db.pluck(query) else {
            return nil
        }
        
        let conversationId = row[conversationId]
        let title = row[conversationTitle]
        let createdAt = row[conversationCreatedAt]
        let updatedAt = row[conversationUpdatedAt]
        let isEphemeral = row[conversationIsEphemeral]
        let agentConfigJson = try? row.get(conversationAgentConfig)
        let summary = try? row.get(conversationSummary)
        let tokenUsage = try? row.get(conversationTokenUsage)
        
        // Decode agent configuration from JSON
        let agentConfig: AgentConfiguration?
        if let jsonString = agentConfigJson,
           let data = jsonString.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AgentConfiguration.self, from: data) {
            agentConfig = decoded
        } else {
            agentConfig = nil
        }
        
        let conversationMessages = try loadMessages(for: conversationId)
        
        return Conversation(
            id: conversationId,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isEphemeral: isEphemeral,
            messages: conversationMessages,
            agentConfiguration: agentConfig,
            summary: summary,
            tokenUsage: tokenUsage
        )
    }
    
    /// Delete a conversation and all its messages
    /// - Parameter id: The conversation ID
    public func deleteConversation(id: UUID) throws {
        
        let query = conversations.filter(conversationId == id)
        try db.run(query.delete())
        // Messages are deleted via foreign key cascade
    }
    
    /// Load messages for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of messages sorted by timestamp
    private func loadMessages(for conversationId: UUID) throws -> [Message] {
        
        var result: [Message] = []
        
        let query = messages.filter(messageConversationId == conversationId).order(messageTimestamp.asc)
        
        for row in try db.prepare(query) {
            let id = row[messageId]
            let roleString = row[messageRole]
            let role = MessageRole(rawValue: roleString) ?? .user
            let content = row[messageContent]
            let timestamp = row[messageTimestamp]
            let toolCallsJson = try? row.get(messageToolCalls)
            let attachmentsJson = try? row.get(messageAttachments)
            
            // Parse tool calls if present
            var toolCalls: [ToolCall] = []
            if let toolCallsJson = toolCallsJson,
               let data = toolCallsJson.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([ToolCall].self, from: data) {
                toolCalls = decoded
            }
            
            // Parse attachments if present
            var attachments: [FileAttachment] = []
            if let attachmentsJson = attachmentsJson,
               let data = attachmentsJson.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([FileAttachment].self, from: data) {
                attachments = decoded
            }
            
            let message = Message(
                id: id,
                role: role,
                content: content,
                timestamp: timestamp,
                toolCalls: toolCalls,
                attachments: attachments
            )
            
            result.append(message)
        }
        
        return result
    }
    
    /// Save a message to the database
    /// - Parameters:
    ///   - message: The message to save
    ///   - conversationId: The conversation ID this message belongs to
    public func saveMessage(_ message: Message, conversationId: UUID) throws {
        
        // Encode tool calls as JSON
        let toolCallsJson: String?
        if message.toolCalls.isEmpty {
            toolCallsJson = nil
        } else {
            let encoder = JSONEncoder()
            toolCallsJson = try? String(data: encoder.encode(message.toolCalls), encoding: .utf8)
        }
        
        // Encode attachments as JSON
        let attachmentsJson: String?
        if message.attachments.isEmpty {
            attachmentsJson = nil
        } else {
            let encoder = JSONEncoder()
            attachmentsJson = try? String(data: encoder.encode(message.attachments), encoding: .utf8)
        }
        
        let insert = messages.insert(
            messageId <- message.id,
            messageConversationId <- conversationId,
            messageRole <- message.role.rawValue,
            messageContent <- message.content,
            messageTimestamp <- message.timestamp,
            messageToolCalls <- toolCallsJson,
            messageAttachments <- attachmentsJson
        )
        
        // Try to update first, if that fails, insert
        let updateQuery = messages.filter(messageId == message.id)
        let update = updateQuery.update(
            messageConversationId <- conversationId,
            messageRole <- message.role.rawValue,
            messageContent <- message.content,
            messageTimestamp <- message.timestamp,
            messageToolCalls <- toolCallsJson,
            messageAttachments <- attachmentsJson
        )
        
        if try db.run(update) == 0 {
            // No rows updated, so insert
            try db.run(insert)
        }
        
        // Update conversation's updated_at timestamp
        let conversation = conversations.filter(self.conversationId == conversationId)
        try db.run(conversation.update(conversationUpdatedAt <- Date()))
    }
    
    /// Save file metadata to the database
    /// - Parameter file: The file metadata to save
    public func saveFile(_ file: FileMetadata) throws {
        
        // Try to update first, if that fails, insert
        let updateQuery = files.filter(fileId == file.id)
        let update = updateQuery.update(
            fileEmbeddingCount <- file.embeddingCount,
            fileIsIndexed <- file.isIndexed
        )
        
        if try db.run(update) == 0 {
            // No rows updated, so insert
            let insert = files.insert(
                fileId <- file.id,
                fileFilename <- file.filename,
                fileFilepath <- file.filepath,
                fileFileType <- file.fileType.rawValue,
                fileIndexedAt <- file.indexedAt,
                fileEmbeddingCount <- file.embeddingCount,
                fileIsIndexed <- file.isIndexed,
                fileFileSize <- file.fileSize
            )
            try db.run(insert)
        }
    }
    
    /// Load all files from the database
    /// - Returns: Array of file metadata sorted by indexed date (newest first)
    public func loadFiles() throws -> [FileMetadata] {
        
        var result: [FileMetadata] = []
        
        for row in try db.prepare(files.order(fileIndexedAt.desc)) {
            let id = row[fileId]
            let filename = row[fileFilename]
            let filepath = row[fileFilepath]
            let fileTypeString = row[fileFileType]
            let fileType = FileType(rawValue: fileTypeString) ?? .unknown
            let indexedAt = row[fileIndexedAt]
            let embeddingCount = row[fileEmbeddingCount]
            let isIndexed = row[fileIsIndexed]
            let fileSize = row[fileFileSize]
            
            let file = FileMetadata(
                id: id,
                filename: filename,
                filepath: filepath,
                fileType: fileType,
                indexedAt: indexedAt,
                embeddingCount: embeddingCount,
                isIndexed: isIndexed,
                fileSize: fileSize
            )
            
            result.append(file)
        }
        
        return result
    }
    
    /// Delete a file from the database
    /// - Parameter id: The file ID
    public func deleteFile(id: UUID) throws {
        
        let query = files.filter(fileId == id)
        try db.run(query.delete())
    }
}

/// Database errors
@available(macOS 26.0, iOS 26.0, *)
public enum DatabaseError: LocalizedError {
    case notInitialized
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

