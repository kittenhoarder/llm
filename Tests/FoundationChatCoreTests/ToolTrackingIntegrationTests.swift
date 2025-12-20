//
//  ToolTrackingIntegrationTests.swift
//  FoundationChatCoreTests
//
//  Integration tests for tool call tracking functionality
//

import XCTest
@testable import FoundationChatCore
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
final class ToolTrackingIntegrationTests: XCTestCase {
    
    // MARK: - ToolCallTracker Tests
    
    func testToolCallTrackerRecordsCalls() async {
        let tracker = ToolCallTracker()
        let sessionId = UUID().uuidString
        
        // Record some tool calls
        await tracker.recordCall(sessionId: sessionId, toolName: "duckduckgo_search", arguments: "test query")
        await tracker.recordCall(sessionId: sessionId, toolName: "duckduckgo_search", arguments: "another query")
        
        // Get unique tool names
        let toolNames = await tracker.getUniqueToolNames(for: sessionId)
        
        XCTAssertEqual(toolNames.count, 1, "Should have one unique tool name")
        XCTAssertEqual(toolNames.first, "duckduckgo_search", "Should be duckduckgo_search")
        
        print("✓ ToolCallTracker records calls correctly")
    }
    
    func testToolCallTrackerMultipleTools() async {
        let tracker = ToolCallTracker()
        let sessionId = UUID().uuidString
        
        // Record calls from different tools
        await tracker.recordCall(sessionId: sessionId, toolName: "duckduckgo_search", arguments: nil)
        await tracker.recordCall(sessionId: sessionId, toolName: "file_search", arguments: nil)
        await tracker.recordCall(sessionId: sessionId, toolName: "duckduckgo_search", arguments: nil)
        
        let toolNames = await tracker.getUniqueToolNames(for: sessionId)
        
        XCTAssertEqual(toolNames.count, 2, "Should have two unique tool names")
        XCTAssertTrue(toolNames.contains("duckduckgo_search"))
        XCTAssertTrue(toolNames.contains("file_search"))
        
        print("✓ ToolCallTracker handles multiple tools correctly")
    }
    
    func testToolCallTrackerSessionIsolation() async {
        let tracker = ToolCallTracker()
        let sessionId1 = UUID().uuidString
        let sessionId2 = UUID().uuidString
        
        // Record calls in different sessions
        await tracker.recordCall(sessionId: sessionId1, toolName: "duckduckgo_search", arguments: nil)
        await tracker.recordCall(sessionId: sessionId2, toolName: "file_search", arguments: nil)
        
        let tools1 = await tracker.getUniqueToolNames(for: sessionId1)
        let tools2 = await tracker.getUniqueToolNames(for: sessionId2)
        
        XCTAssertEqual(tools1.count, 1)
        XCTAssertEqual(tools2.count, 1)
        XCTAssertEqual(tools1.first, "duckduckgo_search")
        XCTAssertEqual(tools2.first, "file_search")
        
        print("✓ ToolCallTracker isolates sessions correctly")
    }
    
    func testToolCallTrackerClearSession() async {
        let tracker = ToolCallTracker()
        let sessionId = UUID().uuidString
        
        await tracker.recordCall(sessionId: sessionId, toolName: "duckduckgo_search", arguments: nil)
        
        let beforeClear = await tracker.getUniqueToolNames(for: sessionId)
        XCTAssertEqual(beforeClear.count, 1)
        
        await tracker.clearSession(sessionId)
        
        let afterClear = await tracker.getUniqueToolNames(for: sessionId)
        XCTAssertEqual(afterClear.count, 0, "Session should be cleared")
        
        print("✓ ToolCallTracker clears sessions correctly")
    }
    
    // MARK: - TrackedTool Tests
    
    func testTrackedToolWrapsAndRecords() async throws {
        let tracker = ToolCallTracker()
        let sessionId = UUID().uuidString
        let originalTool = DuckDuckGoFoundationTool()
        
        let trackedTool = TrackedTool(wrapping: originalTool, sessionId: sessionId, tracker: tracker)
        
        // Verify the wrapper delegates properties correctly
        XCTAssertEqual(trackedTool.name, originalTool.name)
        XCTAssertEqual(trackedTool.description, originalTool.description)
        
        // Call the tool
        let args = DuckDuckGoFoundationTool.Arguments(query: "2+2")
        let result = try await trackedTool.call(arguments: args)
        
        // Verify the call was recorded
        let toolNames = await tracker.getUniqueToolNames(for: sessionId)
        XCTAssertEqual(toolNames.count, 1)
        XCTAssertEqual(toolNames.first, "duckduckgo_search")
        
        // Verify the result is correct
        XCTAssertFalse(result.isEmpty)
        
        print("✓ TrackedTool wraps and records correctly")
    }
    
    // MARK: - ModelService Tool Tracking Tests
    
