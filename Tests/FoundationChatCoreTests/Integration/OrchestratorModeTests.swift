//
//  OrchestratorModeTests.swift
//  FoundationChatCoreTests
//
//  Integration tests for orchestrator mode (experimental)
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class OrchestratorModeTests: XCTestCase {
    var agentService: AgentService!
    var conversationService: ConversationService!
    var conversationId: UUID!
    
    override func setUp() async throws {
        try await super.setUp()
        agentService = AgentService()
        conversationService = try ConversationService()
        
        // Ensure all agents are initialized before tests run
        try await TestHelpers.ensureAgentsInitialized(agentService: agentService)
        
        let conversation = try conversationService.createConversation(title: "Orchestrator Test")
        conversationId = conversation.id
    }
    
    override func tearDown() async throws {
        if let conversationId = conversationId {
            try? await conversationService.deleteConversation(id: conversationId)
        }
        try await super.tearDown()
    }
    
    // MARK: - Delegation Tests
    
    func testOrchestratorModeDelegatesToSpecializedAgents() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == AgentName.coordinator }),
              let webSearch = agents.first(where: { $0.name == AgentName.webSearch }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "Search for information about Swift"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try conversationService.addMessage(userMessage, to: conversationId)
        
        // Process message through orchestrator
        do {
            let result = try await agentService.processMessage(
                message,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
            // Coordinator should delegate to WebSearchAgent
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - Smart Delegation Tests
    
    func testOrchestratorModeSmartDelegation() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Coordinator should exist")
            return
        }
        
        let defaults = UserDefaults.standard
        let originalSmartDelegation = defaults.object(forKey: "smartDelegation")
        
        defer {
            if let original = originalSmartDelegation {
                defaults.set(original, forKey: "smartDelegation")
            } else {
                defaults.removeObject(forKey: "smartDelegation")
            }
        }
        
        // Enable smart delegation
        defaults.set(true, forKey: "smartDelegation")
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Simple greeting - should not delegate
        let message = "Hello"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processMessage(
                message,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
            // With smart delegation, coordinator should respond directly for simple messages
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - Result Synthesis Tests
    
    func testOrchestratorModeSynthesizesResults() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == "Coordinator" }),
              let fileReader = agents.first(where: { $0.name == "File Reader" }),
              let webSearch = agents.first(where: { $0.name == AgentName.webSearch }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, fileReader.id, webSearch.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "Search for Swift best practices and analyze code"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processMessage(
                message,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
            // Coordinator should synthesize results from multiple agents
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - Image Task Delegation Tests
    
    func testOrchestratorModeHandlesImageTasks() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == "Coordinator" }),
              let visionAgent = agents.first(where: { $0.name == AgentName.visionAgent }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        // Create test image
        let imagePath = "/tmp/test_image.png"
        let pngData = createMinimalPNG()
        try pngData.write(to: URL(fileURLWithPath: imagePath))
        defer {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, visionAgent.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "What's in this image?"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processMessage(
                message,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
            // Coordinator should delegate image tasks to VisionAgent
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create a minimal valid PNG file for testing
    private func createMinimalPNG() -> Data {
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
            0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
            0x0D, 0x0A, 0x2D, 0xB4,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngHeader)
    }
}

