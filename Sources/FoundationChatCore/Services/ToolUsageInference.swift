//
//  ToolUsageInference.swift
//  FoundationChatCore
//
//  Fallback mechanism to infer tool usage from response content
//

import Foundation

/// Infers tool usage from response content when direct tracking fails
@available(macOS 26.0, iOS 26.0, *)
public struct ToolUsageInference {
    /// Infer which tools were used based on response content
    /// - Parameters:
    ///   - content: The model's response content
    ///   - availableTools: List of available tool names
    /// - Returns: Array of tool names that were likely used
    public static func inferToolUsage(from content: String, availableTools: [String]) -> [String] {
        var inferredTools: [String] = []
        let contentLower = content.lowercased()
        
        // Check for DuckDuckGo usage
        if availableTools.contains("duckduckgo_search") {
            let duckduckgoIndicators = [
                "duckduckgo",
                "duckduckgo instant answers",
                "duckduckgo api",
                "couldn't find any information",
                "couldn't find any current information",
                "couldn't find any online information",
                "does not have an instant answer",
                "doesn't have an instant answer",
                "instant answers api"
            ]
            
            for indicator in duckduckgoIndicators {
                if contentLower.contains(indicator) {
                    inferredTools.append("duckduckgo_search")
                    break
                }
            }
        }
        
        // Add more tool inference logic here as needed
        
        return inferredTools
    }
}