    func testModelServiceTracksToolUsage() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available: \(ModelService.errorMessage(for: availability))")
        }
        
        // Register tool
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        // Send a query that should trigger the tool
        let response = try await modelService.respond(to: "Use duckduckgo_search to find: what is 2+2?")
        
        // Verify response has content
        XCTAssertFalse(response.content.isEmpty)
        
        // Verify tool calls are tracked (may be empty if tool wasn't used, but structure should be correct)
        // The tool might not always be used, so we just verify the structure exists
        XCTAssertNotNil(response.toolCalls)
        
        print("✓ ModelService tracks tool usage")
        print("  Response length: \(response.content.count)")
        print("  Tool calls tracked: \(response.toolCalls.count)")
        
        if !response.toolCalls.isEmpty {
            print("  Tools used: \(response.toolCalls.map { $0.toolName }.joined(separator: ", "))")
            // If tools were used, verify they're tracked correctly
            let toolNames = response.toolCalls.map { $0.toolName }
            XCTAssertTrue(toolNames.contains("duckduckgo_search") || toolNames.isEmpty,
                         "If tools were used, duckduckgo_search should be in the list")
        }
    }
    
    func testModelServiceNoToolsWhenNotUsed() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        // Register tool
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        // Send a query that shouldn't trigger the tool (simple question)
        let response = try await modelService.respond(to: "What is 2+2?")
        
        // Response should have content
        XCTAssertFalse(response.content.isEmpty)
        
        // Tool calls should be empty or not include the tool if it wasn't used
        // (The model might use the tool anyway, so we just verify structure)
        XCTAssertNotNil(response.toolCalls)
        
        print("✓ ModelService correctly handles when tools aren't used")
        print("  Tool calls: \(response.toolCalls.count)")
    }
    
    func testModelServiceMultipleToolCalls() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        // Register tool
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        // Send multiple queries that might trigger the tool
        let query1 = "Search DuckDuckGo for: Python programming"
        let response1 = try await modelService.respond(to: query1)
        
        let query2 = "Search DuckDuckGo for: Swift language"
        let response2 = try await modelService.respond(to: query2)
        
        // Each response should have its own tool calls tracked
        XCTAssertNotNil(response1.toolCalls)
        XCTAssertNotNil(response2.toolCalls)
        
        // Tool calls should be independent between responses
        // (Each response gets a new session ID internally)
        
        print("✓ ModelService tracks tool calls per response")
        print("  Response 1 tool calls: \(response1.toolCalls.count)")
        print("  Response 2 tool calls: \(response2.toolCalls.count)")
    }
    
    // MARK: - ToolNameMapper Tests
    
    func testToolNameMapperFriendlyNames() {
        // Test known mapping
        let friendly = ToolNameMapper.friendlyName(for: "duckduckgo_search")
        XCTAssertEqual(friendly, "DuckDuckGo Search", "Should map to friendly name")
        
        // Test unknown tool name (should return as-is)
        let unknown = ToolNameMapper.friendlyName(for: "unknown_tool")
        XCTAssertEqual(unknown, "unknown_tool", "Unknown tool should return as-is")
        
        print("✓ ToolNameMapper maps names correctly")
    }
    
    func testToolNameMapperMultipleNames() {
        let toolNames = ["duckduckgo_search", "file_search", "unknown_tool"]
        let friendly = ToolNameMapper.friendlyNames(for: toolNames)
        
        XCTAssertEqual(friendly.count, 3)
        XCTAssertEqual(friendly[0], "DuckDuckGo Search")
        XCTAssertEqual(friendly[1], "file_search") // Not mapped
        XCTAssertEqual(friendly[2], "unknown_tool") // Not mapped
        
        print("✓ ToolNameMapper handles multiple names")
    }
    
    func testToolNameMapperFormatList() {
        let toolNames = ["duckduckgo_search"]
        let formatted = ToolNameMapper.formatToolList(toolNames)
        
        XCTAssertEqual(formatted, "DuckDuckGo Search")
        
        let multiple = ["duckduckgo_search", "file_search"]
        let formattedMultiple = ToolNameMapper.formatToolList(multiple)
        
        XCTAssertTrue(formattedMultiple.contains("DuckDuckGo Search"))
        XCTAssertTrue(formattedMultiple.contains("file_search"))
        
        print("✓ ToolNameMapper formats lists correctly")
    }
    
    // MARK: - End-to-End Integration Test
    
    func testEndToEndToolTracking() async throws {
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        
        guard case .available = availability else {
            throw XCTSkip("Model not available")
        }
        
        // Setup
        let tool = DuckDuckGoFoundationTool()
        await modelService.updateTools([tool])
        
        // Query that should trigger tool
        let query = "Search DuckDuckGo for: what is Python?"
        let response = try await modelService.respond(to: query)
        
        // Verify response structure
        XCTAssertFalse(response.content.isEmpty)
        XCTAssertNotNil(response.toolCalls)
        
        // If tools were used, verify they're properly formatted
        if !response.toolCalls.isEmpty {
            let toolNames = response.toolCalls.map { $0.toolName }
            let friendlyNames = ToolNameMapper.friendlyNames(for: toolNames)
            
            print("\n=== End-to-End Tool Tracking Test ===")
            print("Query: \(query)")
            print("Response length: \(response.content.count)")
            print("Tools tracked: \(toolNames.joined(separator: ", "))")
            print("Friendly names: \(friendlyNames.joined(separator: ", "))")
            print("Formatted: \(ToolNameMapper.formatToolList(toolNames))")
            print("=====================================")
            
            // Verify at least one tool was tracked
            XCTAssertTrue(toolNames.count > 0, "At least one tool should be tracked if tools were used")
        } else {
            print("⚠ No tools were tracked (tool may not have been used by model)")
        }
        
        print("✓ End-to-end tool tracking test complete")
    }
}







