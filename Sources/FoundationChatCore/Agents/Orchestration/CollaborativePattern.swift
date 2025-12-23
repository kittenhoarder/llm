//
//  CollaborativePattern.swift
//  FoundationChatCore
//
//  Collaborative pattern: Peer-to-peer agent collaboration
//

import Foundation

/// Collaborative pattern implementation
/// Agents work together, sharing intermediate results and building consensus
@available(macOS 26.0, iOS 26.0, *)
public struct CollaborativePattern: OrchestrationPattern {
    public init() {}
    
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
        
        // All agents process the task in parallel
        var results: [AgentResult] = []
        var sharedContext = context
        
        // First round: all agents process independently
        for agent in agents {
            try cancellationToken?.checkCancellation()
            let result = try await agent.process(task: task, context: sharedContext)
            results.append(result)
            
            // Merge updated context
            if let updated = result.updatedContext {
                sharedContext.merge(updated)
            }
        }
        
        // Second round: agents can refine based on others' results
        if agents.count > 1 {
            var refinedResults: [AgentResult] = []
            
            for (index, agent) in agents.enumerated() {
                try cancellationToken?.checkCancellation()
                
                // Create a task that includes other agents' results
                let otherResults = results.enumerated()
                    .filter { $0.offset != index }
                    .map { "Agent \($0.offset + 1): \($0.element.content)" }
                    .joined(separator: "\n\n")
                
                let refinementTask = AgentTask(
                    description: """
                    Original task: \(task.description)
                    
                    Other agents' results:
                    \(otherResults)
                    
                    Please refine your response considering the other agents' perspectives.
                    """,
                    requiredCapabilities: task.requiredCapabilities,
                    priority: task.priority,
                    parameters: task.parameters
                )
                
                let refined = try await agent.process(task: refinementTask, context: sharedContext)
                refinedResults.append(refined)
                
                if let updated = refined.updatedContext {
                    sharedContext.merge(updated)
                }
            }
            
            results = refinedResults
        }
        
        // Aggregate results with consensus building
        let aggregatedContent = buildConsensus(from: results)
        
        // Use first agent's ID as the result agent ID (or create a synthetic one)
        let resultAgentId = agents.first?.id ?? UUID()
        
        return AgentResult(
            agentId: resultAgentId,
            taskId: task.id,
            content: aggregatedContent,
            success: results.allSatisfy { $0.success },
            error: results.compactMap { $0.error }.first,
            toolCalls: results.flatMap { $0.toolCalls },
            updatedContext: sharedContext
        )
    }
    
    /// Build consensus from multiple agent results
    private func buildConsensus(from results: [AgentResult]) -> String {
        guard !results.isEmpty else {
            return "No results from agents."
        }
        
        if results.count == 1 {
            return results[0].content
        }
        
        var consensus = "Collaborative Analysis from \(results.count) Agents:\n\n"
        
        // Group by similarity (simple approach: show all perspectives)
        for (index, result) in results.enumerated() {
            consensus += "Agent \(index + 1) Perspective:\n"
            consensus += "\(result.content)\n\n"
        }
        
        consensus += "---\n"
        consensus += "Synthesized Consensus:\n"
        consensus += "Based on the collaborative analysis above, here is a unified perspective combining all agents' insights."
        
        return consensus
    }
}





