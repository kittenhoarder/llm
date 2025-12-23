//
//  SerpAPIClient.swift
//  FoundationChatCore
//
//  Swift-native HTTP client for SerpAPI
//

import Foundation

/// Client for interacting with SerpAPI
public actor SerpAPIClient {
    /// Base URL for SerpAPI
    private let baseURL = "https://serpapi.com/search"
    
    /// API key for authentication
    private let apiKey: String
    
    /// URLSession for making HTTP requests
    private let session: URLSession
    
    /// Request timeout in seconds
    private let timeout: TimeInterval
    
    /// Maximum number of retry attempts
    private let maxRetries: Int
    
    /// Initializes a new SerpAPI client
    /// - Parameters:
    ///   - apiKey: SerpAPI API key (required)
    ///   - session: URLSession to use for requests (defaults to shared session)
    ///   - timeout: Request timeout in seconds (defaults to 10 seconds)
    ///   - maxRetries: Maximum number of retry attempts (defaults to 2)
    public init(
        apiKey: String,
        session: URLSession = .shared,
        timeout: TimeInterval = 10.0,
        maxRetries: Int = 2
    ) {
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
        self.maxRetries = maxRetries
    }
    
    /// Searches SerpAPI for a query
    /// - Parameter query: The search query
    /// - Returns: SerpAPIResponse containing the search results
    /// - Throws: SerpAPIError if the request fails or no results are found
    public func search(query: String) async throws -> SerpAPIResponse {
        // Validate query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw SerpAPIError.invalidQuery(query)
        }
        
        // Validate API key
        guard !apiKey.isEmpty else {
            throw SerpAPIError.missingApiKey
        }
        
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw SerpAPIError.invalidResponse
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "engine", value: "google"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        
        guard let url = urlComponents.url else {
            throw SerpAPIError.invalidResponse
        }
        
        // Create request with timeout
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Perform request with retry logic
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                
                // Check HTTP status
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    
                    // Handle specific error codes
                    if statusCode == 401 || statusCode == 403 {
                        throw SerpAPIError.invalidApiKey
                    } else if statusCode == 429 {
                        throw SerpAPIError.rateLimitExceeded
                    } else if !(200...299).contains(statusCode) {
                        throw SerpAPIError.httpError(statusCode: statusCode)
                    }
                }
                
                // Decode JSON response
                let decoder = JSONDecoder()
                let apiResponse = try decoder.decode(SerpAPIResponse.self, from: data)
                
                // Check if response has content
                guard apiResponse.hasContent else {
                    throw SerpAPIError.noResults
                }
                
                return apiResponse
                
            } catch let error as SerpAPIError {
                // Re-throw SerpAPI errors immediately (no retry for auth/rate limit errors)
                if case .invalidApiKey = error {
                    throw error
                } else if case .rateLimitExceeded = error {
                    throw error
                } else if case .missingApiKey = error {
                    throw error
                } else if case .noResults = error {
                    throw error
                }
                // For other SerpAPI errors, continue to retry logic below
                lastError = error
            } catch let error as DecodingError {
                // Decoding errors shouldn't be retried
                throw SerpAPIError.decodingError(error)
            } catch let error as URLError {
                // Network errors can be retried
                lastError = error
                if attempt < maxRetries {
                    // Exponential backoff: wait 0.5s, 1s
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw SerpAPIError.networkError(error)
                }
            } catch {
                // Other errors
                lastError = error
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw SerpAPIError.networkError(error)
                }
            }
        }
        
        // If we get here, all retries failed
        if let lastError = lastError {
            throw SerpAPIError.networkError(lastError)
        } else {
            throw SerpAPIError.networkError(NSError(domain: "SerpAPIClient", code: -1))
        }
    }
}


