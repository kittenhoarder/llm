//
//  OrchestrationPatternTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for orchestration patterns
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class OrchestrationPatternTests: XCTestCase {
    func testOrchestrationPatternType() {
        let types: [OrchestrationPatternType] = [.orchestrator, .collaborative, .hierarchical]
        for type in types {
            XCTAssertFalse(type.rawValue.isEmpty)
        }
    }
    
    func testOrchestratorPatternCreation() {
        let coordinator = BaseAgent(
            name: "Test Coordinator",
            description: "Test",
            capabilities: [.generalReasoning]
        )
        
        let pattern = OrchestratorPattern(coordinator: coordinator)
        XCTAssertNotNil(pattern)
    }
    
    func testCollaborativePatternCreation() {
        let pattern = CollaborativePattern()
        XCTAssertNotNil(pattern)
    }
    
    func testHierarchicalPatternCreation() {
        let supervisor = BaseAgent(
            name: "Test Supervisor",
            description: "Test",
            capabilities: [.generalReasoning]
        )
        
        let pattern = HierarchicalPattern(supervisor: supervisor)
        XCTAssertNotNil(pattern)
    }
}





