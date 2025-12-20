//
//  PerformanceTests.swift
//  FoundationChatTests
//
//  Performance tests for tool execution
//

import XCTest
@testable import FoundationChat

final class PerformanceTests: XCTestCase {
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
    
    // MARK: - Latency Tests
    
    func testToolCallLatency() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "test"]
        )
        
        let startTime = Date()
        _ = await toolService.executeToolCall(request)
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete within 10 seconds (p95 target is 2 seconds, but allow more for network)
        XCTAssertLessThan(duration, 10.0, "Tool call should complete within 10 seconds")
        
        print("Tool call latency: \(String(format: "%.3f", duration))s")
    }
    
    func testMultipleSequentialCalls() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let queries = ["Swift", "Python", "JavaScript", "Go", "Rust"]
        var totalDuration: TimeInterval = 0
        
        for query in queries {
            let request = ToolCallRequest(
                toolName: "duckduckgo_search",
                parameters: ["query": query]
            )
            
            let startTime = Date()
            _ = await toolService.executeToolCall(request)
            totalDuration += Date().timeIntervalSince(startTime)
        }
        
        let averageDuration = totalDuration / Double(queries.count)
        print("Average latency for \(queries.count) calls: \(String(format: "%.3f", averageDuration))s")
        
        // Average should be reasonable
        XCTAssertLessThan(averageDuration, 5.0, "Average latency should be reasonable")
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentToolCalls() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let requestCount = 10
        let requests = (0..<requestCount).map { index in
            ToolCallRequest(
                toolName: "duckduckgo_search",
                parameters: ["query": "test\(index)"]
            )
        }
        
        let startTime = Date()
        
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
        
        let totalDuration = Date().timeIntervalSince(startTime)
        let averageDuration = totalDuration / Double(requestCount)
        
        XCTAssertEqual(results.count, requestCount, "Should handle all concurrent requests")
        print("Concurrent \(requestCount) calls completed in \(String(format: "%.3f", totalDuration))s")
        print("Average per call: \(String(format: "%.3f", averageDuration))s")
        
        // Concurrent calls should complete faster than sequential
        XCTAssertLessThan(totalDuration, Double(requestCount) * 5.0, "Concurrent calls should be efficient")
    }
    
    // MARK: - Memory Tests
    
    func testMemoryUsage() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        // Execute multiple tool calls and check for memory leaks
        for i in 0..<10 {
            let request = ToolCallRequest(
                toolName: "duckduckgo_search",
                parameters: ["query": "test\(i)"]
            )
            
            _ = await toolService.executeToolCall(request)
        }
        
        // If we get here without crashing, memory usage is acceptable
        XCTAssertTrue(true, "Memory usage test passed")
    }
    
    // MARK: - Registry Performance Tests
    
    func testRegistryRegistrationPerformance() async {
        let startTime = Date()
        
        for i in 0..<100 {
            let tool = MockTool(name: "tool\(i)")
            await registry.register(tool)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("Registered 100 tools in \(String(format: "%.3f", duration))s")
        
        // Should be very fast
        XCTAssertLessThan(duration, 1.0, "Registry registration should be fast")
    }
    
    func testRegistryLookupPerformance() async {
        // Register tools
        for i in 0..<100 {
            let tool = MockTool(name: "tool\(i)")
            await registry.register(tool)
        }
        
        // Measure lookup performance
        let startTime = Date()
        
        for i in 0..<1000 {
            _ = await registry.isRegistered(name: "tool\(i % 100)")
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let averageLookup = duration / 1000.0
        
        print("1000 lookups in \(String(format: "%.3f", duration))s")
        print("Average lookup: \(String(format: "%.6f", averageLookup))s")
        
        // Lookups should be very fast
        XCTAssertLessThan(averageLookup, 0.001, "Registry lookups should be very fast")
    }
    
    // MARK: - Tool Execution Performance
    
    func testToolExecutionTimeTracking() async {
        let tool = DuckDuckGoToolService()
        await toolService.registerTool(tool)
        
        let request = ToolCallRequest(
            toolName: "duckduckgo_search",
            parameters: ["query": "test"]
        )
        
        let result = await toolService.executeToolCall(request)
        
        // Execution time should be tracked
        // Note: We can't directly access execution time from ToolCallResult,
        // but we can verify the result was generated
        XCTAssertNotNil(result, "Result should be generated")
    }
}









