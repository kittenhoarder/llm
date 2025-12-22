//
//  AgentTokenTracker.swift
//  FoundationChatCore
//
//  Tracks token usage per agent per task with granularity
//

import Foundation

/// Tracks token usage for agents
@available(macOS 26.0, iOS 26.0, *)
public actor AgentTokenTracker {
    private let tokenCounter: TokenCounter
    
    /// Token usage per agent ID
    private var agentTokenUsage: [UUID: AgentTokenUsage] = [:]
    
    /// SVDB savings per agent ID (tokens saved through SVDB optimization)
    private var agentSVDBSavings: [UUID: Int] = [:]
    
    public init(tokenCounter: TokenCounter = TokenCounter()) {
        self.tokenCounter = tokenCounter
    }
    
    /// Track input prompt tokens for an agent
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - tokens: Number of input tokens
    public func trackInputTokens(agentId: UUID, tokens: Int) {
        var usage = agentTokenUsage[agentId] ?? AgentTokenUsage()
        usage = AgentTokenUsage(
            inputTokens: usage.inputTokens + tokens,
            outputTokens: usage.outputTokens,
            toolCallTokens: usage.toolCallTokens,
            contextTokens: usage.contextTokens
        )
        agentTokenUsage[agentId] = usage
    }
    
    /// Track output tokens for an agent
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - tokens: Number of output tokens
    public func trackOutputTokens(agentId: UUID, tokens: Int) {
        var usage = agentTokenUsage[agentId] ?? AgentTokenUsage()
        usage = AgentTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens + tokens,
            toolCallTokens: usage.toolCallTokens,
            contextTokens: usage.contextTokens
        )
        agentTokenUsage[agentId] = usage
    }
    
    /// Track tool call tokens for an agent
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - tokens: Number of tool call tokens
    public func trackToolCallTokens(agentId: UUID, tokens: Int) {
        var usage = agentTokenUsage[agentId] ?? AgentTokenUsage()
        usage = AgentTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            toolCallTokens: usage.toolCallTokens + tokens,
            contextTokens: usage.contextTokens
        )
        agentTokenUsage[agentId] = usage
    }
    
    /// Track context tokens for an agent
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - tokens: Number of context tokens
    public func trackContextTokens(agentId: UUID, tokens: Int) {
        var usage = agentTokenUsage[agentId] ?? AgentTokenUsage()
        usage = AgentTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            toolCallTokens: usage.toolCallTokens,
            contextTokens: usage.contextTokens + tokens
        )
        agentTokenUsage[agentId] = usage
    }
    
    /// Track tokens from a prompt string
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - prompt: The prompt string
    public func trackPrompt(agentId: UUID, prompt: String) async {
        let tokens = await tokenCounter.countTokens(prompt)
        trackInputTokens(agentId: agentId, tokens: tokens)
    }
    
    /// Track tokens from a response string
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - response: The response string
    public func trackResponse(agentId: UUID, response: String) async {
        let tokens = await tokenCounter.countTokens(response)
        trackOutputTokens(agentId: agentId, tokens: tokens)
    }
    
    /// Track tokens from tool calls
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - toolCalls: Array of tool calls
    public func trackToolCalls(agentId: UUID, toolCalls: [ToolCall]) async {
        var totalTokens = 0
        for toolCall in toolCalls {
            totalTokens += await tokenCounter.countTokens(toolCall.toolName)
            totalTokens += await tokenCounter.countTokens(toolCall.arguments)
            if let result = toolCall.result {
                totalTokens += await tokenCounter.countTokens(result)
            }
        }
        trackToolCallTokens(agentId: agentId, tokens: totalTokens)
    }
    
    /// Track tokens from context
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - context: The agent context
    public func trackContext(agentId: UUID, context: AgentContext) async {
        let conversationTokens = await tokenCounter.countTokens(context.conversationHistory)
        let fileRefTokens = context.fileReferences.joined(separator: ", ").count / 4
        let toolResultsTokens = await tokenCounter.countTokens(context.toolResults.values.joined(separator: " "))
        let totalContextTokens = conversationTokens + fileRefTokens + toolResultsTokens
        
        trackContextTokens(agentId: agentId, tokens: totalContextTokens)
    }
    
    /// Get token usage for an agent
    /// - Parameter agentId: Agent ID
    /// - Returns: Token usage breakdown
    public func getTokenUsage(for agentId: UUID) -> AgentTokenUsage {
        return agentTokenUsage[agentId] ?? AgentTokenUsage()
    }
    
    /// Get total token usage across all agents
    /// - Returns: Total token usage
    public func getTotalTokenUsage() -> Int {
        return agentTokenUsage.values.reduce(0) { $0 + $1.totalTokens }
    }
    
    /// Track SVDB-based token savings for an agent
    /// - Parameters:
    ///   - agentId: Agent ID
    ///   - originalTokens: Original token count before SVDB optimization
    ///   - optimizedTokens: Token count after SVDB optimization
    public func trackSVDBSavings(agentId: UUID, originalTokens: Int, optimizedTokens: Int) {
        let savings = max(0, originalTokens - optimizedTokens)
        agentSVDBSavings[agentId] = (agentSVDBSavings[agentId] ?? 0) + savings
    }
    
    /// Get SVDB savings for an agent
    /// - Parameter agentId: Agent ID
    /// - Returns: Total SVDB savings in tokens
    public func getSVDBSavings(for agentId: UUID) -> Int {
        return agentSVDBSavings[agentId] ?? 0
    }
    
    /// Get total SVDB savings across all agents
    /// - Returns: Total SVDB savings in tokens
    public func getTotalSVDBSavings() -> Int {
        return agentSVDBSavings.values.reduce(0, +)
    }
    
    /// Store token usage in context metadata
    /// - Parameter context: The context to update
    /// - Returns: Updated context with token usage metadata
    public func storeInContext(_ context: AgentContext) -> AgentContext {
        var updatedContext = context
        
        // Store per-agent token usage
        for (agentId, usage) in agentTokenUsage {
            let keyPrefix = "tokens_\(agentId.uuidString.prefix(8))"
            updatedContext.metadata["\(keyPrefix)_input"] = String(usage.inputTokens)
            updatedContext.metadata["\(keyPrefix)_output"] = String(usage.outputTokens)
            updatedContext.metadata["\(keyPrefix)_tools"] = String(usage.toolCallTokens)
            updatedContext.metadata["\(keyPrefix)_context"] = String(usage.contextTokens)
            updatedContext.metadata["\(keyPrefix)_total"] = String(usage.totalTokens)
            
            // Store SVDB savings if available
            if let svdbSavings = agentSVDBSavings[agentId], svdbSavings > 0 {
                updatedContext.metadata["\(keyPrefix)_svdb_saved"] = String(svdbSavings)
            }
        }
        
        // Store total
        let total = getTotalTokenUsage()
        updatedContext.metadata["tokens_total_task"] = String(total)
        
        // Store total SVDB savings
        let totalSVDBSavings = getTotalSVDBSavings()
        if totalSVDBSavings > 0 {
            updatedContext.metadata["tokens_svdb_saved_total"] = String(totalSVDBSavings)
        }
        
        return updatedContext
    }
    
    /// Calculate token savings vs single-agent approach
    /// - Parameter singleAgentEstimate: Estimated tokens for single-agent approach
    /// - Returns: Savings percentage
    /// Note: SVDB savings are already reflected in the total token usage (fewer context tokens),
    /// so we calculate savings as (estimate - actual) / estimate * 100
    public func calculateSavings(singleAgentEstimate: Int) -> Double {
        let total = getTotalTokenUsage()
        guard singleAgentEstimate > 0 else { return 0.0 }
        
        // Calculate savings: (estimate - actual) / estimate * 100
        // The actual total already includes the benefit of SVDB optimization (fewer context tokens)
        let savings = Double(singleAgentEstimate - total) / Double(singleAgentEstimate) * 100.0
        return max(0.0, savings)
    }
    
    /// Reset all tracking
    public func reset() {
        agentTokenUsage.removeAll()
        agentSVDBSavings.removeAll()
    }
}

