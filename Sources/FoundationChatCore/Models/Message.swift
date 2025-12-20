//
//  Message.swift
//  FoundationChatCore
//
//  Model representing a single message in a conversation
//

import Foundation

/// Role of the message sender
@available(macOS 26.0, iOS 26.0, *)
public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// Represents a single message in a conversation
@available(macOS 26.0, iOS 26.0, *)
public struct Message: Identifiable, Codable, Sendable {
    /// Unique identifier for the message
    public let id: UUID
    
    /// Role of the message sender
    public let role: MessageRole
    
    /// Content of the message
    public var content: String
    
    /// When the message was created
    public let timestamp: Date
    
    /// Tool calls made during this message (if assistant message)
    public var toolCalls: [ToolCall]
    
    /// Response time in seconds (only for assistant messages)
    public var responseTime: TimeInterval?
    
    /// File attachments in this message
    public var attachments: [FileAttachment]
    
    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall] = [],
        responseTime: TimeInterval? = nil,
        attachments: [FileAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.responseTime = responseTime
        self.attachments = attachments
    }
}

/// Represents a tool call made during message generation
@available(macOS 26.0, iOS 26.0, *)
public struct ToolCall: Codable, Sendable {
    /// Name of the tool that was called
    public let toolName: String
    
    /// Arguments passed to the tool
    public let arguments: String
    
    /// Result returned by the tool
    public var result: String?
    
    public init(
        toolName: String,
        arguments: String,
        result: String? = nil
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
    }
}


