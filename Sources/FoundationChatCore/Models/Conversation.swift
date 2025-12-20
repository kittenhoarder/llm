//
//  Conversation.swift
//  FoundationChatCore
//
//  Model representing a conversation thread
//

import Foundation

/// Represents a conversation thread with messages
@available(macOS 26.0, iOS 26.0, *)
public struct Conversation: Identifiable, Codable, Sendable {
    /// Unique identifier for the conversation
    public let id: UUID
    
    /// Title of the conversation (auto-generated or user-edited)
    public var title: String
    
    /// When the conversation was created
    public let createdAt: Date
    
    /// When the conversation was last updated
    public var updatedAt: Date
    
    /// Whether this conversation should be stored persistently
    public var isEphemeral: Bool
    
    /// Messages in this conversation
    public var messages: [Message]
    
    /// Type of conversation
    public var conversationType: ConversationType
    
    /// Agent configuration (only for agent-based conversations)
    public var agentConfiguration: AgentConfiguration?
    
    /// Conversation summary (for context compaction)
    public var summary: String?
    
    /// Token usage tracking
    public var tokenUsage: Int?
    
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isEphemeral: Bool = false,
        messages: [Message] = [],
        conversationType: ConversationType = .chat,
        agentConfiguration: AgentConfiguration? = nil,
        summary: String? = nil,
        tokenUsage: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isEphemeral = isEphemeral
        self.messages = messages
        self.conversationType = conversationType
        self.agentConfiguration = agentConfiguration
        self.summary = summary
        self.tokenUsage = tokenUsage
    }
    
    /// Auto-generate a title from the first user message
    public mutating func generateTitle() {
        if let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let preview = String(firstUserMessage.content.prefix(50))
            self.title = preview.isEmpty ? "New Conversation" : preview
            if firstUserMessage.content.count > 50 {
                self.title += "..."
            }
        } else {
            self.title = "New Conversation"
        }
    }
}


