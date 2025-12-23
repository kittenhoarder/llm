//
//  HierarchicalPattern.swift
//  FoundationChatCore
//
//  Hierarchical pattern: Multi-level agent hierarchy
//

import Foundation

/// Hierarchical pattern implementation
/// Multi-level hierarchy with supervisor agents managing subordinates
@available(macOS 26.0, iOS 26.0, *)
public struct HierarchicalPattern: OrchestrationPattern {
    /// Supervisor agent (manages the hierarchy)
    private let supervisor: any Agent
    
    public init(supervisor: any Agent) {
        self.supervisor = supervisor
    }
    
    public func execute(
        task: AgentTask,
        agents: [any Agent],
        context: AgentContext,
        progressTracker: OrchestrationProgressTracker? = nil,
        checkpointCallback: (@Sendable (WorkflowCheckpoint) async throws -> Void)? = nil,
        cancellationToken: WorkflowCancellationToken? = nil
    ) async throws -> AgentResult {
        try cancellationToken?.checkCancellation()
        guard !agents.isEmpty else {
            throw AgentOrchestratorError.noAgentsAvailable
        }
        
        // Step 1: Supervisor breaks down the task
        let breakdownTask = AgentTask(
            description: """
            Break down the following task into subtasks and assign them to specialized agents.
            
            Task: \(task.description)
            
            Available agents: \(agents.map { "\($0.name) (capabilities: \($0.capabilities.map { $0.rawValue }.joined(separator: ", ")))" }.joined(separator: "; "))
            
            Provide a hierarchical breakdown with:
            1. Main task decomposition
            2. Subtask assignments to specific agents
            3. Dependencies between subtasks
            """,
            requiredCapabilities: [.generalReasoning]
        )
        
        let breakdownResult = try await supervisor.process(task: breakdownTask, context: context)
        
        // Step 2: Execute subtasks in hierarchical order
        // For now, we'll use a simple approach: execute agents based on their capabilities
        var results: [AgentResult] = []
        var updatedContext = context
        updatedContext.toolResults["supervisorBreakdown"] = breakdownResult.content
        
        // Group agents by capability level (simplified hierarchy)
        let specializedAgents = agents.filter { $0.id != supervisor.id }
        
        // Execute specialized agents
        for agent in specializedAgents {
            try cancellationToken?.checkCancellation()
            
            // Check if this agent's capabilities match the task
            if task.requiredCapabilities.isEmpty || 
               !task.requiredCapabilities.isDisjoint(with: agent.capabilities) {
                let subtask = AgentTask(
                    description: """
                    \(task.description)
                    
                    Supervisor's breakdown:
                    \(breakdownResult.content)
                    """,
                    requiredCapabilities: task.requiredCapabilities,
                    priority: task.priority,
                    parameters: task.parameters
                )
                
                let result = try await agent.process(task: subtask, context: updatedContext)
                results.append(result)
                
                if let updated = result.updatedContext {
                    updatedContext.merge(updated)
                }
            }
        }
        
        // Step 3: Supervisor synthesizes results
        let synthesisTask = AgentTask(
            description: """
            Synthesize the following agent results into a final response:
            
            Original task: \(task.description)
            
            Agent results:
            \(results.enumerated().map { "Agent \($0.offset + 1): \($0.element.content)" }.joined(separator: "\n\n"))
            """,
            requiredCapabilities: [.generalReasoning]
        )
        
        let finalResult = try await supervisor.process(task: synthesisTask, context: updatedContext)
        
        return AgentResult(
            agentId: supervisor.id,
            taskId: task.id,
            content: finalResult.content,
            success: finalResult.success && results.allSatisfy { $0.success },
            error: finalResult.error ?? results.compactMap { $0.error }.first,
            toolCalls: [finalResult.toolCalls, results.flatMap { $0.toolCalls }].flatMap { $0 },
            updatedContext: updatedContext
        )
    }
}





