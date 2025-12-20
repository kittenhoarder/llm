//
//  DuckDuckGoClient.swift
//  FoundationChatCore
//
//  Swift-native HTTP client for DuckDuckGo Instant Answers API
//

import Foundation

/// Client for interacting with DuckDuckGo Instant Answers API
public actor DuckDuckGoClient {
    /// Base URL for DuckDuckGo Instant Answers API
    private let baseURL = "https://api.duckduckgo.com/"
    
    /// URLSession for making HTTP requests
    private let session: URLSession
    
    /// Request timeout in seconds
    private let timeout: TimeInterval
    
    /// Maximum number of retry attempts
    private let maxRetries: Int
    
    /// Initializes a new DuckDuckGo client
    /// - Parameters:
    ///   - session: URLSession to use for requests (defaults to shared session)
    ///   - timeout: Request timeout in seconds (defaults to 10 seconds)
    ///   - maxRetries: Maximum number of retry attempts (defaults to 2)
    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 10.0,
        maxRetries: Int = 2
    ) {
        self.session = session
        self.timeout = timeout
        self.maxRetries = maxRetries
    }
    
    /// Searches DuckDuckGo Instant Answers API for a query
    /// - Parameter query: The search query
    /// - Returns: DuckDuckGoResponse containing the answer or related information
    /// - Throws: DuckDuckGoError if the request fails or no results are found
    public func search(query: String) async throws -> DuckDuckGoResponse {
        // Validate query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw DuckDuckGoError.invalidQuery(query)
        }
        
        // Build URL with query parameters
        guard var urlComponents = URLComponents(string: baseURL) else {
            throw DuckDuckGoError.invalidResponse
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        
        guard let url = urlComponents.url else {
            throw DuckDuckGoError.invalidResponse
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
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw DuckDuckGoError.httpError(statusCode: httpResponse.statusCode)
                    }
                }
                
                // Decode JSON response
                let decoder = JSONDecoder()
                let apiResponse = try decoder.decode(DuckDuckGoResponse.self, from: data)
                
                // Check if response has content
                guard apiResponse.hasContent else {
                    throw DuckDuckGoError.noResults
                }
                
                return apiResponse
                
            } catch let error as DuckDuckGoError {
                // Re-throw DuckDuckGo errors immediately (no retry)
                throw error
            } catch let error as DecodingError {
                // Decoding errors shouldn't be retried
                throw DuckDuckGoError.decodingError(error)
            } catch let error as URLError {
                // Network errors can be retried
                lastError = error
                if attempt < maxRetries {
                    // Exponential backoff: wait 0.5s, 1s, 2s
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw DuckDuckGoError.networkError(error)
                }
            } catch {
                // Other errors
                lastError = error
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt)) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                } else {
                    throw DuckDuckGoError.networkError(error)
                }
            }
        }
        
        // If we get here, all retries failed
        if let lastError = lastError {
            throw DuckDuckGoError.networkError(lastError)
        } else {
            throw DuckDuckGoError.networkError(NSError(domain: "DuckDuckGoClient", code: -1))
        }
    }
}


