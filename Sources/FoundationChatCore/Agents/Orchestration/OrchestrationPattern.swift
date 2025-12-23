//
//  OrchestrationPattern.swift
//  FoundationChatCore
//
//  Protocol for different orchestration patterns
//

import Foundation

/// Protocol defining how agents are orchestrated to complete tasks
@available(macOS 26.0, iOS 26.0, *)
public protocol OrchestrationPattern: Sendable {
    /// Execute a task using the provided agents
    /// - Parameters:
    ///   - task: The task to execute
    ///   - agents: Available agents to use
    ///   - context: Shared context
    ///   - progressTracker: Optional progress tracker for visualization
    ///   - checkpointCallback: Optional callback to save checkpoints (conversationId, messageId, checkpoint)
    /// - Returns: Result of execution
    func execute(
        task: AgentTask,
        agents: [any Agent],
        context: AgentContext,
        progressTracker: OrchestrationProgressTracker?,
        checkpointCallback: (@Sendable (WorkflowCheckpoint) async throws -> Void)?,
        cancellationToken: WorkflowCancellationToken?
    ) async throws -> AgentResult
}

/// Type of orchestration pattern
@available(macOS 26.0, iOS 26.0, *)
public enum OrchestrationPatternType: String, Codable, Sendable {
    /// Single coordinator delegates to specialists
    case orchestrator
    
    /// Peer-to-peer collaboration
    case collaborative
    
    /// Multi-level hierarchy
    case hierarchical
}





