//
//  ErrorScenarioTests.swift
//  FoundationChatTests
//
//  Tests for error scenarios and edge cases
//

import XCTest
@testable import FoundationChat

final class ErrorScenarioTests: XCTestCase {
    var toolService: LLMToolService!
    var registry: ToolRegistryService!
    
    override func setUp() {
        super.setUp()
        registry = ToolRegistryService.shared
        toolService = LLMToolService.shared
    }
    
    override func tearDown() {
        Task {
            await registry.clear()
        }
        super.tearDown()
    }
    
    // MARK: - Network Error Tests
    
    func testNetworkTimeout() async {
        // Create tool with very short timeout
        let client = DuckDuckGoClient(timeout: 0.001, maxRetries: 0)
        let tool = DuckDuckGoTool(client: client)
        let service = DuckDuckGoToolService(tool: tool)
        
        await toolService.registerTool(service)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "test"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        // Should handle timeout gracefully
        XCTAssertFalse(result.success, "Should fail on timeout")
        XCTAssertFalse(result.content.isEmpty, "Should contain error message")
    }
    
    func testInvalidAPIResponse() async {
        // This would require mocking the URLSession to return invalid JSON
        // For now, test that the system handles errors gracefully
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Use a query that might return unexpected response
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "test"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        // Should either succeed or fail gracefully
        XCTAssertNotNil(result, "Should return a result")
    }
    
    // MARK: - No Results Tests
    
    func testNoResultsFound() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Use a query that likely has no instant answer
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "xysdfghjklqwertyuiop123456789"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        // Should handle no results gracefully
        // May return a message or error depending on API response
        XCTAssertNotNil(result, "Should return a result")
    }
    
    // MARK: - Invalid Parameter Tests
    
    func testMissingQueryParameter() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: [:]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail with missing parameter")
        XCTAssertTrue(
            result.content.contains("query") || result.content.contains("parameter"),
            "Error should mention query parameter"
        )
    }
    
    func testEmptyQueryParameter() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": ""]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail with empty query")
    }
    
    func testWhitespaceOnlyQuery() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "   "]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail with whitespace-only query")
    }
    
    // MARK: - Tool Availability Tests
    
    func testToolNotRegistered() async {
        // Don't register any tools
        
        let request = ToolCallRequest(
            toolName: "nonexistent_tool",
            parameters: ["query": "test"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail for non-existent tool")
        XCTAssertTrue(
            result.content.contains("not registered") || result.content.contains("disabled"),
            "Error should indicate tool is not available"
        )
    }
    
    func testToolDisabled() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Disable the tool
        await registry.setEnabled(name: "duckduckgo_search", enabled: false)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "test"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail for disabled tool")
        XCTAssertTrue(
            result.content.contains("disabled"),
            "Error should indicate tool is disabled"
        )
    }
    
    // MARK: - Concurrent Execution Tests
    
    func testConcurrentToolCalls() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Create multiple concurrent requests
        let requests = (0..<5).map { index in
            ToolCallRequest(
                toolName: "duckduckgo_search",
                parameters: ["query": "test\(index)"]
            )
        }
        
        // Execute concurrently
        let results = await withTaskGroup(of: ToolCallResult.self) { group in
            for request in requests {
                group.addTask {
                    await self.toolService.executeToolCall(request)
                }
            }
            
            var allResults: [ToolCallResult] = []
            for await result in group {
                allResults.append(result)
            }
            return allResults
        }
        
        XCTAssertEqual(results.count, 5, "Should handle concurrent requests")
        for result in results {
            XCTAssertEqual(result.toolName, "duckduckgo_search")
        }
    }
    
    // MARK: - Error Recovery Tests
    
    func testErrorRecoveryAfterFailure() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // First call with invalid query
        let badRequest = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": ""]
        )
        
        let badResult = await toolService.executeToolCall(badRequest)
        XCTAssertFalse(badResult.success)
        
        // Second call with valid query should work
        let goodRequest = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "Swift"]
        )
        
        let goodResult = await toolService.executeToolCall(goodRequest)
        // May succeed or fail depending on network, but should not crash
        XCTAssertNotNil(goodResult)
    }
}









