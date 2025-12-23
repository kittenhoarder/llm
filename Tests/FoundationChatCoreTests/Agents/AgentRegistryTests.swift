//
//  AgentRegistryTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for agent registry
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class AgentRegistryTests: XCTestCase {
    func testAgentRegistryRegistration() async {
        let registry = AgentRegistry.shared
        await registry.clear()
        
        let agent = FileReaderAgent()
        await registry.register(agent)
        
        let count = await registry.count()
        XCTAssertEqual(count, 1)
    }
    
    func testAgentRegistryGetByID() async {
        let registry = AgentRegistry.shared
        await registry.clear()
        
        let agent = FileReaderAgent()
        await registry.register(agent)
        
        let retrieved = await registry.getAgent(byId: agent.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, agent.id)
    }
    
    func testAgentRegistryGetByCapability() async {
        let registry = AgentRegistry.shared
        await registry.clear()
        
        let fileAgent = FileReaderAgent()
        let webAgent = WebSearchAgent()
        
        await registry.register(fileAgent)
        await registry.register(webAgent)
        
        let fileAgents = await registry.getAgents(byCapability: .fileReading)
        XCTAssertEqual(fileAgents.count, 1)
        
        let webAgents = await registry.getAgents(byCapability: .webSearch)
        XCTAssertEqual(webAgents.count, 1)
    }
}






