//
//  SerpAPIClientTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for SerpAPIClient
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class SerpAPIClientTests: XCTestCase {
    
    func testSerpAPIClientInitialization() async {
        let client = SerpAPIClient(apiKey: "test-key")
        // Just verify it initializes without error
        XCTAssertNotNil(client)
    }
    
    func testSerpAPIClientInvalidQuery() async {
        let client = SerpAPIClient(apiKey: "test-key")
        
        do {
            _ = try await client.search(query: "")
            XCTFail("Should have thrown invalidQuery error")
        } catch SerpAPIError.invalidQuery {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSerpAPIClientMissingApiKey() async {
        let client = SerpAPIClient(apiKey: "")
        
        do {
            _ = try await client.search(query: "test")
            XCTFail("Should have thrown missingApiKey error")
        } catch SerpAPIError.missingApiKey {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // Note: Actual API calls are not tested here to avoid requiring a real API key
    // Integration tests with mocked responses would go in a separate file
}

