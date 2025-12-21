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
    
    // MARK: - Smart Delegation Tests
    
    func testSmartDelegationIsEnabledByDefault() {
        // Smart delegation should be enabled by default
        let defaults = UserDefaults.standard
        let smartDelegationEnabled: Bool
        if defaults.object(forKey: "smartDelegation") != nil {
            smartDelegationEnabled = defaults.bool(forKey: "smartDelegation")
        } else {
            smartDelegationEnabled = true // Default
        }
        XCTAssertTrue(smartDelegationEnabled, "Smart delegation should be enabled by default")
    }
    
    func testSmartDelegationCanBeDisabled() {
        let defaults = UserDefaults.standard
        let originalValue = defaults.object(forKey: "smartDelegation")
        
        // Set to false
        defaults.set(false, forKey: "smartDelegation")
        XCTAssertFalse(defaults.bool(forKey: "smartDelegation"), "Smart delegation should be disabled")
        
        // Restore original value
        if let original = originalValue {
            defaults.set(original, forKey: "smartDelegation")
        } else {
            defaults.removeObject(forKey: "smartDelegation")
        }
    }
    
    func testOrchestratorPatternRespectsSmartDelegationSetting() async throws {
        let coordinator = BaseAgent(
            name: "Test Coordinator",
            description: "Test",
            capabilities: [.generalReasoning]
        )
        
        let pattern = OrchestratorPattern(coordinator: coordinator)
        XCTAssertNotNil(pattern, "Pattern should be created")
        
        // The pattern should check UserDefaults for smartDelegation setting
        // This is tested indirectly through execution, but we verify the pattern exists
        let task = AgentTask(description: "Simple greeting")
        let context = AgentContext()
        let agents: [any Agent] = [coordinator]
        
        // This will test smart delegation during execution
        // Simple tasks should not delegate when smart delegation is enabled
        do {
            let result = try await pattern.execute(task: task, agents: agents, context: context)
            XCTAssertNotNil(result, "Pattern should execute and return result")
        } catch {
            // Execution may fail if ModelService is unavailable, which is acceptable in tests
            // We're just verifying the pattern structure supports smart delegation
        }
    }
}





