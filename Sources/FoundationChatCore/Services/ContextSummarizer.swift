//
//  ContextSummarizer.swift
//  FoundationChatCore
//
//  Service for summarizing conversation history using Foundation Models
//

import Foundation
import FoundationModels

/// Service for summarizing conversation context
@available(macOS 26.0, iOS 26.0, *)
public actor ContextSummarizer {
    /// Model service for summarization (lazy initialization to avoid blocking)
    private var _modelService: ModelService?
    private var modelService: ModelService {
        get async {
            if _modelService == nil {
                // Create ModelService in a detached task to avoid blocking
                _modelService = await Task.detached(priority: .userInitiated) {
                    ModelService()
                }.value
            }
            return _modelService!
        }
    }
    
    /// Token counter for estimating costs
    private let tokenCounter = TokenCounter()
    
    public init() {
        // ModelService will be created lazily when first accessed
    }
    
    /// Summarize a conversation in 2-3 sentences
    /// - Parameter messages: Messages to summarize
    /// - Returns: Summary string
    public func summarize(_ messages: [Message]) async throws -> String {
        guard !messages.isEmpty else {
            return ""
        }
        
        // Format messages for summarization
        let conversationText = formatMessagesForSummarization(messages)
        
        // Create compact summarization prompt
        let prompt = """
        Summarize the following conversation in 2-3 sentences, focusing on key questions, answers, and decisions made.
        
        Conversation:
        \(conversationText)
        """
        
        // Use model service to generate summary
        let service = await modelService
        let response = try await service.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Summarize messages with different levels of detail
    /// - Parameters:
    ///   - messages: Messages to summarize
    ///   - level: Summarization level (light, medium, heavy)
    /// - Returns: Summary string
    public func summarize(_ messages: [Message], level: SummarizationLevel) async throws -> String {
        guard !messages.isEmpty else {
            return ""
        }
        
        let conversationText = formatMessagesForSummarization(messages)
        
        let instruction: String
        switch level {
        case .light:
            instruction = "Summarize the key points in 1-2 sentences."
        case .medium:
            instruction = "Summarize the main topics and outcomes in 2-3 sentences."
        case .heavy:
            instruction = "Provide a concise summary of the essential information in 3-4 sentences, focusing only on the most important facts and decisions."
        }
        
        let prompt = """
        \(instruction)
        
        Conversation:
        \(conversationText)
        """
        
        let service = await modelService
        let response = try await service.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Summarize a single message or text block
    /// - Parameter text: Text to summarize
    /// - Returns: Summary string
    public func summarize(_ text: String) async throws -> String {
        guard !text.isEmpty else {
            return ""
        }
        
        let prompt = """
        Summarize the following text in 2-3 sentences, focusing on key information:
        
        \(text)
        """
        
        let service = await modelService
        let response = try await service.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Format messages for summarization
    /// - Parameter messages: Messages to format
    /// - Returns: Formatted string
    private func formatMessagesForSummarization(_ messages: [Message]) -> String {
        return messages.map { message in
            let role = message.role.rawValue.capitalized
            let content = message.content
            return "\(role): \(content)"
        }.joined(separator: "\n\n")
    }
}

/// Summarization level
@available(macOS 26.0, iOS 26.0, *)
public enum SummarizationLevel: Sendable {
    case light    // 1-2 sentences
    case medium   // 2-3 sentences
    case heavy    // 3-4 sentences, very concise
}



