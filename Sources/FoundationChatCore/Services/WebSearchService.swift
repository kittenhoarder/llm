//
//  WebSearchService.swift
//  FoundationChatCore
//
//  Service for orchestrating web searches in isolated conversations
//

import Foundation
import FoundationModels

/// Service for managing web search operations
@available(macOS 26.0, iOS 26.0, *)
public actor WebSearchService {
    /// Model service for search conversations (lazy initialization to avoid blocking)
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
    
    /// Context summarizer for query summarization
    private let summarizer = ContextSummarizer()
    
    /// Web search tool
    private let webSearchTool = WebSearchFoundationTool()
    
    public init() {
        // ModelService will be created lazily when first accessed
    }
    
    /// Perform a web search in an isolated conversation
    /// - Parameters:
    ///   - query: Original search query
    ///   - context: Optional context from main conversation
    /// - Returns: Formatted search results
    public func performSearch(query: String, context: String? = nil) async throws -> String {
        // Summarize query and context if provided
        let searchQuery = try await summarizeQuery(query: query, context: context)
        
        // Register web search tool
        let service = await modelService
        await service.updateTools([webSearchTool])
        
        // Perform search using the tool
        // The model will automatically use the tool when it sees the search request
        let searchPrompt = """
        Search the web for: \(searchQuery)
        Use the web_search tool to find current information.
        """
        
        let response = try await service.respond(to: searchPrompt)
        
        // Return the response content (which should include tool results)
        return response.content
    }
    
    /// Summarize query and context for web search
    private func summarizeQuery(query: String, context: String?) async throws -> String {
        if let context = context, !context.isEmpty {
            // Combine query and context, then summarize
            let combined = """
            User query: \(query)
            
            Conversation context: \(context)
            """
            return try await summarizer.summarize(combined)
        } else {
            // Just return the query, possibly normalized
            return normalizeQuery(query)
        }
    }
    
    /// Normalize query for better search results
    private func normalizeQuery(_ query: String) -> String {
        var normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common question prefixes
        let questionPrefixes = [
            "what is ", "what are ", "who is ", "where is ",
            "when is ", "why is ", "how is ", "search for ",
            "look up ", "find ", "search "
        ]
        
        let lowercased = normalized.lowercased()
        for prefix in questionPrefixes {
            if lowercased.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
                break
            }
        }
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}



