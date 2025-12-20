//
//  DuckDuckGoLLMIntegrationTests.swift
//  FoundationChatTests
//
//  End-to-end integration tests for DuckDuckGo tool with LLM system
//

import XCTest
@testable import FoundationChat

final class DuckDuckGoLLMIntegrationTests: XCTestCase {
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
    
    // MARK: - End-to-End Flow Tests
    
    func testCompleteToolFlow() async {
        // 1. Register DuckDuckGo tool
        let duckDuckGoTool = DuckDuckGoToolService()
        await toolService.registerTool(duckDuckGoTool)
        
        // 2. Verify tool is available
        let isAvailable = await toolService.isToolAvailable(name: "duckduckgo_search")
        XCTAssertTrue(isAvailable, "DuckDuckGo tool should be available")
        
        // 3. Get available tools for LLM
        let availableTools = await toolService.getAvailableTools()
        XCTAssertTrue(availableTools.contains { ($0["name"] as? String) == "duckduckgo_search" })
        
        // 4. Execute tool call (may fail if network unavailable)
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "Swift programming language"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        // 5. Verify result structure
        XCTAssertEqual(result.toolName, "duckduckgo_search")
        XCTAssertEqual(result.callId, request.callId)
        
        // Result may be success or failure depending on network
        if result.success {
            XCTAssertFalse(result.content.isEmpty, "Result should contain content")
        } else {
            XCTAssertFalse(result.content.isEmpty, "Error message should be present")
        }
    }
    
    func testToolRegistrationAndExecution() async {
        // Register tool
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Create tool call request
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "2+2"]
        )
        
        // Execute
        let result = await toolService.executeToolCall(request)
        
        // Verify
        XCTAssertEqual(result.toolName, "duckduckgo_search")
        XCTAssertEqual(result.callId, request.callId)
    }
    
    func testMultipleToolCalls() async {
        // Register tool
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Create multiple tool call requests
        let requests = [
            ToolCallRequest(toolName: "duckduckgo_search", parameters: ["query": "Python"]),
            ToolCallRequest(toolName: "duckduckgo_search", parameters: ["query": "JavaScript"]),
            ToolCallRequest(toolName: "duckduckgo_search", parameters: ["query": "Swift"])
        ]
        
        // Execute all
        var results: [ToolCallResult] = []
        for request in requests {
            let result = await toolService.executeToolCall(request)
            results.append(result)
        }
        
        // Verify all completed
        XCTAssertEqual(results.count, 3)
        for result in results {
            XCTAssertEqual(result.toolName, "duckduckgo_search")
        }
    }
    
    // MARK: - Query Type Tests
    
    func testCalculationQuery() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "10 * 5"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        if result.success {
            // Should contain answer for calculation
            XCTAssertFalse(result.content.isEmpty)
        }
    }
    
    func testDefinitionQuery() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "definition of algorithm"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        if result.success {
            XCTAssertFalse(result.content.isEmpty)
        }
    }
    
    func testFactualQuery() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "capital of France"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        if result.success {
            XCTAssertFalse(result.content.isEmpty)
        }
    }
    
    // MARK: - Error Scenario Tests
    
    func testInvalidQuery() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": ""]
        )
        
        let result = await toolService.executeToolCall(request)
        
        // Should fail with error
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.content.isEmpty, "Should contain error message")
    }
    
    func testNonExistentTool() async {
        let request = ToolCallRequest(
            toolName: "nonexistent_tool",
            parameters: ["query": "test"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail for non-existent tool")
        XCTAssertTrue(result.content.contains("not registered") || result.content.contains("disabled"))
    }
    
    // MARK: - Performance Tests
    
    func testToolCallPerformance() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "test"]
        )
        
        let startTime = Date()
        _ = await toolService.executeToolCall(request)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete within reasonable time (10 seconds)
        XCTAssertLessThan(duration, 10.0, "Tool call should complete within 10 seconds")
    }
    
    // MARK: - Integration with Registry Tests
    
    func testToolRegistryIntegration() async {
        // Register via tool service
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Verify in registry
        let isRegistered = await registry.isRegistered(name: "duckduckgo_search")
        XCTAssertTrue(isRegistered, "Tool should be registered in registry")
        
        // Get from registry
        let retrievedTool = await registry.getTool(name: "duckduckgo_search")
        XCTAssertNotNil(retrievedTool, "Should retrieve tool from registry")
    }
    
    func testToolDescriptorFormat() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let descriptors = await toolService.getAvailableTools()
        let duckDuckGoDescriptor = descriptors.first { ($0["name"] as? String) == "duckduckgo_search" }
        
        XCTAssertNotNil(duckDuckGoDescriptor, "Should have DuckDuckGo descriptor")
        XCTAssertNotNil(duckDuckGoDescriptor?["description"], "Should have description")
        XCTAssertNotNil(duckDuckGoDescriptor?["parameters"], "Should have parameters")
    }
}









