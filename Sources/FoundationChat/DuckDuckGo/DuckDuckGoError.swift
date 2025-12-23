//
//  DuckDuckGoError.swift
//  FoundationChat
//
//  Error types for DuckDuckGo API operations
//

import Foundation

/// Errors that can occur when interacting with DuckDuckGo Instant Answers API
public enum DuckDuckGoError: LocalizedError {
    /// Network or connection error
    case networkError(Error)
    
    /// Invalid or malformed API response
    case invalidResponse
    
    /// Valid response but no answer/content available
    case noResults
    
    /// JSON decoding error
    case decodingError(Error)
    
    /// Invalid query (empty or malformed)
    case invalidQuery(String)
    
    /// Request timeout
    case timeout
    
    /// HTTP error with status code
    case httpError(statusCode: Int)
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from DuckDuckGo API"
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
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .networkError:
            return "Unable to connect to DuckDuckGo API. Please check your internet connection."
        case .invalidResponse:
            return "The API returned an unexpected response format."
        case .noResults:
            return "DuckDuckGo could not find an instant answer for your query."
        case .decodingError:
            return "The API response could not be parsed."
        case .invalidQuery:
            return "The search query is empty or invalid."
        case .timeout:
            return "The request took too long to complete."
        case .httpError:
            return "The server returned an error status code."
        }
    }
}










