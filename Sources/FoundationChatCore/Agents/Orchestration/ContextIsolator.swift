//
//  ContextIsolator.swift
//  FoundationChatCore
//
//  Wrapper around ProgressiveContextBuilder for backward compatibility
//

import Foundation

/// Helper for isolating context for agents (wrapper around ProgressiveContextBuilder)
@available(macOS 26.0, iOS 26.0, *)
public actor ContextIsolator {
    private let contextBuilder: ProgressiveContextBuilder
    private let defaultTokenBudget: Int
    
    public init(
        contextBuilder: ProgressiveContextBuilder = ProgressiveContextBuilder(),
        defaultTokenBudget: Int = 2000
    ) {
        self.contextBuilder = contextBuilder
        self.defaultTokenBudget = defaultTokenBudget
    }
    
    /// Isolate context for a subtask
    /// - Parameters:
    ///   - subtask: The subtask
    ///   - originalContext: Original full context
    ///   - previousResults: Results from previous agents
    ///   - summarizer: Context summarizer
    /// - Returns: Isolated context
    public func isolateContext(
        for subtask: DecomposedSubtask,
        originalContext: AgentContext,
        previousResults: [AgentResult],
        summarizer: ContextSummarizer
    ) async throws -> AgentContext {
        return try await contextBuilder.buildContext(
            for: subtask,
            baseContext: originalContext,
            previousResults: previousResults,
            tokenBudget: defaultTokenBudget
        )
    }
}

