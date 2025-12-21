//
//  MessageCompactor.swift
//  FoundationChatCore
//
//  Service for compacting message history to fit within token limits
//

import Foundation

/// Service for compacting message history
@available(macOS 26.0, iOS 26.0, *)
public actor MessageCompactor {
    /// Token counter
    private let tokenCounter = TokenCounter()
    
    /// Context summarizer
    private let summarizer = ContextSummarizer()
    
    /// Number of recent messages to keep full (default: 5)
    public var recentMessagesCount: Int = 5
    
    public init(recentMessagesCount: Int = 5) {
        self.recentMessagesCount = recentMessagesCount
    }
    
    /// Compact messages to fit within token budget
    /// - Parameters:
    ///   - messages: Messages to compact
    ///   - maxTokens: Maximum token budget
    /// - Returns: Compacted messages (recent messages + summary of older ones)
    public func compact(messages: [Message], maxTokens: Int) async throws -> [Message] {
        guard !messages.isEmpty else {
            return []
        }
        
        // If messages fit within budget, return as-is
        let totalTokens = await tokenCounter.countTokens(messages)
        if totalTokens <= maxTokens {
            return messages
        }
        
        // Split messages into recent and old
        let recentMessages = Array(messages.suffix(recentMessagesCount))
        let oldMessages = Array(messages.dropLast(recentMessagesCount))
        
        guard !oldMessages.isEmpty else {
            // All messages are recent, but still over budget
            // Truncate oldest recent messages
            return try await truncateMessages(messages, maxTokens: maxTokens)
        }
        
        // Count tokens for recent messages
        let recentTokens = await tokenCounter.countTokens(recentMessages)
        
        // Calculate available tokens for summary
        let availableForSummary = maxTokens - recentTokens - AppConstants.tokenReserveOverhead
        
        guard availableForSummary > AppConstants.minimumTokensForSummary else {
            // Not enough space for summary, just keep recent messages
            return recentMessages
        }
        
        // Summarize old messages
        let summary = try await summarizer.summarize(oldMessages, level: .heavy)
        
        // Create summary message
        let summaryMessage = Message(
            role: .system,
            content: "Previous conversation summary: \(summary)"
        )
        
        // Combine summary + recent messages
        return [summaryMessage] + recentMessages
    }
    
    /// Compact messages using sliding window strategy
    /// - Parameters:
    ///   - messages: Messages to compact
    ///   - maxTokens: Maximum token budget
    /// - Returns: Compacted messages
    public func compactSlidingWindow(messages: [Message], maxTokens: Int) async throws -> [Message] {
        guard !messages.isEmpty else {
            return []
        }
        
        // Start from most recent and work backwards
        var result: [Message] = []
        var currentTokens = 0
        
        // Reserve tokens for potential summary
        let availableTokens = maxTokens - 100
        
        for message in messages.reversed() {
            let messageTokens = await tokenCounter.countTokens(message)
            
            if currentTokens + messageTokens <= availableTokens {
                result.insert(message, at: 0)
                currentTokens += messageTokens
            } else {
                // Remaining messages need to be summarized
                let remainingMessages = Array(messages.prefix(messages.count - result.count))
                if !remainingMessages.isEmpty {
                    let summary = try await summarizer.summarize(remainingMessages, level: .heavy)
                    let summaryMessage = Message(
                        role: .system,
                        content: "Previous conversation summary: \(summary)"
                    )
                    result.insert(summaryMessage, at: 0)
                }
                break
            }
        }
        
        return result
    }
    
    /// Compact messages with selective summarization
    /// - Parameters:
    ///   - messages: Messages to compact
    ///   - maxTokens: Maximum token budget
    ///   - recentCount: Number of recent messages to keep full
    /// - Returns: Compacted messages
    public func compactSelective(
        messages: [Message],
        maxTokens: Int,
        recentCount: Int = 5
    ) async throws -> [Message] {
        guard !messages.isEmpty else {
            return []
        }
        
        // Keep recent messages full
        let recentMessages = Array(messages.suffix(recentCount))
        let oldMessages = Array(messages.dropLast(recentCount))
        
        guard !oldMessages.isEmpty else {
            return recentMessages
        }
        
        // Calculate available tokens
        let recentTokens = await tokenCounter.countTokens(recentMessages)
        let availableForOld = maxTokens - recentTokens - AppConstants.tokenReserveOverhead
        
        guard availableForOld > AppConstants.minimumTokensForSummary else {
            return recentMessages
        }
        
        // Group old messages by time or topic (simple: by position)
        let chunkSize = max(1, oldMessages.count / 3)
        var compactedOld: [Message] = []
        
        for i in stride(from: 0, to: oldMessages.count, by: chunkSize) {
            let chunk = Array(oldMessages[i..<min(i + chunkSize, oldMessages.count)])
            let summary = try await summarizer.summarize(chunk, level: .medium)
            let summaryMessage = Message(
                role: .system,
                content: "Summary: \(summary)"
            )
            compactedOld.append(summaryMessage)
        }
        
        // Check if compacted old messages fit
        let compactedTokens = await tokenCounter.countTokens(compactedOld)
        if recentTokens + compactedTokens <= maxTokens {
            return compactedOld + recentMessages
        } else {
            // Still too large, summarize all old messages together
            let fullSummary = try await summarizer.summarize(oldMessages, level: .heavy)
            let summaryMessage = Message(
                role: .system,
                content: "Previous conversation summary: \(fullSummary)"
            )
            return [summaryMessage] + recentMessages
        }
    }
    
    /// Truncate messages if they exceed token budget
    /// - Parameters:
    ///   - messages: Messages to truncate
    ///   - maxTokens: Maximum token budget
    /// - Returns: Truncated messages
    private func truncateMessages(_ messages: [Message], maxTokens: Int) async throws -> [Message] {
        var result: [Message] = []
        var currentTokens = 0
        
        // Keep messages from most recent
        for message in messages.reversed() {
            let messageTokens = await tokenCounter.countTokens(message)
            if currentTokens + messageTokens <= maxTokens {
                result.insert(message, at: 0)
                currentTokens += messageTokens
            } else {
                break
            }
        }
        
        return result
    }
}



