//
//  ToolRegistryServiceTests.swift
//  FoundationChatTests
//
//  Unit tests for ToolRegistryService
//

import XCTest
@testable import FoundationChat

// Mock tool for testing
struct MockTool: LLMTool {
    let name: String
    let description: String
    let parameters: [String: Any]
    let shouldSucceed: Bool
    let result: String
    let error: Error?
    
    init(
        name: String = "mock_tool",
        description: String = "A mock tool for testing",
        parameters: [String: Any] = ["type": "object", "properties": [:], "required": []],
        shouldSucceed: Bool = true,
        result: String = "Mock result",
        error: Error? = nil
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.shouldSucceed = shouldSucceed
        self.result = result
        self.error = error
    }
    
    func execute(parameters: [String: Any]) async throws -> String {
        if shouldSucceed {
            return result
        } else {
            throw error ?? NSError(domain: "MockTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
        }
    }
}

final class ToolRegistryServiceTests: XCTestCase {
    var registry: ToolRegistryService!
    
    override func setUp() {
        super.setUp()
        registry = ToolRegistryService.shared
    }
    
    override func tearDown() {
        Task {
            await registry.clear()
        }
        super.tearDown()
    }
    
    // MARK: - Registration Tests
    
    func testRegisterTool() async {
        let tool = MockTool()
        await registry.register(tool)
        
        let isRegistered = await registry.isRegistered(name: tool.name)
        XCTAssertTrue(isRegistered, "Tool should be registered")
        
        let toolCount = await registry.toolCount()
        XCTAssertEqual(toolCount, 1, "Should have one registered tool")
    }
    
    func testUnregisterTool() async {
        let tool = MockTool()
        await registry.register(tool)
        
        await registry.unregister(name: tool.name)
        
        let isRegistered = await registry.isRegistered(name: tool.name)
        XCTAssertFalse(isRegistered, "Tool should not be registered after unregistering")
    }
    
    func testRegisterMultipleTools() async {
        let tool1 = MockTool(name: "tool1")
        let tool2 = MockTool(name: "tool2")
        
        await registry.register(tool1)
        await registry.register(tool2)
        
        let toolCount = await registry.toolCount()
        XCTAssertEqual(toolCount, 2, "Should have two registered tools")
    }
    
    func testGetTool() async {
        let tool = MockTool(name: "test_tool")
        await registry.register(tool)
        
        let retrievedTool = await registry.getTool(name: "test_tool")
        XCTAssertNotNil(retrievedTool, "Should retrieve registered tool")
        XCTAssertEqual(retrievedTool?.name, "test_tool")
    }
    
    func testGetNonExistentTool() async {
        let tool = await registry.getTool(name: "nonexistent")
        XCTAssertNil(tool, "Should return nil for non-existent tool")
    }
    
    // MARK: - Descriptor Tests
    
    func testGetAllDescriptors() async {
        let tool = MockTool(name: "test_tool")
        await registry.register(tool)
        
        let descriptors = await registry.getAllDescriptors()
        XCTAssertEqual(descriptors.count, 1, "Should return one descriptor")
        XCTAssertEqual(descriptors.first?.name, "test_tool")
    }
    
    func testGetFunctionCallDescriptors() async {
        let tool = MockTool(
            name: "test_tool",
            description: "Test description",
            parameters: ["type": "object", "properties": [:], "required": []]
        )
        await registry.register(tool)
        
        let descriptors = await registry.getFunctionCallDescriptors()
        XCTAssertEqual(descriptors.count, 1, "Should return one descriptor")
        
        let descriptor = descriptors.first!
        XCTAssertEqual(descriptor["name"] as? String, "test_tool")
        XCTAssertEqual(descriptor["description"] as? String, "Test description")
    }
    
    // MARK: - Execution Tests
    
    func testExecuteToolSuccess() async {
        let tool = MockTool(shouldSucceed: true, result: "Success result")
        await registry.register(tool)
        
        let result = await registry.executeTool(name: tool.name, parameters: [:])
        
        XCTAssertTrue(result.success, "Tool execution should succeed")
        XCTAssertEqual(result.result, "Success result")
        XCTAssertEqual(result.toolName, tool.name)
        XCTAssertNil(result.error)
        XCTAssertGreaterThan(result.executionTime, 0)
    }
    
    func testExecuteToolFailure() async {
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let tool = MockTool(shouldSucceed: false, error: error)
        await registry.register(tool)
        
        let result = await registry.executeTool(name: tool.name, parameters: [:])
        
        XCTAssertFalse(result.success, "Tool execution should fail")
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.toolName, tool.name)
    }
    
    func testExecuteNonExistentTool() async {
        let result = await registry.executeTool(name: "nonexistent", parameters: [:])
        
        XCTAssertFalse(result.success, "Execution should fail for non-existent tool")
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error?.contains("not registered") ?? false)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testSetToolEnabled() async {
        let tool = MockTool(name: "test_tool")
        await registry.register(tool)
        
        await registry.setEnabled(name: "test_tool", enabled: false)
        
        let result = await registry.executeTool(name: "test_tool", parameters: [:])
        XCTAssertFalse(result.success, "Disabled tool should not execute")
        XCTAssertTrue(result.error?.contains("disabled") ?? false)
    }
    
    func testSetToolDisabledThenEnabled() async {
        let tool = MockTool(name: "test_tool", shouldSucceed: true, result: "Result")
        await registry.register(tool)
        
        await registry.setEnabled(name: "test_tool", enabled: false)
        var result = await registry.executeTool(name: "test_tool", parameters: [:])
        XCTAssertFalse(result.success)
        
        await registry.setEnabled(name: "test_tool", enabled: true)
        result = await registry.executeTool(name: "test_tool", parameters: [:])
        XCTAssertTrue(result.success, "Re-enabled tool should execute")
    }
    
    // MARK: - Clear Tests
    
    func testClearRegistry() async {
        let tool1 = MockTool(name: "tool1")
        let tool2 = MockTool(name: "tool2")
        
        await registry.register(tool1)
        await registry.register(tool2)
        
        await registry.clear()
        
        let toolCount = await registry.toolCount()
        XCTAssertEqual(toolCount, 0, "Registry should be empty after clear")
    }
}










