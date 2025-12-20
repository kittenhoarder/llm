//
//  ConversationService.swift
//  FoundationChatCore
//
//  High-level service for managing conversations
//

import Foundation

/// Service for managing conversations and messages
@available(macOS 26.0, iOS 26.0, *)
public class ConversationService {
    /// The database manager
    private let dbManager: DatabaseManager
    
    /// Initialize the conversation service
    /// - Parameter dbPath: Optional custom database path
    public init(dbPath: String? = nil) throws {
        print("💬 ConversationService init() called")
        print("💬 Thread: \(Thread.isMainThread ? "Main" : "Background")")
        print("💬 About to create DatabaseManager...")
        self.dbManager = try DatabaseManager(dbPath: dbPath)
        print("✅ ConversationService init() complete")
    }
    
    /// Create a new conversation
    /// - Parameters:
    ///   - title: Optional title (will be auto-generated if nil)
    ///   - isEphemeral: Whether this conversation should be stored
    /// - Returns: The created conversation
    public func createConversation(title: String? = nil, isEphemeral: Bool = false) throws -> Conversation {
        let conversation = Conversation(
            title: title ?? "New Conversation",
            isEphemeral: isEphemeral
        )
        
        // Only save if not ephemeral
        if !isEphemeral {
            try dbManager.saveConversation(conversation)
        }
        
        return conversation
    }
    
    /// Load all conversations
    /// - Returns: Array of conversations sorted by updated date
    public func loadConversations() throws -> [Conversation] {
        return try dbManager.loadConversations()
    }
    
    /// Load a specific conversation
    /// - Parameter id: The conversation ID
    /// - Returns: The conversation if found
    public func loadConversation(id: UUID) throws -> Conversation? {
        return try dbManager.loadConversation(id: id)
    }
    
    /// Update a conversation
    /// - Parameter conversation: The conversation to update
    public func updateConversation(_ conversation: Conversation) throws {
        // Only save if not ephemeral
        if !conversation.isEphemeral {
            try dbManager.saveConversation(conversation)
        }
    }
    
    /// Delete a conversation
    /// - Parameter id: The conversation ID
    nonisolated public func deleteConversation(id: UUID) async throws {
        // Delete all files associated with this conversation
        // This will also delete RAG indexes via FileManagerService
        let fileManagerService = FileManagerService.shared
        do {
            try await fileManagerService.deleteFilesForConversation(conversationId: id)
        } catch {
            // Log error but don't fail deletion - we still want to delete from database
            print("⚠️ Error deleting files for conversation \(id): \(error)")
        }
        
        // Delete from database
        // Capture dbManager to avoid isolation issues
        let db = self.dbManager
        try db.deleteConversation(id: id)
    }
    
    /// Add a message to a conversation
    /// - Parameters:
    ///   - message: The message to add
    ///   - conversationId: The conversation ID
    public func addMessage(_ message: Message, to conversationId: UUID) throws {
        // Load conversation to check if it's ephemeral
        if let conversation = try dbManager.loadConversation(id: conversationId), !conversation.isEphemeral {
            try dbManager.saveMessage(message, conversationId: conversationId)
        }
    }
    
    /// Update a message in a conversation
    /// - Parameters:
    ///   - message: The updated message
    ///   - conversationId: The conversation ID
    public func updateMessage(_ message: Message, in conversationId: UUID) throws {
        if let conversation = try dbManager.loadConversation(id: conversationId), !conversation.isEphemeral {
            try dbManager.saveMessage(message, conversationId: conversationId)
        }
    }
    
    /// Search conversations by title
    /// - Parameter query: Search query
    /// - Returns: Matching conversations
    public func searchConversations(query: String) throws -> [Conversation] {
        let allConversations = try loadConversations()
        let lowerQuery = query.lowercased()
        return allConversations.filter { conversation in
            conversation.title.lowercased().contains(lowerQuery)
        }
    }
}

