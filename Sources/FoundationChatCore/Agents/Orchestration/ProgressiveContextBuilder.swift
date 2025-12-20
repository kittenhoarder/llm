//
//  ProgressiveContextBuilder.swift
//  FoundationChatCore
//
//  Builds context iteratively rather than passing everything at once (RCR-Router pattern)
//

import Foundation

/// Builds minimal, focused context for agents
@available(macOS 26.0, iOS 26.0, *)
public actor ProgressiveContextBuilder {
    private let summarizer: ContextSummarizer
    private let tokenCounter: TokenCounter
    private let budgetGuard: TokenBudgetGuard
    
    public init(
        summarizer: ContextSummarizer = ContextSummarizer(),
        tokenCounter: TokenCounter = TokenCounter(),
        budgetGuard: TokenBudgetGuard = TokenBudgetGuard()
    ) {
        self.summarizer = summarizer
        self.tokenCounter = tokenCounter
        self.budgetGuard = budgetGuard
    }
    
    /// Build context for a subtask with minimal, focused information
    /// - Parameters:
    ///   - subtask: The subtask to build context for
    ///   - baseContext: Original full context
    ///   - previousResults: Results from previous agents in the chain
    ///   - tokenBudget: Maximum tokens for context
    /// - Returns: Isolated context for the subtask
    public func buildContext(
        for subtask: DecomposedSubtask,
        baseContext: AgentContext,
        previousResults: [AgentResult],
        tokenBudget: Int
    ) async throws -> AgentContext {
        print("🔧 ProgressiveContextBuilder: Building context for subtask '\(subtask.description.prefix(50))...'")
        
        var isolatedContext = AgentContext()
        
        // 1. Light conversation summary (1-2 sentences)
        if !baseContext.conversationHistory.isEmpty {
            let summary = try await summarizer.summarize(baseContext.conversationHistory, level: .light)
            isolatedContext.conversationHistory = [
                Message(role: .system, content: "Context summary: \(summary)")
            ]
        }
        
        // 2. Relevant file references only (filter based on subtask description)
        isolatedContext.fileReferences = filterRelevantFiles(
            baseContext.fileReferences,
            for: subtask.description
        )
        
        // 3. Summarized previous results (not raw results)
        if !previousResults.isEmpty {
            let resultSummarizer = ResultSummarizer(summarizer: summarizer)
            let summarizedResults = try await resultSummarizer.summarizeResults(previousResults, level: .light)
            isolatedContext.conversationHistory.append(
                Message(role: .assistant, content: "Previous agent results: \(summarizedResults)")
            )
            
            // Store full results in toolResults for reference
            for (index, result) in previousResults.enumerated() {
                isolatedContext.toolResults["agent_result_\(index)"] = result.content
            }
        }
        
        // 4. Tool results directly relevant to this subtask
        isolatedContext.toolResults = filterRelevantToolResults(
            baseContext.toolResults,
            for: subtask.description
        )
        
        // 5. Copy user preferences
        isolatedContext.userPreferences = baseContext.userPreferences
        
        // 6. Enforce token budget
        let enforcedContext = try await budgetGuard.enforceBudget(
            context: isolatedContext,
            budget: tokenBudget,
            summarizer: summarizer
        )
        
        let finalTokens = await estimateContextTokens(enforcedContext)
        print("✅ ProgressiveContextBuilder: Built context with ~\(finalTokens) tokens (budget: \(tokenBudget))")
        
        return enforcedContext
    }
    
    /// Filter file references based on relevance to subtask
    private func filterRelevantFiles(_ files: [String], for subtaskDescription: String) -> [String] {
        let lowercased = subtaskDescription.lowercased()
        
        // If subtask mentions specific files, try to match
        return files.filter { file in
            let fileName = (file as NSString).lastPathComponent.lowercased()
            
            // Check if file name appears in subtask description
            if lowercased.contains(fileName) {
                return true
            }
            
            // Check file extension relevance
            let ext = (file as NSString).pathExtension.lowercased()
            if !ext.isEmpty {
                if lowercased.contains(ext) || lowercased.contains("\(ext) file") {
                    return true
                }
            }
            
            // If no specific files mentioned, include all (or limit to first few)
            return true
        }
    }
    
    /// Filter tool results based on relevance to subtask
    private func filterRelevantToolResults(_ toolResults: [String: String], for subtaskDescription: String) -> [String: String] {
        let lowercased = subtaskDescription.lowercased()
        
        // Filter results that seem relevant to the subtask
        return toolResults.filter { key, value in
            // Include if key or value mentions relevant terms
            let keyLower = key.lowercased()
            let valueLower = value.lowercased()
            
            // Simple keyword matching
            let keywords = lowercased.components(separatedBy: .whitespaces)
                .filter { $0.count > 3 } // Only meaningful words
            
            for keyword in keywords {
                if keyLower.contains(keyword) || valueLower.contains(keyword) {
                    return true
                }
            }
            
            // Always include recent results (they might be needed)
            return key.contains("agent_result") || key.contains("recent")
        }
    }
    
    /// Estimate token count for context
    private func estimateContextTokens(_ context: AgentContext) async -> Int {
        let conversationTokens = await tokenCounter.countTokens(context.conversationHistory)
        let fileRefTokens = context.fileReferences.joined(separator: ", ").count / 4
        let toolResultsTokens = await tokenCounter.countTokens(context.toolResults.values.joined(separator: " "))
        
        return conversationTokens + fileRefTokens + toolResultsTokens
    }
}

