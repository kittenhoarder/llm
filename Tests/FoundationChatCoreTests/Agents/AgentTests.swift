//
//  AgentTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for agent infrastructure
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class AgentTests: XCTestCase {
    func testAgentCapability() {
        let capability = AgentCapability.fileReading
        XCTAssertEqual(capability.rawValue, "fileReading")
    }
    
    func testAgentContext() {
        var context = AgentContext()
        XCTAssertTrue(context.conversationHistory.isEmpty)
        XCTAssertTrue(context.fileReferences.isEmpty)
        
        context.fileReferences.append("test.txt")
        XCTAssertEqual(context.fileReferences.count, 1)
    }
    
    func testAgentTask() {
        let task = AgentTask(
            description: "Test task",
            requiredCapabilities: [.fileReading],
            priority: 1
        )
        
        XCTAssertEqual(task.description, "Test task")
        XCTAssertTrue(task.requiredCapabilities.contains(.fileReading))
        XCTAssertEqual(task.priority, 1)
    }
    
    func testAgentResult() {
        let result = AgentResult(
            agentId: UUID(),
            taskId: UUID(),
            content: "Test result",
            success: true
        )
        
        XCTAssertEqual(result.content, "Test result")
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
    }
}





