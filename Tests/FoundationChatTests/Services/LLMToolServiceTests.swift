//
//  LLMToolServiceTests.swift
//  FoundationChatTests
//
//  Integration tests for LLMToolService
//

import XCTest
@testable import FoundationChat

final class LLMToolServiceTests: XCTestCase {
    var toolService: LLMToolService!
    var registry: ToolRegistryService!
    var mockLogger: MockLogger!
    
    override func setUp() {
        super.setUp()
        mockLogger = MockLogger()
        registry = ToolRegistryService.shared
        toolService = LLMToolService(registry: registry, logger: mockLogger)
    }
    
    override func tearDown() {
        Task {
            await registry.clear()
        }
        super.tearDown()
    }
    
    // MARK: - Tool Registration Tests
    
    func testRegisterTool() async {
        let tool = MockTool(name: "test_tool")
        await toolService.registerTool(tool)
        
        let isAvailable = await toolService.isToolAvailable(name: "test_tool")
        XCTAssertTrue(isAvailable, "Tool should be available after registration")
    }
    
    func testGetAvailableTools() async {
        let tool1 = MockTool(name: "tool1")
        let tool2 = MockTool(name: "tool2")
        
        await toolService.registerTool(tool1)
        await toolService.registerTool(tool2)
        
        let availableTools = await toolService.getAvailableTools()
        XCTAssertEqual(availableTools.count, 2, "Should return two available tools")
        
        let toolNames = availableTools.compactMap { $0["name"] as? String }
        XCTAssertTrue(toolNames.contains("tool1"))
        XCTAssertTrue(toolNames.contains("tool2"))
    }
    
    func testGetToolDescriptor() async {
        let tool = MockTool(name: "test_tool", description: "Test description")
        await toolService.registerTool(tool)
        
        let descriptor = await toolService.getToolDescriptor(name: "test_tool")
        XCTAssertNotNil(descriptor, "Should return descriptor for registered tool")
        XCTAssertEqual(descriptor?.name, "test_tool")
        XCTAssertEqual(descriptor?.description, "Test description")
    }
    
    func testGetToolDescriptorForNonExistentTool() async {
        let descriptor = await toolService.getToolDescriptor(name: "nonexistent")
        XCTAssertNil(descriptor, "Should return nil for non-existent tool")
    }
    
    // MARK: - Tool Execution Tests
    
    func testExecuteToolCallSuccess() async {
        let tool = MockTool(name: "test_tool", shouldSucceed: true, result: "Success")
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "test_tool",
            parameters: [:]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertTrue(result.success, "Tool call should succeed")
        XCTAssertEqual(result.content, "Success")
        XCTAssertEqual(result.toolName, "test_tool")
        XCTAssertEqual(result.callId, request.callId)
    }
    
    func testExecuteToolCallFailure() async {
        let tool = MockTool(name: "test_tool", shouldSucceed: false)
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "test_tool",
            parameters: [:]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Tool call should fail")
        XCTAssertFalse(result.content.isEmpty, "Should contain error message")
        XCTAssertEqual(result.toolName, "test_tool")
    }
    
    func testExecuteToolCallNonExistentTool() async {
        let request = ToolCallRequest(
            toolName: "nonexistent",
            parameters: [:]
        )
        
        let result = await toolService.executeToolCall(request)
        
        XCTAssertFalse(result.success, "Should fail for non-existent tool")
        XCTAssertTrue(result.content.contains("not registered") || result.content.contains("disabled"))
    }
    
    func testExecuteToolCallLogsExecution() async {
        let tool = MockTool(name: "test_tool", shouldSucceed: true, result: "Result")
        await toolService.registerTool(tool)
        
        mockLogger.logs.removeAll()
        
        let request = ToolCallRequest(toolName: "test_tool", parameters: [:])
        _ = await toolService.executeToolCall(request)
        
        // Check that logging occurred
        XCTAssertFalse(mockLogger.logs.isEmpty, "Should have logged tool execution")
        let infoLogs = mockLogger.logs.filter { $0.level == .info }
        XCTAssertFalse(infoLogs.isEmpty, "Should have info level logs")
    }
    
    // MARK: - Tool Call Request/Result Tests
    
    func testToolCallRequestInitialization() {
        let request = ToolCallRequest(
            toolName: "test_tool",
            parameters: ["param1": "value1"]
        )
        
        XCTAssertEqual(request.toolName, "test_tool")
        XCTAssertEqual(request.parameters["param1"] as? String, "value1")
        XCTAssertFalse(request.callId.isEmpty, "Should generate call ID")
    }
    
    func testToolCallRequestWithCustomCallId() {
        let customId = "custom-call-id"
        let request = ToolCallRequest(
            toolName: "test_tool",
            parameters: [:],
            callId: customId
        )
        
        XCTAssertEqual(request.callId, customId)
    }
    
    func testToolCallResultInitialization() {
        let result = ToolCallResult(
            callId: "call-123",
            toolName: "test_tool",
            content: "Result content",
            success: true
        )
        
        XCTAssertEqual(result.callId, "call-123")
        XCTAssertEqual(result.toolName, "test_tool")
        XCTAssertEqual(result.content, "Result content")
        XCTAssertTrue(result.success)
    }
}









