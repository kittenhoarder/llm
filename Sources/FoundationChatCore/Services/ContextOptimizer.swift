//
//  ContextOptimizer.swift
//  FoundationChatCore
//
//  Main orchestrator for context management and optimization
//

import Foundation
import FoundationModels

/// Configuration for context optimization
@available(macOS 26.0, iOS 26.0, *)
public struct ContextOptimizerConfig: Sendable {
    /// Maximum context tokens (default: 4096)
    public let maxContextTokens: Int
    
    /// Tokens to reserve for output (default: 500)
    public let outputReserveTokens: Int
    
    /// Threshold to start compacting (default: 3500, 85% of max)
    public let compactionThreshold: Int
    
    /// Number of recent messages to keep full (default: 5)
    public let recentMessagesCount: Int
    
    public init(
        maxContextTokens: Int = 4096,
        outputReserveTokens: Int = 500,
        compactionThreshold: Int = 3500,
        recentMessagesCount: Int = 5
    ) {
        self.maxContextTokens = maxContextTokens
        self.outputReserveTokens = outputReserveTokens
        self.compactionThreshold = compactionThreshold
        self.recentMessagesCount = recentMessagesCount
    }
}

/// Optimized context result
@available(macOS 26.0, iOS 26.0, *)
public struct OptimizedContext: Sendable {
    /// Optimized messages
    public let messages: [Message]
    
    /// Token usage breakdown
    public let tokenUsage: TokenUsage
    
    /// Number of messages truncated/summarized
    public let messagesTruncated: Int
    
    public init(
        messages: [Message],
        tokenUsage: TokenUsage,
        messagesTruncated: Int
    ) {
        self.messages = messages
        self.tokenUsage = tokenUsage
        self.messagesTruncated = messagesTruncated
    }
}

/// Token usage breakdown
@available(macOS 26.0, iOS 26.0, *)
public struct TokenUsage: Sendable {
    /// Tokens used by system prompt
    public let systemTokens: Int
    
    /// Tokens used by tool definitions
    public let toolTokens: Int
    
    /// Tokens used by messages
    public let messageTokens: Int
    
    /// Total tokens used
    public let totalTokens: Int
    
    /// Available tokens remaining
    public let availableTokens: Int
    
    public init(
        systemTokens: Int = 0,
        toolTokens: Int = 0,
        messageTokens: Int = 0,
        totalTokens: Int = 0,
        availableTokens: Int = 0
    ) {
        self.systemTokens = systemTokens
        self.toolTokens = toolTokens
        self.messageTokens = messageTokens
        self.totalTokens = totalTokens
        self.availableTokens = availableTokens
    }
}

