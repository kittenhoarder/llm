//
//  SerpAPIError.swift
//  FoundationChatCore
//
//  Error types for SerpAPI operations
//

import Foundation

/// Errors that can occur when interacting with SerpAPI
public enum SerpAPIError: LocalizedError {
    /// Network or connection error
    case networkError(Error)
    
    /// Invalid or malformed API response
    case invalidResponse
    
    /// Valid response but no results available
    case noResults
    
    /// JSON decoding error
    case decodingError(Error)
    
    /// Invalid query (empty or malformed)
    case invalidQuery(String)
    
    /// Request timeout
    case timeout
    
    /// HTTP error with status code
    case httpError(statusCode: Int)
    
    /// Missing API key
    case missingApiKey
    
    /// Invalid API key (authentication failed)
    case invalidApiKey
    
    /// Rate limit exceeded
    case rateLimitExceeded
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from SerpAPI"
        case .noResults:
            return "No results found for the query"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidQuery(let query):
            return "Invalid query: \(query)"
        case .timeout:
            return "Request timed out"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .missingApiKey:
            return "SerpAPI key not configured"
        case .invalidApiKey:
            return "SerpAPI authentication failed"
        case .rateLimitExceeded:
            return "SerpAPI rate limit exceeded"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .networkError:
            return "Unable to connect to SerpAPI. Please check your internet connection."
        case .invalidResponse:
            return "The API returned an unexpected response format."
        case .noResults:
            return "SerpAPI could not find results for your query."
        case .decodingError:
            return "The API response could not be parsed."
        case .invalidQuery:
            return "The search query is empty or invalid."
        case .timeout:
            return "The request took too long to complete."
        case .httpError(let statusCode):
            if statusCode == 401 || statusCode == 403 {
                return "SerpAPI authentication failed. Please check your API key."
            } else if statusCode == 429 {
                return "SerpAPI rate limit exceeded. Please try again later."
            } else {
                return "The server returned an error status code: \(statusCode)."
            }
        case .missingApiKey:
            return "Please set your API key in Settings → API Keys (macOS) or via the SERPAPI_API_KEY environment variable."
        case .invalidApiKey:
            return "Please check your API key in Settings → API Keys."
        case .rateLimitExceeded:
            return "Please try again later or upgrade your plan at https://serpapi.com"
        }
    }
}

