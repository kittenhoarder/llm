//
//  AgentRegistry.swift
//  FoundationChatCore
//
//  Central registry for managing available agents
//

import Foundation

/// Registry for managing all available agents
@available(macOS 26.0, iOS 26.0, *)
public actor AgentRegistry {
    /// Shared singleton instance
    public static let shared = AgentRegistry()
    
    /// Registered agents by ID
    private var agents: [UUID: any Agent] = [:]
    
    /// Agents by capability
    private var agentsByCapability: [AgentCapability: Set<UUID>] = [:]
    
    private init() {}
    
    /// Register an agent
    /// - Parameter agent: The agent to register
    /// - Note: If an agent with the same name already exists, registration is skipped to prevent duplicates
    public func register(_ agent: any Agent) {
        // Check if an agent with this name already exists
        if hasAgent(named: agent.name) {
            Log.warn("⚠️ Agent '\(agent.name)' already registered, skipping duplicate registration")
            return
        }
        
        agents[agent.id] = agent
        
        // Index by capability
        for capability in agent.capabilities {
            agentsByCapability[capability, default: []].insert(agent.id)
        }
    }
    
    /// Get an agent by ID
    /// - Parameter id: The agent ID
    /// - Returns: The agent if found
    public func getAgent(byId id: UUID) -> (any Agent)? {
        return agents[id]
    }
    
    /// Check if an agent with the given name already exists
    /// - Parameter name: The agent name to check
    /// - Returns: True if an agent with this name exists
    public func hasAgent(named name: String) -> Bool {
        return agents.values.contains { $0.name == name }
    }
    
    /// Get an agent by name
    /// - Parameter name: The agent name
    /// - Returns: The agent if found
    public func getAgent(byName name: String) -> (any Agent)? {
        return agents.values.first { $0.name == name }
    }
    
    /// Get all agents with a specific capability
    /// - Parameter capability: The capability to search for
    /// - Returns: Array of agents with that capability
    public func getAgents(byCapability capability: AgentCapability) -> [any Agent] {
        guard let agentIds = agentsByCapability[capability] else {
            return []
        }
        
        return agentIds.compactMap { agents[$0] }
    }
    
    /// Get agents that have all of the specified capabilities
    /// - Parameter capabilities: Set of required capabilities
    /// - Returns: Array of agents that have all capabilities
    public func getAgents(withAllCapabilities capabilities: Set<AgentCapability>) -> [any Agent] {
        guard !capabilities.isEmpty else {
            return listAll()
        }
        
        var candidateIds: Set<UUID>?
        
        for capability in capabilities {
            guard let agentIds = agentsByCapability[capability] else {
                return [] // No agents have this capability
            }
            
            if let existing = candidateIds {
                candidateIds = existing.intersection(agentIds)
            } else {
                candidateIds = agentIds
            }
        }
        
        guard let ids = candidateIds else {
            return []
        }
        
        return ids.compactMap { agents[$0] }
    }
    
    /// List all registered agents
    /// - Returns: Array of all agents
    public func listAll() -> [any Agent] {
        return Array(agents.values)
    }
    
    /// Unregister an agent
    /// - Parameter id: The agent ID to unregister
    public func unregister(agentId id: UUID) {
        guard let agent = agents[id] else {
            return
        }
        
        agents.removeValue(forKey: id)
        
        // Remove from capability index
        for capability in agent.capabilities {
            agentsByCapability[capability]?.remove(id)
        }
    }
    
    /// Clear all registered agents
    public func clear() {
        agents.removeAll()
        agentsByCapability.removeAll()
    }
    
    /// Get count of registered agents
    /// - Returns: Number of registered agents
    public func count() -> Int {
        return agents.count
    }
}





