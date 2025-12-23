//
//  SerpAPIFoundationTool.swift
//  FoundationChatCore
//
//  SerpAPI tool adapter for Apple Foundation Models
//

import Foundation
import FoundationModels

/// SerpAPI search tool for Apple Foundation Models
@available(macOS 26.0, iOS 26.0, *)
public struct SerpAPIFoundationTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "serpapi_search"
    public let description = "Search the web using SerpAPI (Google search) to find current information, news, facts, and real-time data. Use this tool when the user asks you to 'search', 'look up', 'find information online', asks about current events, recent data, or information that may have changed. Always use this tool when explicitly asked to search the web or find information online. Returns formatted search results with titles, URLs, snippets, and extracted content."
    
    /// API key for SerpAPI (optional - will be read from UserDefaults or environment if nil)
    private let apiKey: String?
    
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }
    
    @Generable
    public struct Arguments {
        public let query: String
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        // Get API key from various sources
        let resolvedApiKey: String? = apiKey ?? getApiKey()
        
        guard let key = resolvedApiKey, !key.isEmpty else {
            return "SerpAPI key not configured. Please set your API key in Settings → API Keys (macOS) or via the SERPAPI_API_KEY environment variable. Get your key at https://serpapi.com"
        }
        
        // Create client and tool
        let client = SerpAPIClient(apiKey: key)
        let tool = SerpAPITool(client: client)
        
        // Normalize query
        let normalizedQuery = normalizeQuery(arguments.query)
        
        do {
            return try await tool.search(query: normalizedQuery)
        } catch SerpAPIError.missingApiKey {
            return "SerpAPI key not configured. Please set your API key in Settings → API Keys (macOS) or via the SERPAPI_API_KEY environment variable. Get your key at https://serpapi.com"
        } catch SerpAPIError.invalidApiKey {
            return "SerpAPI authentication failed. Please check your API key in Settings → API Keys."
        } catch SerpAPIError.rateLimitExceeded {
            return "SerpAPI rate limit exceeded. Please try again later or upgrade your plan at https://serpapi.com"
        } catch SerpAPIError.noResults {
            return "No search results found for this query. You should answer using your own knowledge."
        } catch SerpAPIError.networkError(let error) {
            return "Network error while searching: \(error.localizedDescription). Please try again or answer using your own knowledge."
        } catch SerpAPIError.httpError(let statusCode) {
            if statusCode == 401 || statusCode == 403 {
                return "SerpAPI authentication failed. Please check your API key in Settings → API Keys."
            } else if statusCode == 429 {
                return "SerpAPI rate limit exceeded. Please try again later or upgrade your plan at https://serpapi.com"
            } else {
                return "SerpAPI returned an error (HTTP \(statusCode)). Please try again or answer using your own knowledge."
            }
        } catch SerpAPIError.invalidResponse {
            return "SerpAPI returned an invalid response. Please try again or answer using your own knowledge."
        } catch {
            return "Error searching SerpAPI: \(error.localizedDescription). Please answer using your own knowledge if possible."
        }
    }
    
    /// Get API key from UserDefaults or environment variable
    /// - Returns: API key if found, nil otherwise
    private func getApiKey() -> String? {
        // Try UserDefaults first (for UI settings)
        if let key = UserDefaults.standard.string(forKey: UserDefaultsKey.serpapiApiKey), !key.isEmpty {
            return key
        }
        
        // Fall back to environment variable (for CLI)
        if let key = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"], !key.isEmpty {
            return key
        }
        
        return nil
    }
    
    /// Normalize query to improve search success rate
    /// - Parameter query: Original query
    /// - Returns: Normalized query optimized for search
    private func normalizeQuery(_ query: String) -> String {
        var normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common question prefixes that don't help with search
        let questionPrefixes = [
            "what is ", "what are ", "what was ", "what were ",
            "who is ", "who are ", "who was ", "who were ",
            "where is ", "where are ", "where was ", "where were ",
            "when is ", "when are ", "when was ", "when were ",
            "why is ", "why are ", "why was ", "why were ",
            "how is ", "how are ", "how was ", "how were ",
            "search for ", "look up ", "find ", "search ",
            "use serpapi to find ", "use serpapi_search to find ",
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
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

