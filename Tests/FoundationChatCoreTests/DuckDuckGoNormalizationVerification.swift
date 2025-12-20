//
//  DuckDuckGoNormalizationVerification.swift
//  FoundationChatCoreTests
//
//  Verify that query normalization actually improves results
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class DuckDuckGoNormalizationVerification: XCTestCase {
    
    func testNormalizedVsOriginalQueries() async throws {
        let tool = DuckDuckGoFoundationTool()
        
        print("\n=== Normalized vs Original Query Comparison ===")
        
        let testCases = [
            ("what is 2+2?", "2+2"),
            ("What is the capital of France?", "capital of France"),
            ("search for Python", "Python")
        ]
        
        for (original, normalized) in testCases {
            print("\n--- Testing: '\(original)' ---")
            
            // Test original
            let originalArgs = DuckDuckGoFoundationTool.Arguments(query: original)
            let originalResult = try await tool.call(arguments: originalArgs)
            print("Original result length: \(originalResult.count)")
            print("Original preview: \(originalResult.prefix(100))")
            
            // Test normalized (by calling with normalized query directly)
            let normalizedArgs = DuckDuckGoFoundationTool.Arguments(query: normalized)
            let normalizedResult = try await tool.call(arguments: normalizedArgs)
            print("Normalized result length: \(normalizedResult.count)")
            print("Normalized preview: \(normalizedResult.prefix(100))")
            
            // Check if results are different
            if originalResult != normalizedResult {
                print("✓ Normalization changed the result")
            } else {
                print("⚠ Results are identical")
            }
        }
        
        print("\n================================================")
    }
}







