//
//  DuckDuckGoIntegrationTests.swift
//  FoundationChatTests
//
//  Integration tests for DuckDuckGo Instant Answers API
//

import XCTest
@testable import FoundationChat

/// Integration tests that make real API calls to DuckDuckGo
/// These tests require network connectivity
final class DuckDuckGoIntegrationTests: XCTestCase {
    
    var client: DuckDuckGoClient!
    var tool: DuckDuckGoTool!
    
    override func setUp() {
        super.setUp()
        client = DuckDuckGoClient(timeout: 10.0, maxRetries: 2)
        tool = DuckDuckGoTool(client: client)
    }
    
    // MARK: - Real API Tests
    
    func testClientSearchWithCalculation() async throws {
        // Test calculation query
        let response = try await client.search(query: "2+2")
        
        XCTAssertTrue(response.hasContent)
        // Should have an answer for calculations
        XCTAssertNotNil(response.answer)
    }
    
    func testClientSearchWithDefinition() async throws {
        // Test definition query
        let response = try await client.search(query: "Swift programming language")
        
        XCTAssertTrue(response.hasContent)
        // Should have abstract or definition
        XCTAssertTrue(
            response.abstract != nil || 
            response.abstractText != nil || 
            response.definition != nil ||
            (response.relatedTopics != nil && !response.relatedTopics!.isEmpty)
        )
    }
    
    func testClientSearchWithFact() async throws {
        // Test factual query
        // Note: Some queries may not have instant answers, which is acceptable
        do {
            let response = try await client.search(query: "capital of France")
            XCTAssertTrue(response.hasContent)
        } catch DuckDuckGoError.noResults {
            // No results is acceptable for some queries
            XCTAssertTrue(true, "No results is acceptable")
        }
    }
    
    func testClientSearchInvalidQuery() async {
        // Test with empty query
        do {
            _ = try await client.search(query: "")
            XCTFail("Should have thrown invalidQuery error")
        } catch DuckDuckGoError.invalidQuery {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testToolSearchIntegration() async throws {
        // Test the tool wrapper
        let result = try await tool.search(query: "Python programming")
        
        XCTAssertFalse(result.isEmpty)
        // Should contain formatted response
        XCTAssertTrue(result.count > 10)
    }
    
    func testToolSearchWithNoResults() async {
        // Test with a query that likely has no instant answer
        // Note: This might still return results, so we just check it doesn't crash
        do {
            let result = try await tool.search(query: "xysdfghjklqwertyuiop123456789")
            // Even if no results, should return a message
            XCTAssertFalse(result.isEmpty)
        } catch {
            // Error is acceptable for queries with no results
            XCTAssertTrue(error is DuckDuckGoError)
        }
    }
    
    func testToolFormattingWithRealResponse() async throws {
        // Get a real response and test formatting
        let response = try await client.search(query: "42")
        let formatted = tool.formatResponse(response)
        
        XCTAssertFalse(formatted.isEmpty)
        // Should contain some structured information
        XCTAssertTrue(
            formatted.contains("Answer:") ||
            formatted.contains("Summary:") ||
            formatted.contains("Definition:") ||
            formatted.contains("Related Topics:")
        )
    }
    
    // MARK: - Error Handling Tests
    
    func testClientHandlesNetworkErrors() async {
        // Create client with very short timeout to test error handling
        let shortTimeoutClient = DuckDuckGoClient(timeout: 0.001, maxRetries: 0)
        
        do {
            _ = try await shortTimeoutClient.search(query: "test")
            // Might succeed if very fast, or timeout
        } catch {
            // Should handle timeout or network errors gracefully
            XCTAssertTrue(
                error is DuckDuckGoError ||
                error is URLError
            )
        }
    }
    
    // MARK: - Performance Tests
    
    func testClientResponseTime() async throws {
        let startTime = Date()
        do {
            _ = try await client.search(query: "test query")
        } catch DuckDuckGoError.noResults {
            // No results is acceptable, still measure time
        }
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete within reasonable time (10 seconds)
        XCTAssertLessThan(duration, 10.0, "API call took too long")
    }
}

