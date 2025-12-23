//
//  MessageChunk.swift
//  FoundationChatCore
//
//  Model representing a chunk of a message with its embedding for RAG
//

import Foundation

/// Represents a chunk of a message with its vector embedding for RAG
@available(macOS 26.0, iOS 26.0, *)
public struct MessageChunk: Identifiable, Codable, Sendable {
    /// Unique chunk identifier
    public let id: UUID
    
    /// Reference to the Message this chunk belongs to
    public let messageId: UUID
    
    /// Conversation this message belongs to
    public let conversationId: UUID
    
    /// Order of chunk in the message (0-indexed)
    public let chunkIndex: Int
    
    /// Role of the message (user, assistant, system)
    public let role: MessageRole
    
    /// Chunk text content
    public let content: String
    
    /// Timestamp of the original message
    public let timestamp: Date
    
    /// Vector embedding for semantic search
    public let embedding: [Float]
    
    /// Additional metadata (score, etc.)
    public var metadata: [String: String]
    
    public init(
        id: UUID = UUID(),
        messageId: UUID,
        conversationId: UUID,
        chunkIndex: Int,
        role: MessageRole,
        content: String,
        timestamp: Date,
        embedding: [Float],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.chunkIndex = chunkIndex
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.embedding = embedding
        self.metadata = metadata
    }
}


