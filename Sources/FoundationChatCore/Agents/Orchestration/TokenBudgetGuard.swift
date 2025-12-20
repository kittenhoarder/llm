//
//  TokenBudgetGuard.swift
//  FoundationChatCore
//
//  Monitors and enforces token budgets per agent and per task
//

import Foundation

/// Guard for monitoring and enforcing token budgets
@available(macOS 26.0, iOS 26.0, *)
public actor TokenBudgetGuard {
    private let tokenCounter: TokenCounter
    private let summarizer: ContextSummarizer
    
    /// Cumulative token usage across all agents
    private var cumulativeUsage: Int = 0
    
    public init(tokenCounter: TokenCounter = TokenCounter(), summarizer: ContextSummarizer = ContextSummarizer()) {
        self.tokenCounter = tokenCounter
        self.summarizer = summarizer
    }
    
    /// Check if estimated tokens fit within budget
    /// - Parameters:
    ///   - estimatedTokens: Estimated token count
    ///   - budget: Token budget
    /// - Returns: True if within budget
    public func checkBudget(estimatedTokens: Int, budget: Int) -> Bool {
        return estimatedTokens <= budget
    }
    
    /// Enforce token budget on context by truncating/summarizing if needed
    /// - Parameters:
    ///   - context: The context to enforce budget on
    ///   - budget: Token budget
    ///   - summarizer: Context summarizer for reducing context size
    /// - Returns: Context that fits within budget
    public func enforceBudget(context: AgentContext, budget: Int, summarizer: ContextSummarizer) async throws -> AgentContext {
        // Estimate current context size
        let conversationTokens = await tokenCounter.countTokens(context.conversationHistory)
        let fileRefTokens = context.fileReferences.joined(separator: ", ").count / 4 // Rough estimate
        let toolResultsTokens = await tokenCounter.countTokens(context.toolResults.values.joined(separator: " "))
        
        let totalTokens = conversationTokens + fileRefTokens + toolResultsTokens
        
        guard totalTokens > budget else {
            return context // Already within budget
        }
        
        print("⚠️ TokenBudgetGuard: Context exceeds budget (\(totalTokens) > \(budget)), enforcing...")
        
        var enforcedContext = context
        
        // Summarize conversation history if too large
        if conversationTokens > budget / 2 {
            let summary = try await summarizer.summarize(context.conversationHistory, level: .light)
            enforcedContext.conversationHistory = [
                Message(role: .system, content: summary)
            ]
        } else if conversationTokens > budget {
            // Truncate to most recent messages
            let targetTokens = budget / 2
            var accumulatedTokens = 0
            var keptMessages: [Message] = []
            
            for message in context.conversationHistory.reversed() {
                let messageTokens = await tokenCounter.countTokens(message)
                if accumulatedTokens + messageTokens <= targetTokens {
                    keptMessages.insert(message, at: 0)
                    accumulatedTokens += messageTokens
                } else {
                    break
                }
            }
            
            enforcedContext.conversationHistory = keptMessages
        }
        
        // Truncate file references if needed
        let enforcedConversationTokens = await tokenCounter.countTokens(enforcedContext.conversationHistory)
        let remainingBudget = budget - enforcedConversationTokens
        if fileRefTokens > remainingBudget / 2 {
            // Keep only first few file references
            let maxFiles = max(1, remainingBudget / 50) // Rough estimate: 50 tokens per file ref
            enforcedContext.fileReferences = Array(context.fileReferences.prefix(maxFiles))
        }
        
        // Truncate tool results if needed
        let _ = await tokenCounter.countTokens(enforcedContext.conversationHistory)
        let fileRefTokensFinal = enforcedContext.fileReferences.joined(separator: ", ").count / 4
        let finalRemainingBudget = remainingBudget - fileRefTokensFinal
        if toolResultsTokens > finalRemainingBudget {
            // Keep only most recent tool results
            let maxResults = max(1, finalRemainingBudget / 100) // Rough estimate
            let sortedResults = context.toolResults.sorted { $0.key < $1.key }
            let prefixResults = Array(sortedResults.prefix(maxResults))
            enforcedContext.toolResults = Dictionary(uniqueKeysWithValues: prefixResults)
        }
        
        return enforcedContext
    }
    
    /// Track cumulative token usage
    /// - Parameter tokens: Number of tokens to add
    public func trackUsage(_ tokens: Int) {
        cumulativeUsage += tokens
    }
    
    /// Get cumulative usage
    /// - Returns: Total tokens used so far
    public func getCumulativeUsage() -> Int {
        return cumulativeUsage
    }
    
    /// Reset cumulative usage
    public func reset() {
        cumulativeUsage = 0
    }
    
    /// Check if approaching budget limit
    /// - Parameters:
    ///   - budget: Token budget
    ///   - warningThreshold: Percentage threshold for warning (default 0.8 = 80%)
    /// - Returns: True if approaching limit
    public func isApproachingLimit(budget: Int, warningThreshold: Double = 0.8) -> Bool {
        return Double(cumulativeUsage) >= Double(budget) * warningThreshold
    }
}

