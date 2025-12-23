//
//  WebSearchFoundationTool.swift
//  FoundationChatCore
//
//  Web search tool adapter for Apple Foundation Models
//

import Foundation
import FoundationModels

/// Web search tool for Apple Foundation Models
@available(macOS 26.0, iOS 26.0, *)
public struct WebSearchFoundationTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "web_search"
    public let description = "Search the web using real search engines (Google, Bing) to find current information, news, facts, and real-time data. Use this tool when the user asks you to 'search', 'look up', 'find information online', asks about current events, recent data, or information that may have changed. Always use this tool when explicitly asked to search the web or find information online. Returns formatted search results with titles, URLs, snippets, and extracted content."
    
    /// Maximum number of results to return
    private let maxResults: Int
    
    /// Maximum content length per result
    private let maxContentLength: Int
    
    /// Whether to extract content from top results
    private let extractContent: Bool
    
    public init(
        maxResults: Int = 5,
        maxContentLength: Int = 500,
        extractContent: Bool = true
    ) {
        self.maxResults = maxResults
        self.maxContentLength = maxContentLength
        self.extractContent = extractContent
    }
    
    @Generable
    public struct Arguments {
        public let query: String
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let tool = WebSearchTool(
            maxResults: maxResults,
            maxContentLength: maxContentLength
        )
        
        // Perform search
        let results = try await tool.search(query: arguments.query)
        
        // Optionally extract content from top results
        var formattedResults = formatResults(results)
        
        if extractContent && !results.isEmpty {
            // Extract content from top 2-3 results
            let topResults = Array(results.prefix(min(3, results.count)))
            for (index, result) in topResults.enumerated() {
                if let url = URL(string: result.url) {
                    do {
                        let content = try await tool.extractContent(from: url)
                        if !content.isEmpty {
                            formattedResults += "\n\nContent from result \(index + 1) (\(result.title)):\n\(String(content.prefix(maxContentLength)))"
                        }
                    } catch {
                        // Continue if content extraction fails
                        continue
                    }
                }
            }
        }
        
        return formattedResults
    }
    
    /// Format search results for LLM consumption
    private func formatResults(_ results: [SearchResult]) -> String {
        guard !results.isEmpty else {
            return "No search results found for this query."
        }
        
        var formatted = "Web Search Results (\(results.count) results):\n\n"
        
        for (index, result) in results.enumerated() {
            formatted += "\(index + 1). \(result.title)\n"
            formatted += "   URL: \(result.url)\n"
            if !result.snippet.isEmpty {
                formatted += "   \(result.snippet)\n"
            }
            formatted += "\n"
        }
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}




