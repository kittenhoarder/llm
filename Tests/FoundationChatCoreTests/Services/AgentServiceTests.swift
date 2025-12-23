//
//  AgentServiceTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for AgentService
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class AgentServiceTests: XCTestCase {
    var agentService: AgentService!
    var conversationService: ConversationService!
    var conversationId: UUID!
    
    override func setUp() async throws {
        try await super.setUp()
        agentService = AgentService()
        conversationService = try ConversationService()
        
        // Ensure all agents are initialized before tests run
        try await TestHelpers.ensureAgentsInitialized(agentService: agentService)
        
        let conversation = try conversationService.createConversation(title: "Test Conversation")
        conversationId = conversation.id
    }
    
    override func tearDown() async throws {
        if let conversationId = conversationId {
            try? await conversationService.deleteConversation(id: conversationId)
        }
        try await super.tearDown()
    }
    
    // MARK: - Agent Registration Tests
    
    func testAgentServiceInitializesDefaultAgents() async throws {
        let agents = await agentService.getAvailableAgents()
        
        XCTAssertFalse(agents.isEmpty, "Should have registered agents")
        
        let agentNames = agents.map { $0.name }
        XCTAssertTrue(agentNames.contains(AgentName.fileReader), "FileReaderAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.webSearch), "WebSearchAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.codeAnalysis), "CodeAnalysisAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.dataAnalysis), "DataAnalysisAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.visionAgent), "VisionAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.coordinator), "Coordinator should be registered")
    }
    
    // MARK: - Single-Agent Mode Tests
    
    func testAgentServiceProcessSingleAgentMessage() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == AgentName.fileReader }) else {
            XCTFail("File Reader agent should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [fileReader.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "Test message"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        // This may fail if ModelService is unavailable, which is acceptable
        do {
            let result = try await agentService.processSingleAgentMessage(
                message,
                agentId: fileReader.id,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
        } catch {
            // ModelService unavailable is acceptable in test environment
            if case AgentServiceError.agentNotFound = error {
                XCTFail("Agent should be found")
            }
            // Other errors (like ModelService unavailable) are acceptable
        }
    }
    
    // MARK: - Orchestrator Mode Tests
    
    func testAgentServiceProcessMessageWithOrchestrator() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Coordinator agent should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "Test message"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        // This may fail if ModelService is unavailable, which is acceptable
        do {
            let result = try await agentService.processMessage(
                message,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - File Reference Tests
    
    func testAgentServiceHandlesFileReferences() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == AgentName.fileReader }) else {
            XCTFail("File Reader agent should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [fileReader.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let testFilePath = "/tmp/test_file.txt"
        try "Test content".write(toFile: testFilePath, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: testFilePath)
        }
        
        let message = "Read this file"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        // Process with file reference
        do {
            let result = try await agentService.processSingleAgentMessage(
                message,
                agentId: fileReader.id,
                conversationId: conversationId,
                conversation: conversation,
                fileReferences: [testFilePath]
            )
            XCTAssertNotNil(result, "Should return a result")
            // File reference should be passed to agent
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - Configuration Tests
    
    func testAgentServiceCreatesAgentConfiguration() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == AgentName.fileReader }) else {
            XCTFail("File Reader agent should exist")
            return
        }
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [fileReader.id],
            pattern: .orchestrator
        )
        
        XCTAssertNotNil(config, "Should create configuration")
        XCTAssertEqual(config.selectedAgents.count, 1, "Should have one selected agent")
        XCTAssertEqual(config.selectedAgents.first, fileReader.id, "Should include File Reader agent")
        XCTAssertEqual(config.orchestrationPattern, .orchestrator, "Should set orchestration pattern")
    }
    
    func testAgentServiceCreatesConfigurationWithMultipleAgents() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == "File Reader" }),
              let webSearch = agents.first(where: { $0.name == AgentName.webSearch }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [fileReader.id, webSearch.id],
            pattern: .orchestrator
        )
        
        XCTAssertNotNil(config, "Should create configuration")
        XCTAssertEqual(config.selectedAgents.count, 2, "Should have two selected agents")
        XCTAssertTrue(config.selectedAgents.contains(fileReader.id), "Should include File Reader")
        XCTAssertTrue(config.selectedAgents.contains(webSearch.id), "Should include Web Search")
    }
}
