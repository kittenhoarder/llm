//
//  DuckDuckGoTool.swift
//  FoundationChatCore
//
//  LLM tool wrapper for DuckDuckGo Instant Answers API
//

import Foundation

/// Tool interface for LLM to search DuckDuckGo Instant Answers
public struct DuckDuckGoTool: Sendable {
    /// The underlying DuckDuckGo client
    private let client: DuckDuckGoClient
    
    /// Maximum length for abstract text (to keep responses concise)
    private let maxAbstractLength: Int
    
    /// Initializes a new DuckDuckGo tool
    /// - Parameters:
    ///   - client: DuckDuckGo client instance (defaults to new instance)
    ///   - maxAbstractLength: Maximum characters for abstract (defaults to 500)
    public init(
        client: DuckDuckGoClient = DuckDuckGoClient(),
        maxAbstractLength: Int = 500
    ) {
        self.client = client
        self.maxAbstractLength = maxAbstractLength
    }
    
    /// Searches DuckDuckGo Instant Answers and returns formatted result for LLM consumption
    /// - Parameter query: The search query
    /// - Returns: Formatted string with answer, abstract, or related information
    /// - Throws: DuckDuckGoError if the search fails
    public func search(query: String) async throws -> String {
        let response = try await client.search(query: query)
        return formatResponse(response)
    }
    
    /// Formats DuckDuckGo response for LLM consumption
    /// - Parameter response: The API response
    /// - Returns: Formatted string prioritizing Answer, then Abstract, then related topics
    internal func formatResponse(_ response: DuckDuckGoResponse) -> String {
        var parts: [String] = []
        
        // Priority 1: Direct answer (for calculations, definitions, etc.)
        if let answer = response.answer, !answer.isEmpty {
            parts.append("Answer: \(answer)")
            
            // Include answer type if available
            if let answerType = response.answerType, !answerType.isEmpty {
                parts.append("(Type: \(answerType))")
            }
        }
        
        // Priority 2: Definition
        if let definition = response.definition, !definition.isEmpty {
            parts.append("Definition: \(definition)")
            
            if let definitionSource = response.definitionSource, !definitionSource.isEmpty {
                parts.append("Source: \(definitionSource)")
            }
            
            if let definitionURL = response.definitionURL, !definitionURL.isEmpty {
                parts.append("URL: \(definitionURL)")
            }
        }
        
        // Priority 3: Abstract (topic summary)
        if let abstract = response.abstract, !abstract.isEmpty {
            let truncatedAbstract = abstract.count > maxAbstractLength
                ? String(abstract.prefix(maxAbstractLength)) + "..."
                : abstract
            parts.append("Summary: \(truncatedAbstract)")
        } else if let abstractText = response.abstractText, !abstractText.isEmpty {
            let truncatedAbstract = abstractText.count > maxAbstractLength
                ? String(abstractText.prefix(maxAbstractLength)) + "..."
                : abstractText
            parts.append("Summary: \(truncatedAbstract)")
        }
        
        // Add heading if available
        if let heading = response.heading, !heading.isEmpty {
            parts.append("Topic: \(heading)")
        }
        
        // Add source attribution for abstract
        if let abstractSource = response.abstractSource, !abstractSource.isEmpty {
            if !parts.contains(where: { $0.contains("Source:") }) {
                parts.append("Source: \(abstractSource)")
            }
        }
        
        if let abstractURL = response.abstractURL, !abstractURL.isEmpty {
            if !parts.contains(where: { $0.contains("URL:") }) {
                parts.append("URL: \(abstractURL)")
            }
        }
        
        // Priority 4: Related topics (limit to first 3 for brevity)
        if let relatedTopics = response.relatedTopics, !relatedTopics.isEmpty {
            let topicsToInclude = Array(relatedTopics.prefix(3))
            if !topicsToInclude.isEmpty {
                parts.append("\nRelated Topics:")
                for (index, topic) in topicsToInclude.enumerated() {
                    var topicLine = "\(index + 1). "
                    
                    if let text = topic.text, !text.isEmpty {
                        topicLine += text
                    } else if let result = topic.result, !result.isEmpty {
                        topicLine += result
                    }
                    
                    if let url = topic.firstURL, !url.isEmpty {
                        topicLine += " (\(url))"
                    }
                    
                    parts.append(topicLine)
                }
                
                if relatedTopics.count > 3 {
                    parts.append("(and \(relatedTopics.count - 3) more)")
                }
            }
        }
        
        // Priority 5: Results array (if no other content)
        if parts.isEmpty, let results = response.results, !results.isEmpty {
            let resultsToInclude = Array(results.prefix(3))
            for (index, result) in resultsToInclude.enumerated() {
                var resultLine = "\(index + 1). "
                
                if let text = result.text, !text.isEmpty {
                    resultLine += text
                } else if let resultText = result.result, !resultText.isEmpty {
                    resultLine += resultText
                }
                
                if let url = result.firstURL, !url.isEmpty {
                    resultLine += " (\(url))"
                }
                
                parts.append(resultLine)
            }
        }
        
        // If still no content, return a message that helps the model understand
        // it should fall back to its own knowledge
        if parts.isEmpty {
            return "No instant answer available for this query. DuckDuckGo Instant Answers does not have a pre-formatted answer for this query. You should answer using your own knowledge."
        }
        
        return parts.joined(separator: "\n")
    }
}


