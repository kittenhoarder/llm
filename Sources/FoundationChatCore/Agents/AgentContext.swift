//
//  AgentContext.swift
//  FoundationChatCore
//
//  Shared context structure for agent communication
//

import Foundation

/// Shared context containing information available to all agents
@available(macOS 26.0, iOS 26.0, *)
public struct AgentContext: Sendable {
    /// Conversation history
    public var conversationHistory: [Message]
    
    /// User preferences or settings
    public var userPreferences: [String: String]
    
    /// File references (file paths or identifiers)
    public var fileReferences: [String]
    
    /// RAG chunks retrieved for current query
    public var ragChunks: [DocumentChunk]
    
    /// Tool results from previous operations
    public var toolResults: [String: String]
    
    /// Agent-specific state
    public var agentState: [UUID: [String: String]]
    
    /// Additional metadata
    public var metadata: [String: String]
    
    public init(
        conversationHistory: [Message] = [],
        userPreferences: [String: String] = [:],
        fileReferences: [String] = [],
        ragChunks: [DocumentChunk] = [],
        toolResults: [String: String] = [:],
        agentState: [UUID: [String: String]] = [:],
        metadata: [String: String] = [:]
    ) {
        self.conversationHistory = conversationHistory
        self.userPreferences = userPreferences
        self.fileReferences = fileReferences
        self.ragChunks = ragChunks
        self.toolResults = toolResults
        self.agentState = agentState
        self.metadata = metadata
    }
    
    /// Merge another context into this one
    public mutating func merge(_ other: AgentContext) {
        conversationHistory.append(contentsOf: other.conversationHistory)
        userPreferences.merge(other.userPreferences) { _, new in new }
        fileReferences.append(contentsOf: other.fileReferences)
        ragChunks.append(contentsOf: other.ragChunks)
        toolResults.merge(other.toolResults) { _, new in new }
        for (agentId, state) in other.agentState {
            agentState[agentId, default: [:]].merge(state) { _, new in new }
        }
        metadata.merge(other.metadata) { _, new in new }
    }
}

/// Represents a task for an agent to process
@available(macOS 26.0, iOS 26.0, *)
public struct AgentTask: Sendable {
    /// Unique identifier for this task
    public let id: UUID
    
    /// The task description or prompt
    public let description: String
    
    /// Required capabilities for this task
    public let requiredCapabilities: Set<AgentCapability>
    
    /// Priority level (higher = more important)
    public let priority: Int
    
    /// Additional parameters
    public var parameters: [String: String]
    
    public init(
        id: UUID = UUID(),
        description: String,
        requiredCapabilities: Set<AgentCapability> = [],
        priority: Int = 0,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.description = description
        self.requiredCapabilities = requiredCapabilities
        self.priority = priority
        self.parameters = parameters
    }
}

/// Result from an agent processing a task
@available(macOS 26.0, iOS 26.0, *)
public struct AgentResult: Sendable, Codable {
    /// The agent that produced this result
    public let agentId: UUID
    
    /// The task that was processed
    public let taskId: UUID
    
    /// The result content
    public let content: String
    
    /// Whether the task was completed successfully
    public let success: Bool
    
    /// Any errors that occurred
    public let error: String?
    
    /// Additional data from the agent
    public var data: [String: String]
    
    /// Tool calls made during processing
    public var toolCalls: [ToolCall]
    
    /// Updated context after processing (not persisted)
    public var updatedContext: AgentContext?
    
    enum CodingKeys: String, CodingKey {
        case agentId, taskId, content, success, error, data, toolCalls
        // updatedContext is excluded from encoding
    }
    
    public init(
        agentId: UUID,
        taskId: UUID,
        content: String,
        success: Bool = true,
        error: String? = nil,
        data: [String: String] = [:],
        toolCalls: [ToolCall] = [],
        updatedContext: AgentContext? = nil
    ) {
        self.agentId = agentId
        self.taskId = taskId
        self.content = content
        self.success = success
        self.error = error
        self.data = data
        self.toolCalls = toolCalls
        self.updatedContext = updatedContext
    }
}





