//
//  DuckDuckGoToolIntegrationTests.swift
//  FoundationChatCoreTests
//
//  Comprehensive integration tests to diagnose DuckDuckGo tool issues
//

import XCTest
@testable import FoundationChatCore
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
final class DuckDuckGoToolIntegrationTests: XCTestCase {
    
    // MARK: - Phase 1: Direct API Tests
    
    func testDuckDuckGoClientDirectAPI() async throws {
        let client = DuckDuckGoClient()
        
        // Test with a calculation query (known to work with DuckDuckGo)
        let response = try await client.search(query: "2+2")
        
        XCTAssertTrue(response.hasContent, "Response should have content")
        print("✓ API Response received")
        print("  Answer: \(response.answer ?? "nil")")
        print("  Abstract: \(response.abstract?.prefix(50) ?? "nil")")
    }
    
    func testDuckDuckGoClientWithDefinition() async throws {
        let client = DuckDuckGoClient()
        
        // Test with a definition query
        let response = try await client.search(query: "Swift programming language")
        
        XCTAssertTrue(response.hasContent, "Response should have content")
        print("✓ Definition query successful")
        print("  Has abstract: \(response.abstract != nil)")
        print("  Has definition: \(response.definition != nil)")
    }
    
    func testDuckDuckGoClientErrorHandling() async {
        let client = DuckDuckGoClient()
        
        // Test with empty query
        do {
            _ = try await client.search(query: "")
            XCTFail("Should have thrown invalidQuery error")
        } catch DuckDuckGoError.invalidQuery {
            print("✓ Empty query correctly rejected")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Phase 2: Tool Wrapper Tests
    
    func testDuckDuckGoToolSearch() async throws {
        let tool = DuckDuckGoTool()
        
        let result = try await tool.search(query: "2+2")
        
        XCTAssertFalse(result.isEmpty, "Result should not be empty")
        print("✓ Tool wrapper successful")
        print("  Result length: \(result.count) characters")
        print("  Result preview: \(result.prefix(100))")
    }
    
    func testDuckDuckGoToolFormatting() async throws {
        let tool = DuckDuckGoTool()
        
        let result = try await tool.search(query: "Python programming")
        
        XCTAssertFalse(result.isEmpty)
        // Should be formatted for LLM consumption
        XCTAssertTrue(result.contains("Answer:") || result.contains("Summary:") || result.contains("Definition:"), 
                     "Result should be formatted")
        print("✓ Formatting verified")
        print("  Formatted result: \(result.prefix(200))")
    }
    
    // MARK: - Phase 3: Foundation Tool Adapter Tests
    
    func testDuckDuckGoFoundationToolCall() async throws {
        let tool = DuckDuckGoFoundationTool()
        
        let arguments = DuckDuckGoFoundationTool.Arguments(query: "Swift language")
        let result = try await tool.call(arguments: arguments)
        
        XCTAssertFalse(result.isEmpty, "Tool call should return result")
        print("✓ Foundation tool adapter successful")
        print("  Tool name: \(tool.name)")
        print("  Tool description: \(tool.description.prefix(100))...")
        print("  Call result: \(result.prefix(150))")
    }
    
    func testDuckDuckGoFoundationToolProtocolConformance() {
        let tool = DuckDuckGoFoundationTool()
        
        XCTAssertEqual(tool.name, "duckduckgo_search")
        XCTAssertFalse(tool.description.isEmpty)
        print("✓ Tool protocol conformance verified")
        print("  Name: \(tool.name)")
        print("  Description length: \(tool.description.count)")
    }
    
    func testDuckDuckGoFoundationToolErrorHandling() async {
        let tool = DuckDuckGoFoundationTool()
        
        // Test with empty query - should return error message, not throw
        let arguments = DuckDuckGoFoundationTool.Arguments(query: "")
        let result = try? await tool.call(arguments: arguments)
        
        // Tool should handle errors gracefully and return error message
        XCTAssertNotNil(result, "Tool should return error message, not throw")
        if let result = result {
            XCTAssertTrue(result.contains("Error:") || result.contains("Invalid"), 
                         "Should contain error indication")
            print("✓ Error handling verified: \(result.prefix(100))")
        }
    }
    
    // MARK: - Phase 4: ModelService Integration Tests
    
    func testModelServiceWithToolRegistration() async throws {
        // Skip if model not available
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            print("⚠ Model not available, skipping test")
            throw XCTSkip("Model not available: \(ModelService.errorMessage(for: availability))")
        }
        
        // Register tool
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        print("✓ Tool registered with ModelService")
        
        // Test with a simple query that should trigger tool
        let response = try await modelService.respond(to: "Use duckduckgo_search to find: what is 2+2?")
        
        XCTAssertFalse(response.content.isEmpty)
        print("✓ ModelService response received")
        print("  Response length: \(response.content.count)")
        print("  Tool calls count: \(response.toolCalls.count)")
        print("  Response preview: \(response.content.prefix(200))")
        
        // Verify tool tracking structure
        XCTAssertNotNil(response.toolCalls, "Tool calls array should exist")
        
        // If tools were tracked, verify they're correct
        if !response.toolCalls.isEmpty {
            let toolNames = response.toolCalls.map { $0.toolName }
            print("  Tools tracked: \(toolNames.joined(separator: ", "))")
            XCTAssertTrue(toolNames.contains("duckduckgo_search"), 
                         "If tools were used, duckduckgo_search should be tracked")
            
            // Verify friendly name mapping works
            let friendlyNames = ToolNameMapper.friendlyNames(for: toolNames)
            print("  Friendly names: \(friendlyNames.joined(separator: ", "))")
        }
        
        // Check if tool was actually used (content should mention the answer or calculation)
        if response.content.contains("4") || response.content.contains("four") {
            print("✓ Tool likely used (response contains expected answer)")
        } else {
            print("⚠ Tool may not have been used (response doesn't contain expected answer)")
            print("  Full response: \(response.content)")
        }
    }
    
    func testModelServiceToolDescription() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        // Test with explicit search request
        let explicitQuery = "Please use the duckduckgo_search tool to search for: current time in London"
        let response = try await modelService.respond(to: explicitQuery)
        
        print("✓ Explicit tool request test")
        print("  Query: \(explicitQuery)")
        print("  Response: \(response.content.prefix(300))")
        print("  Tool calls: \(response.toolCalls.count)")
        
        // Verify tool tracking
        XCTAssertNotNil(response.toolCalls)
        if !response.toolCalls.isEmpty {
            let toolNames = response.toolCalls.map { $0.toolName }
            print("  Tools tracked: \(toolNames.joined(separator: ", "))")
            print("  Formatted: \(ToolNameMapper.formatToolList(toolNames))")
        }
    }
    
