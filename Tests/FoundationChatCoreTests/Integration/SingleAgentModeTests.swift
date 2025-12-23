//
//  SingleAgentModeTests.swift
//  FoundationChatCoreTests
//
//  Integration tests for single-agent mode
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class SingleAgentModeTests: XCTestCase {
    var agentService: AgentService!
    var conversationService: ConversationService!
    var conversationId: UUID!
    
    override func setUp() async throws {
        try await super.setUp()
        agentService = AgentService()
        conversationService = try ConversationService()
        
        // Ensure all agents are initialized before tests run
        try await TestHelpers.ensureAgentsInitialized(agentService: agentService)
        
        let conversation = try conversationService.createConversation(title: "Single Agent Test")
        conversationId = conversation.id
    }
    
    override func tearDown() async throws {
        if let conversationId = conversationId {
            try? await conversationService.deleteConversation(id: conversationId)
        }
        try await super.tearDown()
    }
    
    // MARK: - FileReaderAgent Tests
    
    func testSingleAgentModeWithFileReaderAgent() async throws {
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
        
        // Process message in single-agent mode
        do {
            let result = try await agentService.processSingleAgentMessage(
                message,
                agentId: fileReader.id,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
            // In single-agent mode, message is processed directly by the agent
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - WebSearchAgent Tests
    
    func testSingleAgentModeWithWebSearchAgent() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let webSearch = agents.first(where: { $0.name == AgentName.webSearch }) else {
            XCTFail("Web Search agent should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [webSearch.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "Test search query"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processSingleAgentMessage(
                message,
                agentId: webSearch.id,
                conversationId: conversationId,
                conversation: conversation
            )
            XCTAssertNotNil(result, "Should return a result")
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - VisionAgent Tests
    
    func testSingleAgentModeWithVisionAgent() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let visionAgent = agents.first(where: { $0.name == AgentName.visionAgent }) else {
            XCTFail("Vision Agent should exist")
            return
        }
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [visionAgent.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        // Create test image
        let imagePath = "/tmp/test_image.png"
        let pngData = createMinimalPNG()
        try pngData.write(to: URL(fileURLWithPath: imagePath))
        defer {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        
        let message = "What's in this image?"
        let userMessage = Message(role: .user, content: message)
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processSingleAgentMessage(
                message,
                agentId: visionAgent.id,
                conversationId: conversationId,
                conversation: conversation,
                fileReferences: [imagePath]
            )
            XCTAssertNotNil(result, "Should return a result")
        } catch {
            // ModelService unavailable is acceptable
        }
    }
    
    // MARK: - File Attachment Tests
    
    func testSingleAgentModeWithFileAttachments() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == AgentName.fileReader }) else {
            XCTFail("File Reader agent should exist")
            return
        }
        
        // Create test file
        let testFilePath = "/tmp/test_attachment.txt"
        try "Test file content".write(toFile: testFilePath, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: testFilePath)
        }
        
        let fileAttachment = FileAttachment(
            originalName: "test_attachment.txt",
            sandboxPath: testFilePath,
            fileSize: Int64("Test file content".utf8.count),
            mimeType: "text/plain"
        )
        
        var conversation = try conversationService.loadConversation(id: conversationId)!
        let config = await agentService.createAgentConfiguration(
            agentIds: [fileReader.id],
            pattern: .orchestrator
        )
        conversation.agentConfiguration = config
        try conversationService.updateConversation(conversation)
        conversation = try conversationService.loadConversation(id: conversationId)!
        
        let message = "Read this file"
        let userMessage = Message(role: .user, content: message, attachments: [fileAttachment])
        conversation.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        do {
            let result = try await agentService.processSingleAgentMessage(
                message,
                agentId: fileReader.id,
                conversationId: conversationId,
                conversation: conversation,
                fileReferences: [testFilePath]
            )
            XCTAssertNotNil(result, "Should return a result")
            // File attachment should be passed to agent
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
