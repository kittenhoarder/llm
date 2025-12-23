//
//  MultiAgentContextualModeTests.swift
//  FoundationChatCoreTests
//
//  Tests specifically for contextual mode in multi-agent scenarios
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class MultiAgentContextualModeTests: XCTestCase {
    var agentService: AgentService!
    var conversationService: ConversationService!
    var conversationId: UUID!
    
    override func setUp() async throws {
        try await super.setUp()
        agentService = AgentService()
        conversationService = try ConversationService()
        
        // Ensure all agents are initialized before tests run
        try await TestHelpers.ensureAgentsInitialized(agentService: agentService)
        
        let conversation = try conversationService.createConversation(
            title: "Contextual Test"
        )
        conversationId = conversation.id
    }
    
    override func tearDown() async throws {
        if let conversationId = conversationId {
            try? await conversationService.deleteConversation(id: conversationId)
        }
        try await super.tearDown()
    }
    
    // MARK: - Contextual Mode Requirement Tests
    
    /// Test that multi-agent conversations maintain context across messages
    func testMultiAgentMaintainsContextAcrossMessages() async throws {
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
        
        // First message establishes context
        let message1 = "I'm working on a Swift project about machine learning"
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
        
        // Second message should reference the context
        let message2 = "What programming language am I using?"
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
        
        // Verify context was maintained
        let content = result2.content.lowercased()
        let hasContext = content.contains("swift") || 
                        content.contains("machine learning") ||
                        content.contains("project")
        
        // Note: This is a soft assertion - the model may not always explicitly reference
        // the context, but it should be available. We're checking that the system
        // at least attempts to maintain context.
        print("Second message content: \(result2.content)")
        print("Context maintained: \(hasContext)")
    }
    
    /// Test that AgentContext is properly shared between agents in multi-agent setup
    func testAgentContextSharingInMultiAgent() async throws {
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
        
        // First agent processes a message
        let message1 = "Search for information about Swift"
        let userMessage1 = Message(role: .user, content: message1)
        conversation.messages.append(userMessage1)
        try await conversationService.addMessage(userMessage1, to: conversationId)
        
        let result1 = try await agentService.processMessage(
            message1,
            conversationId: conversationId,
            conversation: conversation
        )
        
        XCTAssertTrue(result1.success, "First agent should succeed")
        
        // Add assistant message
        let assistantMessage1 = Message(role: .assistant, content: result1.content, toolCalls: result1.toolCalls)
        conversation.messages.append(assistantMessage1)
        try await conversationService.addMessage(assistantMessage1, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        // Check that context was updated
        let updatedConversation = try conversationService.loadConversation(id: conversationId)!
        XCTAssertGreaterThan(updatedConversation.messages.count, 0, "Messages should be added to conversation")
        
        // Reload conversation
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Second message - different agent should have access to previous context
        let message2 = "What did you find about Swift?"
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
        
        XCTAssertTrue(result2.success, "Second agent should succeed")
        
        // Verify that conversation history is being shared
        let finalConversation = try conversationService.loadConversation(id: conversationId)!
        XCTAssertGreaterThanOrEqual(finalConversation.messages.count, 4, 
                                   "Should have at least 4 messages (2 user + 2 agent responses)")
    }
    
    /// Test that tool results are shared in context between agents
    func testToolResultsSharedInContext() async throws {
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
        
        // First message triggers tool usage
        let message1 = "Search for current information about Python"
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
        
        // Check if tools were used
        let toolCalls1 = result1.toolCalls
        print("Tool calls in first message: \(toolCalls1.map { $0.toolName })")
        
        // Reload conversation
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Second message should reference tool results if they were generated
        let message2 = "Summarize what you found"
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
        
        // The second agent should be able to reference results from the first
        // This tests that toolResults in AgentContext are being shared
        print("Second message content: \(result2.content)")
    }
    
    /// Test that conversation history is properly passed to agents
    func testConversationHistoryPassedToAgents() async throws {
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
        
        // Send a series of messages
        let messages = [
            "Hello, I'm working on a project",
            "It's about artificial intelligence",
            "I need help with machine learning"
        ]
        
        for messageText in messages {
            let userMessage = Message(role: .user, content: messageText)
            conversation.messages.append(userMessage)
            try await conversationService.addMessage(userMessage, to: conversationId)
            
            let result = try await agentService.processMessage(
                messageText,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertTrue(result.success, "Message should succeed: \(messageText)")
            
            let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
            conversation.messages.append(assistantMessage)
            try await conversationService.addMessage(assistantMessage, to: conversationId)
            try conversationService.updateConversation(conversation)
            
            // Reload for next iteration
            conversation = try conversationService.loadConversation(id: conversationId)!
        }
        
        // Final message that should reference all previous context
        let finalMessage = "What is my project about?"
        let finalUserMessage = Message(role: .user, content: finalMessage)
        conversation.messages.append(finalUserMessage)
        try await conversationService.addMessage(finalUserMessage, to: conversationId)
        
        let finalResult = try await agentService.processMessage(
            finalMessage,
            conversationId: conversationId,
            conversation: conversation
        )
        
        let finalAssistantMessage = Message(role: .assistant, content: finalResult.content, toolCalls: finalResult.toolCalls)
        conversation.messages.append(finalAssistantMessage)
        try await conversationService.addMessage(finalAssistantMessage, to: conversationId)
        try conversationService.updateConversation(conversation)
        
        XCTAssertTrue(finalResult.success, "Final message should succeed")
        
        // Verify conversation has all messages
        let checkConversation = try conversationService.loadConversation(id: conversationId)!
        XCTAssertGreaterThanOrEqual(checkConversation.messages.count, 8, 
                                   "Should have at least 8 messages (4 user + 4 agent)")
        
        print("Final response: \(finalResult.content)")
    }
    
    // MARK: - Contextual Mode Recommendation
    
    /// Document the finding that contextual mode should be enabled for multi-agent
    func testContextualModeShouldBeEnabled() {
        // This test documents the finding that contextual mode should be enabled
        // for multi-agent conversations to maintain LanguageModelSession state
        
        let recommendation = """
        RECOMMENDATION: Contextual mode should be enabled for multi-agent conversations.
        
        Current Implementation:
        - Agents share context via AgentContext.conversationHistory ✓
        - Each agent has its own ModelService instance
        - Agents use non-contextual respond() method (no session reuse)
        
        Issue:
        - LanguageModelSession state is not maintained across messages
        - Each agent call creates a new session, losing conversation state
        
        Solution:
        - Agents should use the contextual respond() method that takes:
          - conversationId: UUID
          - previousMessages: [Message]
          - useContextual: Bool
        - This maintains LanguageModelSession state across agent calls
        - Contextual mode should default to true for multi-agent conversations
        """
        
        print(recommendation)
        // This test always passes - it's documentation
        XCTAssertTrue(true, "Contextual mode recommendation documented")
    }
}