    func testModelServiceWithoutTools() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        // Don't register tools
        let response = try await modelService.respond(to: "What is 2+2?")
        
        XCTAssertFalse(response.content.isEmpty)
        print("✓ Model works without tools")
        print("  Response: \(response.content.prefix(100))")
    }
    
    // MARK: - Phase 5: Diagnostic Tests
    
    func testToolDescriptionContent() {
        let tool = DuckDuckGoFoundationTool()
        
        let description = tool.description
        print("\n=== Tool Description ===")
        print(description)
        print("========================")
        
        // Check for key phrases that should encourage tool usage
        let keyPhrases = ["search", "look up", "find", "current", "real-time"]
        let foundPhrases = keyPhrases.filter { description.lowercased().contains($0) }
        
        print("✓ Key phrases found: \(foundPhrases)")
        XCTAssertFalse(foundPhrases.isEmpty, "Description should contain encouraging phrases")
    }
    
    func testQueryNormalization() async throws {
        // Test that query normalization improves success rate
        let tool = DuckDuckGoFoundationTool()
        
        let testCases = [
            ("what is 2+2?", "2+2"),
            ("search for Python language", "Python language"),
            ("look up Swift programming", "Swift programming"),
            ("What is the capital of France?", "capital of France"),
            ("10 * 5", "10 * 5"),
            ("use duckduckgo to find: inflation UK", "inflation UK")
        ]
        
        print("\n=== Query Normalization Test ===")
        for (original, _) in testCases {
            let args = DuckDuckGoFoundationTool.Arguments(query: original)
            
            // The normalization happens inside call(), so we test the end result
            do {
                let result = try await tool.call(arguments: args)
                if result.contains("Error:") || result.contains("No instant answer") {
                    print("❌ '\(original)' → No instant answer")
                } else {
                    print("✓ '\(original)' → Has result (length: \(result.count))")
                }
            } catch {
                print("❌ '\(original)' → Error: \(error)")
            }
        }
        print("================================")
    }
    
    func testLanguageModelSessionToolIntegration() async throws {
        // This test directly uses LanguageModelSession to see if tools work
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        let tool = DuckDuckGoFoundationTool()
        let session = LanguageModelSession(tools: [tool])
        
        print("✓ LanguageModelSession created with tool")
        print("  Tool name: \(tool.name)")
        
        // Try a query that should definitely trigger search
        let query = "Search DuckDuckGo for: what is the capital of France?"
        print("  Query: \(query)")
        
        let response = try await session.respond(to: query)
        
        print("✓ Session response received")
        print("  Content length: \(response.content.count)")
        print("  Content preview: \(response.content.prefix(300))")
        
        // Check if Paris or France is mentioned (indicates tool was used)
        let contentLower = response.content.lowercased()
        if contentLower.contains("paris") || contentLower.contains("france") {
            print("✓ Tool likely used (response contains expected information)")
        } else {
            print("⚠ Tool may not have been used")
            print("  Full response: \(response.content)")
        }
    }
    
    // MARK: - Diagnostic Tests
    
    func testDirectToolCallWithKnownGoodQuery() async throws {
        // Test the tool directly with a query that should definitely work
        let tool = DuckDuckGoFoundationTool()
        
        // Test with calculation (DuckDuckGo handles these well)
        let calcArgs = DuckDuckGoFoundationTool.Arguments(query: "2+2")
        let calcResult = try await tool.call(arguments: calcArgs)
        
        print("\n=== Direct Tool Call Test ===")
        print("Query: 2+2")
        print("Result: \(calcResult)")
        print("=============================")
        
        XCTAssertFalse(calcResult.isEmpty)
        // Should contain answer or calculation result
        XCTAssertTrue(calcResult.contains("4") || calcResult.contains("Answer:") || calcResult.contains("Topic:"),
                     "Result should contain answer or formatted content")
    }
    
    func testToolWithDefinitionQuery() async throws {
        let tool = DuckDuckGoFoundationTool()
        
        // Test with definition query
        let defArgs = DuckDuckGoFoundationTool.Arguments(query: "Swift programming language")
        let defResult = try await tool.call(arguments: defArgs)
        
        print("\n=== Definition Query Test ===")
        print("Query: Swift programming language")
        print("Result length: \(defResult.count)")
        print("Result preview: \(defResult.prefix(200))")
        print("==============================")
        
        XCTAssertFalse(defResult.isEmpty)
        XCTAssertTrue(defResult.count > 50, "Definition query should return substantial content")
    }
    
    func testModelServiceWithCalculationQuery() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        // Test with a simple calculation that DuckDuckGo handles well
        let query = "What is 5 times 3? Use duckduckgo_search to find the answer."
        print("\n=== ModelService Calculation Test ===")
        print("Query: \(query)")
        
        let response = try await modelService.respond(to: query)
        
        print("Response: \(response.content)")
        print("Tool calls: \(response.toolCalls.count)")
        print("=====================================")
        
        // Check if response contains the answer (15)
        let contentLower = response.content.lowercased()
        if contentLower.contains("15") || contentLower.contains("fifteen") {
            print("✓ Tool likely used successfully")
        } else {
            print("⚠ Tool may not have returned expected result")
        }
    }
    
    func testToolCallFlowDiagnostics() async throws {
        // Comprehensive diagnostic test using queries that DuckDuckGo handles well
        print("\n=== Tool Call Flow Diagnostics ===")
        
        // Use a calculation query (DuckDuckGo handles these reliably)
        let testQuery = "10*5"
        
        // 1. Test direct API
        let client = DuckDuckGoClient()
        do {
            let apiResponse = try await client.search(query: testQuery)
            print("1. Direct API: SUCCESS")
            print("   Has content: \(apiResponse.hasContent)")
            print("   Answer: \(apiResponse.answer ?? "nil")")
            print("   Abstract: \(apiResponse.abstract?.prefix(50) ?? "nil")")
        } catch DuckDuckGoError.noResults {
            print("1. Direct API: NO RESULTS (query may not have instant answer)")
        } catch {
            print("1. Direct API: ERROR - \(error)")
        }
        
        // 2. Test tool wrapper
        let toolWrapper = DuckDuckGoTool()
        do {
            let toolResult = try await toolWrapper.search(query: testQuery)
            print("2. Tool Wrapper: SUCCESS (length: \(toolResult.count))")
            print("   Preview: \(toolResult.prefix(150))")
        } catch {
            print("2. Tool Wrapper: ERROR - \(error)")
        }
        
        // 3. Test Foundation tool
        let foundationTool = DuckDuckGoFoundationTool()
        let foundationArgs = DuckDuckGoFoundationTool.Arguments(query: testQuery)
        let foundationResult = try await foundationTool.call(arguments: foundationArgs)
        print("3. Foundation Tool: SUCCESS (length: \(foundationResult.count))")
        print("   Preview: \(foundationResult.prefix(150))")
        
        // 4. Test with model (if available)
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        if case .available = availability {
            await modelService.updateTools([foundationTool])
            let modelQuery = "What is 10 times 5? Use duckduckgo_search to calculate."
            print("4. Testing Model Integration...")
            print("   Query: \(modelQuery)")
            let modelResponse = try await modelService.respond(to: modelQuery)
            print("   Model Response: \(modelResponse.content.prefix(300))")
            print("   Tool calls extracted: \(modelResponse.toolCalls.count)")
            
            // Check if answer is in response
            let contentLower = modelResponse.content.lowercased()
            if contentLower.contains("50") || contentLower.contains("fifty") {
                print("   ✓ Response contains expected answer (50)")
            } else {
                print("   ⚠ Response may not contain expected answer")
            }
        } else {
            print("4. Model Integration: SKIPPED (model not available)")
        }
        
        print("===================================")
    }
}

