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
        Log.debug("💬 ConversationService init() called")
        Log.debug("💬 Thread: \(Thread.isMainThread ? "Main" : "Background")")
        Log.debug("💬 About to create DatabaseManager...")
        self.dbManager = try DatabaseManager(dbPath: dbPath)
        Log.debug("✅ ConversationService init() complete")
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
            Log.warn("⚠️ Error deleting files for conversation \(id): \(error)")
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
    ///   - indexImmediately: If true, wait for indexing to complete (for current message). If false, index asynchronously (for assistant responses)
    nonisolated public func addMessage(_ message: Message, to conversationId: UUID, indexImmediately: Bool = false) async throws {
        // Load conversation to check if it's ephemeral
        if let conversation = try dbManager.loadConversation(id: conversationId), !conversation.isEphemeral {
            try dbManager.saveMessage(message, conversationId: conversationId)
            
            if indexImmediately {
                // Index synchronously for current user message (needed for immediate context building)
                do {
                    try await RAGService.shared.indexMessage(message, conversationId: conversationId)
                    Log.debug("✅ ConversationService: Indexed message \(message.id) immediately")
                } catch {
                    // Log error but don't fail message save
                    Log.warn("⚠️ ConversationService: Failed to index message \(message.id) in SVDB: \(error.localizedDescription)")
                }
            } else {
                // Index asynchronously for assistant responses (don't block)
                Task {
                    do {
                        try await RAGService.shared.indexMessage(message, conversationId: conversationId)
                    } catch {
                        // Log error but don't fail message save
                        Log.warn("⚠️ ConversationService: Failed to index message \(message.id) in SVDB: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    /// Index existing conversation history in SVDB
    /// - Parameter conversationId: The conversation ID
    /// - Throws: RAGError if indexing fails
    public func indexExistingConversationHistory(_ conversationId: UUID) async throws {
        guard let conversation = try dbManager.loadConversation(id: conversationId) else {
            throw NSError(domain: "ConversationService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
        }
        
        guard !conversation.isEphemeral else {
            Log.debug("ℹ️ ConversationService: Skipping ephemeral conversation \(conversationId)")
            return
        }
        
        let messages = conversation.messages
        guard !messages.isEmpty else {
            Log.debug("ℹ️ ConversationService: No messages to index for conversation \(conversationId)")
            return
        }
        
        Log.debug("📝 ConversationService: Indexing \(messages.count) messages for conversation \(conversationId)")
        try await RAGService.shared.indexConversationHistory(messages, conversationId: conversationId)
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
    
    /// Save orchestration state for a message
    /// - Parameters:
    ///   - state: The orchestration state
    ///   - messageId: The message ID
    public func saveOrchestrationState(_ state: OrchestrationState, for messageId: UUID) throws {
        try dbManager.saveOrchestrationState(state, for: messageId)
    }
    
    /// Load orchestration states for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Dictionary mapping message ID to orchestration state
    public func loadOrchestrationStates(for conversationId: UUID) throws -> [UUID: OrchestrationState] {
        return try dbManager.loadOrchestrationStates(for: conversationId)
    }
    
    /// Save a workflow checkpoint
    /// - Parameter checkpoint: The checkpoint to save
    public func saveWorkflowCheckpoint(_ checkpoint: WorkflowCheckpoint) throws {
        try dbManager.saveWorkflowCheckpoint(checkpoint)
    }
    
    /// Load a workflow checkpoint by ID
    /// - Parameter id: The checkpoint ID
    /// - Returns: The checkpoint if found
    public func loadWorkflowCheckpoint(id: UUID) throws -> WorkflowCheckpoint? {
        return try dbManager.loadWorkflowCheckpoint(id: id)
    }
    
    /// Load all checkpoints for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of checkpoints sorted by creation date
    public func loadWorkflowCheckpoints(for conversationId: UUID) throws -> [WorkflowCheckpoint] {
        return try dbManager.loadWorkflowCheckpoints(for: conversationId)
    }
    
    /// Load all checkpoints for a message
    /// - Parameter messageId: The message ID
    /// - Returns: Array of checkpoints sorted by creation date
    public func loadWorkflowCheckpoints(forMessage messageId: UUID) throws -> [WorkflowCheckpoint] {
        return try dbManager.loadWorkflowCheckpoints(forMessage: messageId)
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
