//
//  WorkflowCheckpoint.swift
//  FoundationChatCore
//
//  Workflow checkpoint for state persistence and resumption
//

import Foundation

/// A checkpoint representing the state of an orchestration workflow at a specific point
@available(macOS 26.0, iOS 26.0, *)
public struct WorkflowCheckpoint: Sendable, Codable {
    /// Unique identifier for this checkpoint
    public let id: UUID
    
    /// Conversation ID this checkpoint belongs to
    public let conversationId: UUID
    
    /// Message ID this checkpoint is associated with
    public let messageId: UUID
    
    /// Current orchestration phase when checkpoint was created
    public let phase: OrchestrationPhase
    
    /// Full orchestration state at checkpoint time
    public let orchestrationState: OrchestrationState
    
    /// Task that was being executed (encoded as JSON string)
    private let taskData: String
    
    /// Agent context at checkpoint time (encoded as JSON string)
    private let contextData: String
    
    /// Available agents at checkpoint time
    public let availableAgentIds: [UUID]
    
    /// Timestamp when checkpoint was created
    public let createdAt: Date
    
    /// Optional description of the checkpoint
    public let description: String?
    
    /// Whether this checkpoint can be used to resume execution
    public let canResume: Bool
    
    /// Task that was being executed (computed property)
    public var task: AgentTask {
        get throws {
            guard let data = taskData.data(using: .utf8) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid task data"))
            }
            return try JSONDecoder().decode(AgentTaskCodable.self, from: data).toAgentTask()
        }
    }
    
    /// Agent context at checkpoint time (computed property)
    public var context: AgentContext {
        get throws {
            guard let data = contextData.data(using: .utf8) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid context data"))
            }
            return try JSONDecoder().decode(AgentContextCodable.self, from: data).toAgentContext()
        }
    }
    
    public init(
        id: UUID = UUID(),
        conversationId: UUID,
        messageId: UUID,
        phase: OrchestrationPhase,
        orchestrationState: OrchestrationState,
        task: AgentTask,
        context: AgentContext,
        availableAgentIds: [UUID],
        createdAt: Date = Date(),
        description: String? = nil,
        canResume: Bool = true
    ) throws {
        self.id = id
        self.conversationId = conversationId
        self.messageId = messageId
        self.phase = phase
        self.orchestrationState = orchestrationState
        self.availableAgentIds = availableAgentIds
        self.createdAt = createdAt
        self.description = description
        self.canResume = canResume
        
        // Encode task and context as JSON strings
        let taskCodable = AgentTaskCodable(from: task)
        let contextCodable = AgentContextCodable(from: context)
        
        let taskEncoder = JSONEncoder()
        let contextEncoder = JSONEncoder()
        
        self.taskData = try String(data: taskEncoder.encode(taskCodable), encoding: .utf8) ?? ""
        self.contextData = try String(data: contextEncoder.encode(contextCodable), encoding: .utf8) ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case id, conversationId, messageId, phase, orchestrationState
        case taskData, contextData, availableAgentIds, createdAt, description, canResume
    }
    
    /// Create a checkpoint from current orchestration state
    public static func create(
        conversationId: UUID,
        messageId: UUID,
        phase: OrchestrationPhase,
        orchestrationState: OrchestrationState,
        task: AgentTask,
        context: AgentContext,
        availableAgents: [any Agent],
        description: String? = nil
    ) throws -> WorkflowCheckpoint {
        return try WorkflowCheckpoint(
            conversationId: conversationId,
            messageId: messageId,
            phase: phase,
            orchestrationState: orchestrationState,
            task: task,
            context: context,
            availableAgentIds: availableAgents.map { $0.id },
            description: description,
            canResume: phase != .complete && phase != .failed
        )
    }
}

/// Codable wrapper for AgentTask
@available(macOS 26.0, iOS 26.0, *)
private struct AgentTaskCodable: Codable {
    let id: UUID
    let description: String
    let requiredCapabilities: [String]
    let priority: Int
    let parameters: [String: String]
    
    init(from task: AgentTask) {
        self.id = task.id
        self.description = task.description
        self.requiredCapabilities = task.requiredCapabilities.map { $0.rawValue }
        self.priority = task.priority
        self.parameters = task.parameters
    }
    
    func toAgentTask() -> AgentTask {
        return AgentTask(
            id: id,
            description: description,
            requiredCapabilities: Set(requiredCapabilities.compactMap { AgentCapability(rawValue: $0) }),
            priority: priority,
            parameters: parameters
        )
    }
}

/// Codable wrapper for AgentContext
@available(macOS 26.0, iOS 26.0, *)
private struct AgentContextCodable: Codable {
    let conversationHistory: [Message]
    let userPreferences: [String: String]
    let fileReferences: [String]
    let ragChunks: [DocumentChunk]
    let toolResults: [String: String]
    let agentState: [String: [String: String]]
    let metadata: [String: String]
    
    init(from context: AgentContext) {
        self.conversationHistory = context.conversationHistory
        self.userPreferences = context.userPreferences
        self.fileReferences = context.fileReferences
        self.ragChunks = context.ragChunks
        self.toolResults = context.toolResults
        // Convert UUID keys to strings for encoding
        self.agentState = Dictionary(uniqueKeysWithValues: context.agentState.map { ($0.key.uuidString, $0.value) })
        self.metadata = context.metadata
    }
    
    func toAgentContext() -> AgentContext {
        // Convert string keys back to UUIDs
        let agentState: [UUID: [String: String]] = Dictionary(uniqueKeysWithValues: self.agentState.compactMap { (key: String, value: [String: String]) -> (UUID, [String: String])? in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, value)
        })
        
        return AgentContext(
            conversationHistory: conversationHistory,
            userPreferences: userPreferences,
            fileReferences: fileReferences,
            ragChunks: ragChunks,
            toolResults: toolResults,
            agentState: agentState,
            metadata: metadata
        )
    }
}

/// Checkpoint metadata for database storage
@available(macOS 26.0, iOS 26.0, *)
public struct CheckpointMetadata: Sendable, Codable {
    public let id: UUID
    public let conversationId: UUID
    public let messageId: UUID
    public let phase: OrchestrationPhase
    public let createdAt: Date
    public let description: String?
    public let canResume: Bool
    
    public init(from checkpoint: WorkflowCheckpoint) {
        self.id = checkpoint.id
        self.conversationId = checkpoint.conversationId
        self.messageId = checkpoint.messageId
        self.phase = checkpoint.phase
        self.createdAt = checkpoint.createdAt
        self.description = checkpoint.description
        self.canResume = checkpoint.canResume
    }
}