/// Main context optimizer
@available(macOS 26.0, iOS 26.0, *)
public actor ContextOptimizer {
    /// Configuration
    private let config: ContextOptimizerConfig
    
    /// Token counter
    private let tokenCounter = TokenCounter()
    
    /// Message compactor
    private let compactor: MessageCompactor
    
    public init(config: ContextOptimizerConfig = ContextOptimizerConfig()) {
        self.config = config
        self.compactor = MessageCompactor(recentMessagesCount: config.recentMessagesCount)
    }
    
    /// Optimize context for a conversation
    /// - Parameters:
    ///   - messages: Conversation messages
    ///   - systemPrompt: Optional system prompt
    ///   - tools: Available tools
    /// - Returns: Optimized context
    public func optimizeContext(
        messages: [Message],
        systemPrompt: String? = nil,
        tools: [any Tool] = []
    ) async throws -> OptimizedContext {
        // Calculate token usage for system prompt and tools
        let systemTokens = systemPrompt != nil ? await tokenCounter.countTokens(systemPrompt!) : 0
        let toolTokens = estimateToolTokens(tools)
        
        // Calculate available tokens for messages
        let reservedTokens = systemTokens + toolTokens + config.outputReserveTokens
        let availableForMessages = config.maxContextTokens - reservedTokens
        
        // Count current message tokens
        let currentMessageTokens = await tokenCounter.countTokens(messages)
        
        // If messages fit within budget, return as-is
        if currentMessageTokens <= availableForMessages {
            let totalTokens = systemTokens + toolTokens + currentMessageTokens
            return OptimizedContext(
                messages: messages,
                tokenUsage: TokenUsage(
                    systemTokens: systemTokens,
                    toolTokens: toolTokens,
                    messageTokens: currentMessageTokens,
                    totalTokens: totalTokens,
                    availableTokens: config.maxContextTokens - totalTokens
                ),
                messagesTruncated: 0
            )
        }
        
        // Need to compact messages
        let compactedMessages = try await compactor.compact(
            messages: messages,
            maxTokens: availableForMessages
        )
        
        let compactedTokens = await tokenCounter.countTokens(compactedMessages)
        let totalTokens = systemTokens + toolTokens + compactedTokens
        let messagesTruncated = messages.count - compactedMessages.count
        
        return OptimizedContext(
            messages: compactedMessages,
            tokenUsage: TokenUsage(
                systemTokens: systemTokens,
                toolTokens: toolTokens,
                messageTokens: compactedTokens,
                totalTokens: totalTokens,
                availableTokens: config.maxContextTokens - totalTokens
            ),
            messagesTruncated: messagesTruncated
        )
    }
    
    /// Optimize context for a transcript
    /// - Parameters:
    ///   - transcript: Conversation transcript
    ///   - systemPrompt: Optional system prompt
    ///   - tools: Available tools
    /// - Returns: Optimized transcript
    /// Note: This method may need adjustment based on actual Transcript API structure
    public func optimizeTranscript(
        transcript: Transcript,
        systemPrompt: String? = nil,
        tools: [any Tool] = []
    ) async throws -> Transcript {
        // For now, return transcript as-is
        // Full implementation would require access to transcript internals
        return transcript
    }
    
    /// Estimate tokens used by tool definitions
    /// - Parameter tools: Tools to estimate
    /// - Returns: Estimated token count
    private func estimateToolTokens(_ tools: [any Tool]) -> Int {
        // Rough estimate: each tool description + name + parameters ≈ 50-100 tokens
        // We'll use 75 tokens per tool as a conservative estimate
        return tools.count * 75
    }
    
    /// Convert transcript to messages
    /// Note: Transcript API structure may vary - this is a simplified conversion
    private func transcriptToMessages(_ transcript: Transcript) -> [Message] {
        // Since we can't directly access transcript entries, we'll need to work with
        // the transcript as provided by FoundationModels API
        // For now, return empty array - this method may need adjustment based on actual API
        return []
    }
    
    /// Convert messages to transcript
    private func messagesToTranscript(_ messages: [Message]) -> Transcript {
        var entries: [Transcript.Entry] = []
        
        for message in messages {
            switch message.role {
            case .user, .system:
                let textSegment = Transcript.TextSegment(content: message.content)
                let prompt = Transcript.Prompt(segments: [.text(textSegment)])
                entries.append(.prompt(prompt))
            case .assistant:
                let textSegment = Transcript.TextSegment(content: message.content)
                let response = Transcript.Response(assetIDs: [], segments: [.text(textSegment)])
                entries.append(.response(response))
            }
        }
        
        return Transcript(entries: entries)
    }
    
    /// Extract text from prompt
    private func extractTextFromPrompt(_ prompt: Transcript.Prompt) -> String {
        return prompt.segments.compactMap { segment in
            if case .text(let textSegment) = segment {
                return textSegment.content
            }
            return nil
        }.joined(separator: " ")
    }
    
    /// Extract text from response
    private func extractTextFromResponse(_ response: Transcript.Response) -> String {
        return response.segments.compactMap { segment in
            if case .text(let textSegment) = segment {
                return textSegment.content
            }
            return nil
        }.joined(separator: " ")
    }
}

