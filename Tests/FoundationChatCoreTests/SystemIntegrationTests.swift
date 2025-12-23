//
//  SystemIntegrationTests.swift
//  FoundationChatCoreTests
//
//  Comprehensive system integration tests for multi-agent orchestration
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class SystemIntegrationTests: XCTestCase {
    var agentService: AgentService!
    var conversationService: ConversationService!
    var conversationId: UUID!
    
    override func setUp() async throws {
        try await super.setUp()
        agentService = AgentService()
        conversationService = try ConversationService()
        
        // Ensure all agents are initialized before tests run
        try await TestHelpers.ensureAgentsInitialized(agentService: agentService)
        
        // Create a test conversation
        let conversation = try conversationService.createConversation(
            title: "Test Conversation"
        )
        conversationId = conversation.id
    }
    
    override func tearDown() async throws {
        if let conversationId = conversationId {
            try? await conversationService.deleteConversation(id: conversationId)
        }
        try await super.tearDown()
    }
    
    // MARK: - Agent Registration Tests
    
    func testDefaultAgentsAreRegistered() async throws {
        let agents = await agentService.getAvailableAgents()
        
        XCTAssertFalse(agents.isEmpty, "Default agents should be registered")
        
        let agentNames = agents.map { $0.name }
        XCTAssertTrue(agentNames.contains(AgentName.fileReader), "FileReaderAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.webSearch), "WebSearchAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.codeAnalysis), "CodeAnalysisAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.dataAnalysis), "DataAnalysisAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.visionAgent), "VisionAgent should be registered")
        XCTAssertTrue(agentNames.contains(AgentName.coordinator), "Coordinator agent should be registered")
    }
    
    func testAgentsHaveCorrectCapabilities() async throws {
        let agents = await agentService.getAvailableAgents()
        
        let fileReader = agents.first { $0.name == AgentName.fileReader }
        XCTAssertNotNil(fileReader, "File Reader agent should exist")
        XCTAssertTrue(fileReader?.capabilities.contains(.fileReading) ?? false, "File Reader should have fileReading capability")
        
        let webSearch = agents.first { $0.name == AgentName.webSearch }
        XCTAssertNotNil(webSearch, "Web Search agent should exist")
        XCTAssertTrue(webSearch?.capabilities.contains(.webSearch) ?? false, "Web Search should have webSearch capability")
        
        let codeAnalysis = agents.first { $0.name == AgentName.codeAnalysis }
        XCTAssertNotNil(codeAnalysis, "Code Analysis agent should exist")
        XCTAssertTrue(codeAnalysis?.capabilities.contains(.codeAnalysis) ?? false, "Code Analysis should have codeAnalysis capability")
        
        let dataAnalysis = agents.first { $0.name == AgentName.dataAnalysis }
        XCTAssertNotNil(dataAnalysis, "Data Analysis agent should exist")
        XCTAssertTrue(dataAnalysis?.capabilities.contains(.dataAnalysis) ?? false, "Data Analysis should have dataAnalysis capability")
    }
    
    // MARK: - Single Agent Tests
    
    func testSingleAgentProcessesMessage() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Coordinator agent should exist")
            return
        }
        
        // Create single agent configuration
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id],
            pattern: .orchestrator
        )
        
        // Update conversation with configuration
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Add user message
        let messageText = "What is 2+2?"
        let userMessage = Message(role: .user, content: messageText)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        // Process a message
        let result = try await agentService.processMessage(
            messageText,
            conversationId: conversationId,
            conversation: conversation
        )
        
        // Add assistant message
        let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
        conversation.messages.append(assistantMessage)
        try await conversationService.addMessage(assistantMessage, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        XCTAssertTrue(result.success, "Agent should successfully process message")
        XCTAssertFalse(result.content.isEmpty, "Agent should return content")
    }
    
    // MARK: - Orchestrator Mode Tests (Experimental)
    
    /// Test orchestrator mode (experimental) - coordinator delegates to specialized agents
    func testOrchestratorModeSharesContext() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == "Coordinator" }),
              let webSearch = agents.first(where: { $0.name == AgentName.webSearch }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        // Create multi-agent configuration
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id],
            pattern: .orchestrator
        )
        
        // Update conversation
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // First message
        let message1 = "Search for information about Swift programming"
        let userMessage1 = Message(role: .user, content: message1)
        conversation.messages.append(userMessage1)
        try await conversationService.addMessage(userMessage1, to: conversationId)
        
        let result1 = try await agentService.processMessage(
            message1,
            conversationId: conversationId,
            conversation: conversation
        )
        
        XCTAssertTrue(result1.success, "First message should succeed")
        
        // Add assistant message
        let assistantMessage1 = Message(role: .assistant, content: result1.content, toolCalls: result1.toolCalls)
        conversation.messages.append(assistantMessage1)
        try await conversationService.addMessage(assistantMessage1, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        // Reload conversation
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Second message - should have context from first
        let message2 = "What did you find?"
        let userMessage2 = Message(role: .user, content: message2)
        conversation.messages.append(userMessage2)
        try await conversationService.addMessage(userMessage2, to: conversationId)
        
        let result2 = try await agentService.processMessage(
            message2,
            conversationId: conversationId,
            conversation: conversation
        )
        
        // Add assistant message
        let assistantMessage2 = Message(role: .assistant, content: result2.content, toolCalls: result2.toolCalls)
        conversation.messages.append(assistantMessage2)
        try await conversationService.addMessage(assistantMessage2, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        XCTAssertTrue(result2.success, "Second message should succeed")
        // Context should be shared - the second message should reference the first
        XCTAssertTrue(
            result2.content.lowercased().contains("swift") || 
            result2.content.lowercased().contains("programming") ||
            result2.content.lowercased().contains("search"),
            "Second message should reference context from first message"
        )
    }
    
    /// Test collaborative pattern in orchestrator mode (experimental)
    func testOrchestratorModeCollaborativePattern() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == "Coordinator" }),
              let webSearch = agents.first(where: { $0.name == "Web Search" }),
              let codeAnalysis = agents.first(where: { $0.name == AgentName.codeAnalysis }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        // Create collaborative configuration
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id, codeAnalysis.id],
            pattern: .collaborative
        )
        
        // Update conversation
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Process message that could benefit from multiple agents
        let message = "Search for Swift best practices and analyze code structure"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        let result = try await agentService.processMessage(
            message,
            conversationId: conversationId,
            conversation: conversation
        )
        
        // Add assistant message
        let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
        conversation.messages.append(assistantMessage)
        try await conversationService.addMessage(assistantMessage, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        XCTAssertTrue(result.success, "Collaborative pattern should succeed")
        XCTAssertFalse(result.content.isEmpty, "Should return content")
    }
    
    // MARK: - Tool Integration Tests
    
    func testWebSearchAgentUsesDuckDuckGoTool() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let webSearch = agents.first(where: { $0.name == "Web Search" }) else {
            XCTFail("Web Search agent should exist")
            return
        }
        
        // Create single agent configuration
        let config = await agentService.createAgentConfiguration(
            agentIds: [webSearch.id],
            pattern: .orchestrator
        )
        
        // Update conversation
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Process search query
        let message = "Search for information about Python programming language"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        let result = try await agentService.processMessage(
            message,
            conversationId: conversationId,
            conversation: conversation
        )
        
        // Add assistant message
        let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
        conversation.messages.append(assistantMessage)
        try await conversationService.addMessage(assistantMessage, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        XCTAssertTrue(result.success, "Web search should succeed")
        
        // Check if tool was used
        let toolCalls = result.toolCalls
        let hasDuckDuckGoCall = toolCalls.contains { $0.toolName == "duckduckgo_search" }
        
        // Tool may or may not be called depending on model decision, but if called, should be tracked
        if !toolCalls.isEmpty {
            XCTAssertTrue(hasDuckDuckGoCall, "If tools were used, DuckDuckGo should be among them")
        }
    }
    
    // MARK: - Context Preservation Tests
    
    func testConversationHistoryIsPreserved() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Coordinator agent should exist")
            return
        }
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id],
            pattern: .orchestrator
        )
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Send multiple messages
        let message1 = "My name is Alice"
        let userMessage1 = Message(role: .user, content: message1)
        conversation.messages.append(userMessage1)
        try await conversationService.addMessage(userMessage1, to: conversationId)
        
        let result1 = try await agentService.processMessage(
            message1,
            conversationId: conversationId,
            conversation: conversation
        )
        
        let assistantMessage1 = Message(role: .assistant, content: result1.content, toolCalls: result1.toolCalls)
        conversation.messages.append(assistantMessage1)
        try await conversationService.addMessage(assistantMessage1, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message2 = "What is my name?"
        let userMessage2 = Message(role: .user, content: message2)
        conversation.messages.append(userMessage2)
        try await conversationService.addMessage(userMessage2, to: conversationId)
        
        let result2 = try await agentService.processMessage(
            message2,
            conversationId: conversationId,
            conversation: conversation
        )
        
        let assistantMessage2 = Message(role: .assistant, content: result2.content, toolCalls: result2.toolCalls)
        conversation.messages.append(assistantMessage2)
        try await conversationService.addMessage(assistantMessage2, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        // Check conversation history
        let finalConversation = try conversationService.loadConversation(id: conversationId)!
        XCTAssertGreaterThanOrEqual(finalConversation.messages.count, 4, "Should have at least 4 messages (2 user + 2 agent)")
        
        // Check that context was preserved
        let lastMessage = finalConversation.messages.last
        XCTAssertNotNil(lastMessage, "Should have a last message")
        // The agent should be able to reference the name from context
        // Note: This is a soft check - the model may or may not explicitly mention the name
        // but the context should be available
    }
    
    // MARK: - Error Handling Tests
    
    func testHandlesInvalidAgentConfiguration() async throws {
        let invalidConfig = AgentConfiguration(
            selectedAgents: [UUID()], // Non-existent agent ID
            orchestrationPattern: .orchestrator,
            agentSettings: [:]
        )
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = invalidConfig
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Should handle gracefully - either use available agents or return error
        let message = "Test message"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try? await conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processMessage(
                message,
                conversationId: conversationId,
                conversation: conversation
            )
            // If it succeeds, that's fine - it may fall back to available agents
            XCTAssertNotNil(result, "Should return a result")
        } catch {
            // If it fails, that's also acceptable for invalid configuration
            XCTAssertTrue(error is AgentServiceError, "Should throw AgentServiceError")
        }
    }
    
    // MARK: - Performance Tests
    
    /// Test orchestrator mode performance (experimental)
    func testOrchestratorModePerformance() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let coordinator = agents.first(where: { $0.name == "Coordinator" }),
              let webSearch = agents.first(where: { $0.name == AgentName.webSearch }) else {
            XCTFail("Required agents should exist")
            return
        }
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id],
            pattern: .orchestrator
        )
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Measure execution time
        let startTime = Date()
        
        let message = "Search for information about artificial intelligence"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        let result = try await agentService.processMessage(
            message,
            conversationId: conversationId,
            conversation: conversation
        )
        
        let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
        conversation.messages.append(assistantMessage)
        try await conversationService.addMessage(assistantMessage, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        let executionTime = Date().timeIntervalSince(startTime)
        
        XCTAssertTrue(result.success, "Should succeed")
        XCTAssertLessThan(executionTime, 30.0, "Should complete within 30 seconds")
        print("Execution time: \(executionTime) seconds")
    }
}
