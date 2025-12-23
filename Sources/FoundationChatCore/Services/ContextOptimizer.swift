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
    
    /// Optimize context using SVDB semantic retrieval
    /// - Parameters:
    ///   - messages: Full conversation messages
    ///   - query: Current user message to use as search query
    ///   - conversationId: The conversation ID for SVDB lookup
    ///   - systemPrompt: Optional system prompt
    ///   - tools: Available tools
    /// - Returns: Optimized context with relevant messages retrieved from SVDB
    public func optimizeContextWithSVDB(
        messages: [Message],
        query: String,
        conversationId: UUID,
        systemPrompt: String? = nil,
        tools: [any Tool] = []
    ) async throws -> OptimizedContext {
        // Check if SVDB optimization is enabled
        let useSVDB = UserDefaults.standard.object(forKey: UserDefaultsKey.useSVDBForContextOptimization) as? Bool ?? true
        
        guard useSVDB else {
            // Fall back to standard optimization
            return try await optimizeContext(messages: messages, systemPrompt: systemPrompt, tools: tools)
        }
        
        // Calculate token usage for system prompt and tools
        let systemTokens = systemPrompt != nil ? await tokenCounter.countTokens(systemPrompt!) : 0
        let toolTokens = estimateToolTokens(tools)
        
        // Calculate available tokens for messages
        let reservedTokens = systemTokens + toolTokens + config.outputReserveTokens
        let availableForMessages = config.maxContextTokens - reservedTokens
        
        // Count original message tokens (for savings calculation)
        let originalMessageTokens = await tokenCounter.countTokens(messages)
        
        // Get configuration for SVDB retrieval
        let svdbTopK = UserDefaults.standard.integer(forKey: UserDefaultsKey.svdbContextTopK)
        let topK = svdbTopK > 0 ? svdbTopK : AppConstants.defaultSVDBContextTopK
        
        let svdbRecentMessages = UserDefaults.standard.integer(forKey: UserDefaultsKey.svdbContextRecentMessages)
        let recentMessagesCount = svdbRecentMessages > 0 ? svdbRecentMessages : AppConstants.defaultSVDBContextRecentMessages
        
        // Always include recent messages (last N messages)
        let recentMessages = Array(messages.suffix(recentMessagesCount))
        let recentMessageIds = Set(recentMessages.map { $0.id })
        
        // Always include the most recent user message (current query) if it exists
        // This ensures the current message is in context even if not yet indexed
        var currentUserMessage: Message? = nil
        if let lastMessage = messages.last, lastMessage.role == .user {
            currentUserMessage = lastMessage
        }
        
        // Try to retrieve relevant messages from SVDB
        var retrievedMessages: [Message] = []
        var svdbAvailable = false
        
        do {
            let messageChunks = try await RAGService.shared.searchRelevantMessages(
                query: query,
                conversationId: conversationId,
                topK: topK
            )
            
            if !messageChunks.isEmpty {
                svdbAvailable = true
                
                // Group chunks by message ID and reconstruct messages
                var messageMap: [UUID: (chunks: [MessageChunk], role: MessageRole, timestamp: Date)] = [:]
                
                for chunk in messageChunks {
                    if let existing = messageMap[chunk.messageId] {
                        var chunks = existing.chunks
                        chunks.append(chunk)
                        messageMap[chunk.messageId] = (chunks: chunks, role: chunk.role, timestamp: chunk.timestamp)
                    } else {
                        messageMap[chunk.messageId] = (chunks: [chunk], role: chunk.role, timestamp: chunk.timestamp)
                    }
                }
                
                // Reconstruct messages from chunks (sorted by timestamp)
                for (messageId, data) in messageMap.sorted(by: { $0.value.timestamp < $1.value.timestamp }) {
                    // Skip if already in recent messages
                    if recentMessageIds.contains(messageId) {
                        continue
                    }
                    
                    // Combine chunks into full message content
                    let chunks = data.chunks.sorted { $0.chunkIndex < $1.chunkIndex }
                    // Remove role prefix if present (format: "Role: content")
                    let content = chunks.map { chunk in
                        let text = chunk.content
                        // Remove role prefix if it exists (e.g., "User: " or "Assistant: ")
                        if let colonIndex = text.firstIndex(of: ":") {
                            let afterColon = text.index(after: colonIndex)
                            if afterColon < text.endIndex {
                                return String(text[afterColon...]).trimmingCharacters(in: .whitespaces)
                            }
                        }
                        return text
                    }.joined(separator: " ")
                    
                    // Find original message to preserve other properties (toolCalls, attachments, etc.)
                    if let originalMessage = messages.first(where: { $0.id == messageId }) {
                        // Create a copy with updated content to preserve immutability semantics
                        let reconstructedMessage = Message(
                            id: originalMessage.id,
                            role: originalMessage.role,
                            content: content,
                            timestamp: originalMessage.timestamp,
                            toolCalls: originalMessage.toolCalls,
                            responseTime: originalMessage.responseTime,
                            attachments: originalMessage.attachments
                        )
                        retrievedMessages.append(reconstructedMessage)
                    } else {
                        // Create new message from chunk data (shouldn't happen in normal flow)
                        let message = Message(
                            id: messageId,
                            role: data.role,
                            content: content,
                            timestamp: data.timestamp
                        )
                        retrievedMessages.append(message)
                    }
                }
            }
        } catch {
            // SVDB not available or error occurred, fall back to summarization
            Log.warn("⚠️ ContextOptimizer: SVDB retrieval failed, falling back to summarization: \(error.localizedDescription)")
        }
        
        // Combine recent messages with retrieved messages
        // Remove duplicates (in case a recent message was also retrieved)
        let retrievedMessageIds = Set(retrievedMessages.map { $0.id })
        let uniqueRecentMessages = recentMessages.filter { !retrievedMessageIds.contains($0.id) }
        
        // Always include current user message if it exists and isn't already included
        var messagesToInclude = retrievedMessages + uniqueRecentMessages
        if let currentMessage = currentUserMessage, !retrievedMessageIds.contains(currentMessage.id) {
            let isInRecent = recentMessageIds.contains(currentMessage.id)
            if !isInRecent {
                messagesToInclude.append(currentMessage)
            }
        }
        
        // Combine all messages and sort by timestamp to maintain chronological order
        var optimizedMessages = messagesToInclude
        optimizedMessages.sort { $0.timestamp < $1.timestamp }
        
        // If SVDB wasn't available or returned no results, fall back to standard optimization
        if !svdbAvailable || optimizedMessages.isEmpty {
            return try await optimizeContext(messages: messages, systemPrompt: systemPrompt, tools: tools)
        }
        
        // Count optimized message tokens
        var optimizedMessageTokens = await tokenCounter.countTokens(optimizedMessages)
        
        // If messages still exceed budget, truncate long messages first, then compact if needed
        if optimizedMessageTokens > availableForMessages {
            // First, truncate individual messages that are too long
            var truncatedMessages: [Message] = []
            var currentTokens = 0
            let maxTokensPerMessage = availableForMessages / max(1, optimizedMessages.count) // Rough per-message limit
            
            for message in optimizedMessages.reversed() { // Process from most recent
                let messageTokens = await tokenCounter.countTokens(message)
                
                if messageTokens > maxTokensPerMessage {
                    // Truncate long message
                    let maxChars = maxTokensPerMessage * 4 // Rough char-to-token conversion
                    let truncatedContent = String(message.content.prefix(maxChars))
                    let truncatedMessage = Message(
                        id: message.id,
                        role: message.role,
                        content: truncatedContent + "... [truncated]",
                        timestamp: message.timestamp,
                        toolCalls: message.toolCalls,
                        responseTime: message.responseTime,
                        attachments: message.attachments
                    )
                    truncatedMessages.insert(truncatedMessage, at: 0)
                    currentTokens += await tokenCounter.countTokens(truncatedMessage)
                } else if currentTokens + messageTokens <= availableForMessages {
                    truncatedMessages.insert(message, at: 0)
                    currentTokens += messageTokens
                } else {
                    // Message doesn't fit, skip it (we'll keep more recent messages)
                    break
                }
            }
            
            optimizedMessages = truncatedMessages
            optimizedMessageTokens = currentTokens
        }
        
        // If optimized messages still exceed budget after truncation, apply compaction
        if optimizedMessageTokens > availableForMessages {
            let compactedMessages = try await compactor.compact(
                messages: optimizedMessages,
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
        
        // Optimized messages fit within budget
        let totalTokens = systemTokens + toolTokens + optimizedMessageTokens
        let messagesTruncated = messages.count - optimizedMessages.count
        
        Log.debug("📊 ContextOptimizer: SVDB optimization - Original: \(originalMessageTokens) tokens, Optimized: \(optimizedMessageTokens) tokens, Saved: \(originalMessageTokens - optimizedMessageTokens) tokens")
        
        return OptimizedContext(
            messages: optimizedMessages,
            tokenUsage: TokenUsage(
                systemTokens: systemTokens,
                toolTokens: toolTokens,
                messageTokens: optimizedMessageTokens,
                totalTokens: totalTokens,
                availableTokens: config.maxContextTokens - totalTokens
            ),
            messagesTruncated: messagesTruncated
        )
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
