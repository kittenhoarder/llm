//
//  OrchestrationProgress.swift
//  FoundationChatCore
//
//  Progress tracking and event emission for agent orchestration
//

import Foundation

/// Events emitted during orchestration to track progress
@available(macOS 26.0, iOS 26.0, *)
public enum OrchestrationProgressEvent: Sendable {
    /// Coordinator made a delegation decision
    case delegationDecision(shouldDelegate: Bool, reason: String?)
    
    /// Coordinator started analyzing the task
    case coordinatorAnalysisStarted
    
    /// Coordinator completed analysis
    case coordinatorAnalysisCompleted(analysis: String)
    
    /// Task decomposition was parsed
    case taskDecomposition(decomposition: TaskDecomposition)
    
    /// A subtask was pruned (removed)
    case subtaskPruned(subtaskId: UUID, rationale: String)
    
    /// A subtask execution started
    case subtaskStarted(subtask: DecomposedSubtask, agentId: UUID, agentName: String)
    
    /// A subtask execution completed
    case subtaskCompleted(subtask: DecomposedSubtask, result: AgentResult)
    
    /// A subtask execution failed
    case subtaskFailed(subtask: DecomposedSubtask, error: String)
    
    /// Coordinator started synthesizing results
    case synthesisStarted
    
    /// Coordinator completed synthesis
    case synthesisCompleted
    
    /// Orchestration completed with final metrics
    case orchestrationCompleted(metrics: DelegationMetrics)
    
    /// Orchestration failed
    case orchestrationFailed(error: String)
}

/// Thread-safe actor for tracking orchestration progress and emitting events
@available(macOS 26.0, iOS 26.0, *)
public actor OrchestrationProgressTracker {
    /// Continuation for the async stream
    private var continuation: AsyncStream<OrchestrationProgressEvent>.Continuation?
    
    /// Current state snapshot
    private var currentState: OrchestrationState?
    
    /// Initialize the tracker
    public init() {}
    
    /// Start tracking and return an async stream of events
    /// - Returns: AsyncStream of orchestration progress events
    public func startTracking() -> AsyncStream<OrchestrationProgressEvent> {
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }
    
    /// Emit a progress event
    /// - Parameter event: The event to emit
    public func emit(_ event: OrchestrationProgressEvent) {
        continuation?.yield(event)
    }
    
    /// Finish tracking (close the stream)
    public func finish() {
        continuation?.finish()
        continuation = nil
    }
    
    /// Get current state snapshot
    /// - Returns: Current orchestration state, if available
    public func getCurrentState() -> OrchestrationState? {
        return currentState
    }
    
    /// Update current state
    /// - Parameter state: New state
    public func updateState(_ state: OrchestrationState) {
        self.currentState = state
    }
}

