//
//  AgentConfiguration.swift
//  FoundationChatCore
//
//  Configuration for agent-based conversations
//

import Foundation

/// Configuration for agent-based conversations
@available(macOS 26.0, iOS 26.0, *)
public struct AgentConfiguration: Codable, Sendable {
    /// Selected agent IDs
    public var selectedAgents: [UUID]
    
    /// Orchestration pattern type
    public var orchestrationPattern: OrchestrationPatternType
    
    /// Settings per agent
    public var agentSettings: [UUID: AgentSettings]
    
    public init(
        selectedAgents: [UUID] = [],
        orchestrationPattern: OrchestrationPatternType = .orchestrator,
        agentSettings: [UUID: AgentSettings] = [:]
    ) {
        self.selectedAgents = selectedAgents
        self.orchestrationPattern = orchestrationPattern
        self.agentSettings = agentSettings
    }
}

/// Settings for a specific agent
@available(macOS 26.0, iOS 26.0, *)
public struct AgentSettings: Codable, Sendable {
    /// Custom instructions for this agent
    public var instructions: String?
    
    /// Whether this agent is enabled
    public var enabled: Bool
    
    /// Additional parameters
    public var parameters: [String: String]
    
    public init(
        instructions: String? = nil,
        enabled: Bool = true,
        parameters: [String: String] = [:]
    ) {
        self.instructions = instructions
        self.enabled = enabled
        self.parameters = parameters
    }
}

/// Type of conversation
@available(macOS 26.0, iOS 26.0, *)
public enum ConversationType: String, Codable, Sendable {
    /// Regular chat conversation (deprecated - all conversations are now agent-based)
    case chat
    
    /// Single agent conversation (default)
    case singleAgent
}





