//
//  OrchestrationVisualization.swift
//  FoundationChatCore
//
//  Models for visualizing agent orchestration state
//

import Foundation

/// Current phase of orchestration
@available(macOS 26.0, iOS 26.0, *)
public enum OrchestrationPhase: String, Sendable, Codable {
    case decision = "Decision"
    case analysis = "Analysis"
    case decomposition = "Decomposition"
    case execution = "Execution"
    case synthesis = "Synthesis"
    case complete = "Complete"
    case failed = "Failed"
}

/// Type of orchestration event
@available(macOS 26.0, iOS 26.0, *)
public enum OrchestrationEventType: String, Sendable, Codable {
    case phaseChange
    case delegationDecision
    case taskDecomposition
    case subtaskStarted
    case subtaskCompleted
    case subtaskFailed
    case subtaskRetry
    case synthesisStarted
    case synthesisCompleted
    case orchestrationCompleted
    case orchestrationFailed
}

/// A single event in the orchestration timeline
@available(macOS 26.0, iOS 26.0, *)
public struct OrchestrationEvent: Sendable, Codable {
    public let timestamp: Date
    public let eventType: OrchestrationEventType
    public let description: String
    public let subtaskId: UUID?
    public let agentName: String?
    public let metadata: [String: String]
    
    public init(
        timestamp: Date = Date(),
        eventType: OrchestrationEventType,
        description: String,
        subtaskId: UUID? = nil,
        agentName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.eventType = eventType
        self.description = description
        self.subtaskId = subtaskId
        self.agentName = agentName
        self.metadata = metadata
    }
}

/// Execution state of a subtask
@available(macOS 26.0, iOS 26.0, *)
public enum SubtaskExecutionState: Sendable, Equatable, Codable {
    case pending
    case inProgress(agentId: UUID, agentName: String, startTime: Date)
    case completed(AgentResult)
    case failed(String, retryAttempts: [RetryAttempt])
    
    public init(pending: Void) {
        self = .pending
    }
    
    public init(inProgress agentId: UUID, agentName: String, startTime: Date) {
        self = .inProgress(agentId: agentId, agentName: agentName, startTime: startTime)
    }
    
    public init(completed result: AgentResult) {
        self = .completed(result)
    }
    
    public init(failed error: String, retryAttempts: [RetryAttempt] = []) {
        self = .failed(error, retryAttempts: retryAttempts)
    }
    
    public static func == (lhs: SubtaskExecutionState, rhs: SubtaskExecutionState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending):
            return true
        case (.inProgress(let lhsId, let lhsName, _), .inProgress(let rhsId, let rhsName, _)):
            return lhsId == rhsId && lhsName == rhsName
        case (.completed(let lhsResult), .completed(let rhsResult)):
            return lhsResult.agentId == rhsResult.agentId && lhsResult.taskId == rhsResult.taskId
        case (.failed(let lhsError, let lhsRetries), .failed(let rhsError, let rhsRetries)):
            return lhsError == rhsError && lhsRetries.count == rhsRetries.count
        default:
            return false
        }
    }
    
    /// Get retry attempts count
    public var retryAttemptsCount: Int {
        switch self {
        case .failed(_, let retries):
            return retries.count
        default:
            return 0
        }
    }
    
    /// Get the error message if failed
    public var errorMessage: String? {
        switch self {
        case .failed(let error, _):
            return error
        default:
            return nil
        }
    }
}

/// Complete orchestration state for visualization
@available(macOS 26.0, iOS 26.0, *)
public struct OrchestrationState: Sendable, Codable {
    /// Current phase of orchestration
    public var currentPhase: OrchestrationPhase
    
    /// Whether coordinator decided to delegate
    public var shouldDelegate: Bool?
    
    /// Delegation decision reason
    public var delegationReason: String?
    
    /// Task decomposition (if available)
    public var decomposition: TaskDecomposition?
    
    /// Execution state of each subtask
    public var subtaskStates: [UUID: SubtaskExecutionState]
    
    /// Completed subtask results
    public var completedSubtasks: [UUID: AgentResult]
    
    /// Parallel execution groups
    public var parallelGroups: [[DecomposedSubtask]]
    
    /// Final metrics (when complete)
    public var metrics: DelegationMetrics?
    
    /// Error message (if failed)
    public var error: String?
    
    /// Coordinator analysis output
    public var coordinatorAnalysis: String?
    
    /// Chronological history of orchestration events
    public var eventHistory: [OrchestrationEvent]
    
    public init(
        currentPhase: OrchestrationPhase = .decision,
        shouldDelegate: Bool? = nil,
        delegationReason: String? = nil,
        decomposition: TaskDecomposition? = nil,
        subtaskStates: [UUID: SubtaskExecutionState] = [:],
        completedSubtasks: [UUID: AgentResult] = [:],
        parallelGroups: [[DecomposedSubtask]] = [],
        metrics: DelegationMetrics? = nil,
        error: String? = nil,
        coordinatorAnalysis: String? = nil,
        eventHistory: [OrchestrationEvent] = []
    ) {
        self.currentPhase = currentPhase
        self.shouldDelegate = shouldDelegate
        self.delegationReason = delegationReason
        self.decomposition = decomposition
        self.subtaskStates = subtaskStates
        self.completedSubtasks = completedSubtasks
        self.parallelGroups = parallelGroups
        self.metrics = metrics
        self.error = error
        self.coordinatorAnalysis = coordinatorAnalysis
        self.eventHistory = eventHistory
    }
    
    /// Get all subtasks from decomposition
    public var allSubtasks: [DecomposedSubtask] {
        return decomposition?.subtasks ?? []
    }
    
    /// Get active (in-progress) subtasks
    public var activeSubtasks: [(UUID, SubtaskExecutionState)] {
        return subtaskStates.compactMap { id, state in
            if case .inProgress = state {
                return (id, state)
            }
            return nil
        }
    }
    
    /// Get pending subtasks
    public var pendingSubtasks: [DecomposedSubtask] {
        return allSubtasks.filter { subtask in
            if case .pending = subtaskStates[subtask.id] {
                return true
            }
            return subtaskStates[subtask.id] == nil
        }
    }
    
    /// Check if orchestration is complete
    public var isComplete: Bool {
        return currentPhase == .complete || currentPhase == .failed
    }
}

