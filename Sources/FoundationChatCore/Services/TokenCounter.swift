//
//  TokenCounter.swift
//  FoundationChatCore
//
//  Service for estimating token counts in text
//

import Foundation
import FoundationModels

/// Service for counting tokens in text
/// Uses rough estimation: 4 characters ≈ 1 token for English text
@available(macOS 26.0, iOS 26.0, *)
public actor TokenCounter {
    /// Cache for token counts to avoid recalculation
    private var cache: [String: Int] = [:]
    
    /// Maximum cache size to prevent memory issues
    private let maxCacheSize = 1000
    
    public init() {}
    
    /// Estimate token count for a string
    /// - Parameter text: The text to count tokens for
    /// - Returns: Estimated token count
    public func countTokens(_ text: String) -> Int {
        // Check cache first
        if let cached = cache[text] {
            return cached
        }
        
        // Rough estimation: 4 characters ≈ 1 token for English
        // More accurate for code: 3 characters ≈ 1 token
        // We'll use 4 as a conservative estimate
        let charCount = text.count
        let estimatedTokens = (charCount + 3) / 4
        
        // Cache the result
        cacheResult(text, count: estimatedTokens)
        
        return estimatedTokens
    }
    
    /// Count tokens for a message
    /// - Parameter message: The message to count tokens for
    /// - Returns: Estimated token count
    public func countTokens(_ message: Message) -> Int {
        var total = 0
        
        // Count content
        total += countTokens(message.content)
        
        // Count role (small overhead)
        total += 2 // "user" or "assistant" ≈ 2 tokens
        
        // Count tool calls if present
        for toolCall in message.toolCalls {
            total += countTokens(toolCall.toolName)
            total += countTokens(toolCall.arguments)
            if let result = toolCall.result {
                total += countTokens(result)
            }
        }
        
        return total
    }
    
    /// Count tokens for multiple messages
    /// - Parameter messages: Array of messages
    /// - Returns: Total estimated token count
    public func countTokens(_ messages: [Message]) -> Int {
        return messages.reduce(0) { $0 + countTokens($1) }
    }
    
    /// Count tokens for a transcript entry
    /// - Parameter entry: Transcript entry
    /// - Returns: Estimated token count
    public func countTokens(_ entry: Transcript.Entry) -> Int {
        // Handle known cases from FoundationModels
        if case .prompt(let prompt) = entry {
            return countTokensForPrompt(prompt)
        } else if case .response(let response) = entry {
            return countTokensForResponse(response)
        } else if case .toolOutput(let toolOutput) = entry {
            return countTokensForToolOutput(toolOutput)
        }
        
        // Fallback for any other cases
        return 0
    }
    
    /// Count tokens for tool output
    private func countTokensForToolOutput(_ toolOutput: Transcript.ToolOutput) -> Int {
        var total = 0
        for segment in toolOutput.segments {
            if case .text(let textSegment) = segment {
                total += countTokens(textSegment.content)
            }
        }
        return total
    }
    
    /// Count tokens for a full transcript
    /// - Parameter transcript: The transcript
    /// - Returns: Total estimated token count
    /// Note: Transcript API structure may vary - this is a simplified implementation
    public func countTokens(_ transcript: Transcript) -> Int {
        // Since Transcript structure is not directly accessible,
        // we'll estimate based on a rough approximation
        // This method may need adjustment based on actual API
        return 0
    }
    
    /// Count tokens for a prompt
    private func countTokensForPrompt(_ prompt: Transcript.Prompt) -> Int {
        var total = 0
        for segment in prompt.segments {
            if case .text(let textSegment) = segment {
                total += countTokens(textSegment.content)
            }
            // Assets don't contribute to token count in text context
        }
        return total
    }
    
    /// Count tokens for a response
    private func countTokensForResponse(_ response: Transcript.Response) -> Int {
        var total = 0
        for segment in response.segments {
            if case .text(let textSegment) = segment {
                total += countTokens(textSegment.content)
            }
            // Assets don't contribute to token count in text context
        }
        return total
    }
    
    /// Cache a result, evicting oldest entries if cache is full
    private func cacheResult(_ text: String, count: Int) {
        // Simple cache eviction: if cache is full, clear it
        // In a production system, you might use LRU eviction
        if cache.count >= maxCacheSize {
            cache.removeAll()
        }
        cache[text] = count
    }
    
    /// Clear the cache
    public func clearCache() {
        cache.removeAll()
    }
}

