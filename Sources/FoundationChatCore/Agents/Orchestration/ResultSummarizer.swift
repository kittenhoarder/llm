//
//  ResultSummarizer.swift
//  FoundationChatCore
//
//  Summarizes agent results before passing to next agent or coordinator
//

import Foundation

/// Summarizes agent results to save tokens
@available(macOS 26.0, iOS 26.0, *)
public actor ResultSummarizer {
    private let summarizer: ContextSummarizer
    
    public init(summarizer: ContextSummarizer = ContextSummarizer()) {
        self.summarizer = summarizer
    }
    
    /// Summarize an agent result
    /// - Parameters:
    ///   - result: The agent result to summarize
    ///   - level: Summarization level
    /// - Returns: Summarized result string
    public func summarizeResult(_ result: AgentResult, level: SummarizationLevel) async throws -> String {
        var summaryParts: [String] = []
        
        // Summarize main content
        if !result.content.isEmpty {
            let contentSummary = try await summarizer.summarize(result.content)
            summaryParts.append(contentSummary)
        }
        
        // Include key tool call results
        if !result.toolCalls.isEmpty {
            let toolResults = result.toolCalls.compactMap { toolCall -> String? in
                guard let result = toolCall.result else { return nil }
                // Truncate very long tool results
                if result.count > AppConstants.toolResultTruncationLength {
                    return "\(toolCall.toolName): \(result.prefix(AppConstants.toolResultTruncationLength))..."
                }
                return "\(toolCall.toolName): \(result)"
            }
            
            if !toolResults.isEmpty {
                summaryParts.append("Tool results: \(toolResults.joined(separator: "; "))")
            }
        }
        
        // Include error if present
        if let error = result.error {
            summaryParts.append("Error: \(error)")
        }
        
        return summaryParts.isEmpty ? "No results" : summaryParts.joined(separator: ". ")
    }
    
    /// Summarize multiple results
    /// - Parameters:
    ///   - results: Array of agent results
    ///   - level: Summarization level
    /// - Returns: Combined summary string
    public func summarizeResults(_ results: [AgentResult], level: SummarizationLevel) async throws -> String {
        guard !results.isEmpty else {
            return "No results from agents."
        }
        
        if results.count == 1 {
            return try await summarizeResult(results[0], level: level)
        }
        
        var summaries: [String] = []
        for (index, result) in results.enumerated() {
            let summary = try await summarizeResult(result, level: level)
            summaries.append("Result \(index + 1): \(summary)")
        }
        
        return summaries.joined(separator: "\n\n")
    }
}

