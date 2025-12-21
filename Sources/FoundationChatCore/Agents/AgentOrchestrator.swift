//
//  AgentOrchestrator.swift
//  FoundationChatCore
//
//  Orchestrator for coordinating multiple agents
//

import Foundation

/// Orchestrator managing agent coordination and task execution
@available(macOS 26.0, iOS 26.0, *)
public actor AgentOrchestrator {
    /// The agent registry
    private let registry: AgentRegistry
    
    /// Current orchestration pattern
    private var currentPattern: (any OrchestrationPattern)?
    
    /// Initialize the orchestrator
    /// - Parameter registry: The agent registry to use
    public init(registry: AgentRegistry = .shared) {
        self.registry = registry
    }
    
    /// Set the orchestration pattern to use
    /// - Parameter pattern: The orchestration pattern
    public func setPattern(_ pattern: any OrchestrationPattern) {
        self.currentPattern = pattern
    }
    
    /// Execute a task using the current orchestration pattern
    /// - Parameters:
    ///   - task: The task to execute
    ///   - context: Shared context
    ///   - agentIds: Optional specific agent IDs to use (if nil, selects automatically)
    ///   - progressTracker: Optional progress tracker for visualization
    /// - Returns: Result of execution
    public func execute(
        task: AgentTask,
        context: AgentContext,
        agentIds: [UUID]? = nil,
        progressTracker: OrchestrationProgressTracker? = nil
    ) async throws -> AgentResult {
        // Get agents to use
        let agents: [any Agent]
        
        if let ids = agentIds {
            // Use specified agents
            agents = try await getAgents(byIds: ids)
        } else {
            // Select agents based on task requirements
            agents = try await selectAgents(for: task)
        }
        
        guard !agents.isEmpty else {
            throw AgentOrchestratorError.noAgentsAvailable
        }
        
        // Get or create pattern
        let pattern = currentPattern ?? createDefaultPattern(agents: agents)
        
        // Execute using pattern - all patterns now support optional progress tracker
        return try await pattern.execute(
            task: task,
            agents: agents,
            context: context,
            progressTracker: progressTracker
        )
    }
    
    /// Select appropriate agents for a task
    /// - Parameter task: The task
    /// - Returns: Array of agents
    private func selectAgents(for task: AgentTask) async throws -> [any Agent] {
        if task.requiredCapabilities.isEmpty {
            // No specific requirements, get all agents
            return await registry.listAll()
        }
        
        // Get agents with required capabilities
        return await registry.getAgents(withAllCapabilities: task.requiredCapabilities)
    }
    
    /// Get agents by IDs
    /// - Parameter ids: Agent IDs
    /// - Returns: Array of agents
    private func getAgents(byIds ids: [UUID]) async throws -> [any Agent] {
        var agents: [any Agent] = []
        
        for id in ids {
            if let agent = await registry.getAgent(byId: id) {
                agents.append(agent)
            }
        }
        
        return agents
    }
    
    /// Create a default orchestration pattern
    /// - Parameter agents: Available agents
    /// - Returns: Default pattern
    private func createDefaultPattern(agents: [any Agent]) -> any OrchestrationPattern {
        // Find a coordinator agent (one with generalReasoning capability)
        if let coordinator = agents.first(where: { $0.capabilities.contains(.generalReasoning) }) {
            return OrchestratorPattern(coordinator: coordinator)
        }
        
        // Fallback: use first agent as coordinator
        if let firstAgent = agents.first {
            return OrchestratorPattern(coordinator: firstAgent)
        }
        
        // Last resort: create a simple coordinator
        let coordinator = BaseAgent(
            name: "Default Coordinator",
            description: "Default coordinator agent",
            capabilities: [.generalReasoning]
        )
        
        return OrchestratorPattern(coordinator: coordinator)
    }
}

/// Errors that can occur in the orchestrator
@available(macOS 26.0, iOS 26.0, *)
public enum AgentOrchestratorError: Error, Sendable {
    case noAgentsAvailable
    case agentNotFound(UUID)
    case patternNotSet
    case executionFailed(String)
}





