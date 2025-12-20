//
//  DuckDuckGoFoundationTool.swift
//  FoundationChatCore
//
//  DuckDuckGo tool adapter for Apple Foundation Models
//

import Foundation
import FoundationModels

/// DuckDuckGo search tool for Apple Foundation Models
@available(macOS 26.0, iOS 26.0, *)
public struct DuckDuckGoFoundationTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "duckduckgo_search"
    public let description = "Search DuckDuckGo Instant Answers API to find current information, facts, definitions, calculations, and real-time data. Use this tool when the user asks you to 'search', 'look up', 'find information', or asks about current events, recent data, or information that may have changed. Always use this tool when explicitly asked to search online or use DuckDuckGo. Returns concise, formatted answers suitable for LLM context."
    
    public init() {}
    
    @Generable
    public struct Arguments {
        public let query: String
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let tool = DuckDuckGoTool()
        
        // Normalize query to improve DuckDuckGo Instant Answers success rate
        // Remove question words and extract the core query
        let normalizedQuery = normalizeQuery(arguments.query)
        
        do {
            return try await tool.search(query: normalizedQuery)
        } catch DuckDuckGoError.noResults {
            // Try alternative query phrasings before giving up
            let alternativeQueries = generateAlternativeQueries(normalizedQuery)
            for altQuery in alternativeQueries {
                do {
                    let result = try await tool.search(query: altQuery)
                    // If we got results, return them with context
                    return "Found information for related query '\(altQuery)':\n\(result)"
                } catch {
                    // Continue to next alternative
                    continue
                }
            }
            
            // If all alternatives failed, return a helpful message
            return "DuckDuckGo Instant Answers API does not have an instant answer for this query. The query may be too specific, require real-time data, or not match DuckDuckGo's instant answer database. You should answer the question using your own knowledge instead."
        } catch DuckDuckGoError.networkError(let error) {
            return "Network error while searching DuckDuckGo: \(error.localizedDescription). Please answer using your own knowledge."
        } catch {
            return "Error searching DuckDuckGo: \(error.localizedDescription). Please answer using your own knowledge if possible."
        }
    }
    
    /// Normalize query to improve DuckDuckGo Instant Answers success rate
    /// - Parameter query: Original query
    /// - Returns: Normalized query optimized for DuckDuckGo Instant Answers
    private func normalizeQuery(_ query: String) -> String {
        var normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common question prefixes that don't help with instant answers
        let questionPrefixes = [
            "what is ", "what are ", "what was ", "what were ",
            "who is ", "who are ", "who was ", "who were ",
            "where is ", "where are ", "where was ", "where were ",
            "when is ", "when are ", "when was ", "when were ",
            "why is ", "why are ", "why was ", "why were ",
            "how is ", "how are ", "how was ", "how were ",
            "search for ", "look up ", "find ", "search ",
            "use duckduckgo to find ", "use duckduckgo_search to find ",
            "please search ", "please look up "
        ]
        
        let lowercased = normalized.lowercased()
        for prefix in questionPrefixes {
            if lowercased.hasPrefix(prefix) {
                normalized = String(normalized.dropFirst(prefix.count))
                break
            }
        }
        
        // Remove trailing question marks and periods
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "?."))
        
        // For calculations, extract just the expression
        if let calculationMatch = normalized.range(of: #"\d+\s*[+\-*/]\s*\d+"#, options: .regularExpression) {
            normalized = String(normalized[calculationMatch])
        }
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Generate alternative query phrasings to improve success rate
    /// - Parameter query: Original normalized query
    /// - Returns: Array of alternative query strings to try
    private func generateAlternativeQueries(_ query: String) -> [String] {
        var alternatives: [String] = []
        
        // Pattern: "X of Y" -> try "Y X" (e.g., "capital of France" -> "France capital")
        if let match = query.range(of: #"(.+?)\s+of\s+(.+)"#, options: .regularExpression) {
            let parts = String(query[match]).components(separatedBy: " of ")
            if parts.count == 2 {
                alternatives.append("\(parts[1]) \(parts[0])")
            }
        }
        
        // Pattern: "what is X" -> try just "X"
        // Already handled in normalizeQuery, but extract key terms
        
        // Extract key nouns (simple heuristic: words that are capitalized or important terms)
        let words = query.components(separatedBy: .whitespaces)
        if words.count > 1 {
            // Try just the last word (often the main subject)
            if let lastWord = words.last, lastWord.count > 2 {
                alternatives.append(lastWord)
            }
            // Try just the first capitalized word
            for word in words {
                if word.first?.isUppercase == true && word.count > 2 {
                    alternatives.append(word)
                    break
                }
            }
        }
        
        return alternatives
    }
}


