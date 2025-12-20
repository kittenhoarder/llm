//
//  DocumentChunk.swift
//  FoundationChatCore
//
//  Model representing a chunk of a document with its embedding
//

import Foundation

/// Represents a chunk of a document with its vector embedding for RAG
@available(macOS 26.0, iOS 26.0, *)
public struct DocumentChunk: Identifiable, Codable, Sendable {
    /// Unique chunk identifier
    public let id: UUID
    
    /// Reference to the FileAttachment this chunk belongs to
    public let fileId: UUID
    
    /// Conversation this file belongs to
    public let conversationId: UUID
    
    /// Order of chunk in the file (0-indexed)
    public let chunkIndex: Int
    
    /// Chunk text content
    public let content: String
    
    /// Vector embedding for semantic search
    public let embedding: [Float]
    
    /// Additional metadata (line numbers, section, etc.)
    public var metadata: [String: String]
    
    public init(
        id: UUID = UUID(),
        fileId: UUID,
        conversationId: UUID,
        chunkIndex: Int,
        content: String,
        embedding: [Float],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.fileId = fileId
        self.conversationId = conversationId
        self.chunkIndex = chunkIndex
        self.content = content
        self.embedding = embedding
        self.metadata = metadata
    }
}

