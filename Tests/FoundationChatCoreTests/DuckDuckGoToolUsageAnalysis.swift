//
//  DuckDuckGoToolUsageAnalysis.swift
//  FoundationChatCoreTests
//
//  Analysis tests to understand tool usage patterns
//

import XCTest
@testable import FoundationChatCore
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
final class DuckDuckGoToolUsageAnalysis: XCTestCase {
    
    func testQueriesWithInstantAnswers() async throws {
        // Test queries that DuckDuckGo Instant Answers handles well
        let tool = DuckDuckGoFoundationTool()
        
        let testQueries = [
            "2+2",                    // Calculation
            "Swift programming",      // Definition/topic
            "Python language",        // Definition/topic
            "capital of France",      // Factual (may not work)
            "current time",           // Real-time (may not work)
            "inflation UK 2024"       // Current data (may not work)
        ]
        
        print("\n=== Testing Queries for Instant Answers ===")
        var successCount = 0
        var noResultsCount = 0
        
        for query in testQueries {
            do {
                let args = DuckDuckGoFoundationTool.Arguments(query: query)
                let result = try await tool.call(arguments: args)
                
                if result.contains("Error:") || result.contains("No instant answer") {
                    print("❌ '\(query)': No instant answer")
                    noResultsCount += 1
                } else {
                    print("✓ '\(query)': Has instant answer (length: \(result.count))")
                    print("  Preview: \(result.prefix(80))")
                    successCount += 1
                }
            } catch {
                print("❌ '\(query)': Error - \(error)")
                noResultsCount += 1
            }
        }
        
        print("\nSummary: \(successCount) with answers, \(noResultsCount) without")
        print("===========================================")
        
        // This helps us understand which query types work
        XCTAssertTrue(successCount > 0, "At least some queries should have instant answers")
    }
    
    func testModelToolUsagePatterns() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        print("\n=== Testing Model Tool Usage Patterns ===")
        
        let testCases = [
            ("Explicit request", "Use duckduckgo_search to find: what is 2+2?"),
            ("Calculation query", "What is 10 * 5? Search online for the answer."),
            ("Definition query", "Look up information about Swift programming language"),
            ("Current info query", "Search for current inflation rate in UK"),
            ("Simple question", "What is the capital of France?")
        ]
        
        for (testType, query) in testCases {
            print("\n--- \(testType) ---")
            print("Query: \(query)")
            
            let response = try await modelService.respond(to: query)
            
            // Check if tool was mentioned (indicates it was used)
            let contentLower = response.content.lowercased()
            let toolMentioned = contentLower.contains("duckduckgo") || 
                               contentLower.contains("search") ||
                               contentLower.contains("couldn't find") ||
                               contentLower.contains("no results")
            
            print("Response: \(response.content.prefix(200))")
            print("Tool mentioned: \(toolMentioned ? "YES" : "NO")")
            print("Tool calls extracted: \(response.toolCalls.count)")
            
            if toolMentioned {
                print("✓ Tool appears to have been used")
            } else {
                print("⚠ Tool may not have been used")
            }
        }
        
        print("\n=========================================")
    }
    
    func testToolDescriptionEffectiveness() async throws {
        // Test if different tool descriptions affect usage
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        print("\n=== Testing Tool Description Effectiveness ===")
        
        let tool = DuckDuckGoFoundationTool()
        print("Current tool description:")
        print("  \(tool.description)")
        print("  Length: \(tool.description.count) characters")
        
        await modelService.updateTools([tool])
        
        // Test with same query multiple times to see consistency
        let query = "Search DuckDuckGo for: what is 2+2?"
        print("\nTesting with query: \(query)")
        
        var toolUsedCount = 0
        let iterations = 3
        
        for i in 1...iterations {
            let response = try await modelService.respond(to: query)
            let contentLower = response.content.lowercased()
            let toolUsed = contentLower.contains("duckduckgo") || 
                          contentLower.contains("search") ||
                          contentLower.contains("couldn't find")
            
            if toolUsed {
                toolUsedCount += 1
            }
            
            print("  Attempt \(i): Tool used: \(toolUsed ? "YES" : "NO")")
        }
        
        print("\nTool used in \(toolUsedCount)/\(iterations) attempts")
        print("================================================")
    }
}








