//
//  SerpAPITool.swift
//  FoundationChatCore
//
//  LLM tool wrapper for SerpAPI
//

import Foundation

/// Tool interface for LLM to search SerpAPI
public struct SerpAPITool: Sendable {
    /// The underlying SerpAPI client
    private let client: SerpAPIClient
    
    /// Maximum number of results to return
    private let maxResults: Int
    
    /// Maximum length for snippet text (to keep responses concise)
    private let maxSnippetLength: Int
    
    /// Initializes a new SerpAPI tool
    /// - Parameters:
    ///   - client: SerpAPI client instance
    ///   - maxResults: Maximum number of results to return (defaults to 5)
    ///   - maxSnippetLength: Maximum characters for snippet (defaults to 500)
    public init(
        client: SerpAPIClient,
        maxResults: Int = 5,
        maxSnippetLength: Int = 500
    ) {
        self.client = client
        self.maxResults = maxResults
        self.maxSnippetLength = maxSnippetLength
    }
    
    /// Searches SerpAPI and returns formatted result for LLM consumption
    /// - Parameter query: The search query
    /// - Returns: Formatted string with search results
    /// - Throws: SerpAPIError if the search fails
    public func search(query: String) async throws -> String {
        let response = try await client.search(query: query)
        return formatResponse(response)
    }
    
    /// Formats SerpAPI response for LLM consumption
    /// - Parameter response: The API response
    /// - Returns: Formatted string prioritizing answer box, then organic results
    internal func formatResponse(_ response: SerpAPIResponse) -> String {
        var parts: [String] = []
        
        // Priority 1: Answer box (direct answer)
        if let answerBox = response.answerBox {
            if let answer = answerBox.answer, !answer.isEmpty {
                parts.append("Answer: \(answer)")
            } else if let snippet = answerBox.snippet, !snippet.isEmpty {
                parts.append("Answer: \(snippet)")
            }
            
            if let title = answerBox.title, !title.isEmpty {
                parts.append("Source: \(title)")
            }
            
            if let link = answerBox.link, !link.isEmpty {
                parts.append("URL: \(link)")
            }
        }
        
        // Priority 2: Knowledge graph
        if let knowledgeGraph = response.knowledgeGraph {
            if let description = knowledgeGraph.description, !description.isEmpty {
                let truncated = description.count > maxSnippetLength
                    ? String(description.prefix(maxSnippetLength)) + "..."
                    : description
                parts.append("Summary: \(truncated)")
            }
            
            if let title = knowledgeGraph.title, !title.isEmpty {
                parts.append("Topic: \(title)")
            }
            
            if let source = knowledgeGraph.source {
                if let name = source.name, !name.isEmpty {
                    if !parts.contains(where: { $0.contains("Source:") }) {
                        parts.append("Source: \(name)")
                    }
                }
                if let link = source.link, !link.isEmpty {
                    if !parts.contains(where: { $0.contains("URL:") }) {
                        parts.append("URL: \(link)")
                    }
                }
            }
        }
        
        // Priority 3: Organic results
        if let organicResults = response.organicResults, !organicResults.isEmpty {
            let resultsToInclude = Array(organicResults.prefix(maxResults))
            if !resultsToInclude.isEmpty {
                parts.append("\nSearch Results (\(resultsToInclude.count) of \(organicResults.count)):")
                
                for (index, result) in resultsToInclude.enumerated() {
                    var resultLine = "\(index + 1). "
                    
                    if let title = result.title, !title.isEmpty {
                        resultLine += title
                    }
                    
                    if let link = result.link, !link.isEmpty {
                        resultLine += "\n   URL: \(link)"
                    }
                    
                    if let snippet = result.snippet, !snippet.isEmpty {
                        let truncatedSnippet = snippet.count > maxSnippetLength
                            ? String(snippet.prefix(maxSnippetLength)) + "..."
                            : snippet
                        resultLine += "\n   \(truncatedSnippet)"
                    }
                    
                    if let source = result.source, !source.isEmpty {
                        resultLine += "\n   Source: \(source)"
                    }
                    
                    parts.append(resultLine)
                }
                
                if organicResults.count > maxResults {
                    parts.append("\n(and \(organicResults.count - maxResults) more results)")
                }
            }
        }
        
        // Priority 4: Related questions
        if let relatedQuestions = response.relatedQuestions, !relatedQuestions.isEmpty {
            let questionsToInclude = Array(relatedQuestions.prefix(3))
            if !questionsToInclude.isEmpty {
                parts.append("\nRelated Questions:")
                for (index, question) in questionsToInclude.enumerated() {
                    var questionLine = "\(index + 1). "
                    
                    if let questionText = question.question, !questionText.isEmpty {
                        questionLine += questionText
                    } else if let title = question.title, !title.isEmpty {
                        questionLine += title
                    }
                    
                    if let snippet = question.snippet, !snippet.isEmpty {
                        let truncated = snippet.count > maxSnippetLength
                            ? String(snippet.prefix(maxSnippetLength)) + "..."
                            : snippet
                        questionLine += "\n   \(truncated)"
                    }
                    
                    parts.append(questionLine)
                }
            }
        }
        
        // If still no content, return a message that helps the model understand
        // it should fall back to its own knowledge
        if parts.isEmpty {
            return "No search results available for this query. You should answer using your own knowledge."
        }
        
        return parts.joined(separator: "\n")
    }
}

