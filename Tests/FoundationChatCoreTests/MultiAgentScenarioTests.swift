//
//  MultiAgentScenarioTests.swift
//  FoundationChatCoreTests
//
//  Realistic multi-agent scenario tests demonstrating different agent/tool combinations
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class MultiAgentScenarioTests: XCTestCase {
    var agentService: AgentService!
    var conversationService: ConversationService!
    var conversationId: UUID!
    var testOutputsDir: String!
    
    override func setUp() async throws {
        try await super.setUp()
        agentService = AgentService()
        conversationService = try ConversationService()
        
        // Ensure all agents are initialized before tests run
        try await TestHelpers.ensureAgentsInitialized(agentService: agentService)
        
        // Create test outputs directory with absolute path
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        testOutputsDir = (currentDir as NSString).appendingPathComponent("test_outputs")
        let outputsURL = URL(fileURLWithPath: testOutputsDir)
        try? fileManager.createDirectory(at: outputsURL, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let conversationId = conversationId {
            try? await conversationService.deleteConversation(id: conversationId)
        }
        try await super.tearDown()
    }
    
    // MARK: - Scenario 1: Research + Code Analysis
    
    /// Scenario: WebSearchAgent + CodeAnalysisAgent
    /// Task: Search for best practices and analyze code
    func testResearchAndCodeAnalysisScenario() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let webSearch = agents.first(where: { $0.name == AgentName.webSearch }),
              let codeAnalysis = agents.first(where: { $0.name == AgentName.codeAnalysis }),
              let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Required agents not found")
            return
        }
        
        let conversation = try conversationService.createConversation(title: "Research + Code Analysis")
        conversationId = conversation.id
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id, codeAnalysis.id],
            pattern: .orchestrator
        )
        
        var conv = try conversationService.loadConversation(id: conversationId)!
        conv.agentConfiguration = config
        try conversationService.updateConversation(conv)
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Sample Swift code for analysis
        let sampleCode = """
        func processData(_ data: [Int]) -> Int {
            var sum = 0
            for item in data {
                sum += item
            }
            return sum
        }
        """
        
        // Step 1: Search for best practices
        let message1 = "Search for Swift concurrency best practices"
        let userMessage1 = Message(role: .user, content: message1)
        conv.messages.append(userMessage1)
        try await conversationService.addMessage(userMessage1, to: conversationId)
        
        let result1 = try await agentService.processMessage(
            message1,
            conversationId: conversationId,
            conversation: conv
        )
        
        XCTAssertTrue(result1.success, "First message should succeed")
        
        // Add assistant message
        let assistantMessage1 = Message(role: .assistant, content: result1.content, toolCalls: result1.toolCalls)
        conv.messages.append(assistantMessage1)
        try await conversationService.addMessage(assistantMessage1, to: conversationId)
        try conversationService.updateConversation(conv)
        
        // Reload to get updated conversation
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Step 2: Analyze code with context from search
        let message2 = "Analyze this code for thread safety: \(sampleCode)"
        let userMessage2 = Message(role: .user, content: message2)
        conv.messages.append(userMessage2)
        try await conversationService.addMessage(userMessage2, to: conversationId)
        
        let result2 = try await agentService.processMessage(
            message2,
            conversationId: conversationId,
            conversation: conv
        )
        
        // Add assistant message
        let assistantMessage2 = Message(role: .assistant, content: result2.content, toolCalls: result2.toolCalls)
        conv.messages.append(assistantMessage2)
        try await conversationService.addMessage(assistantMessage2, to: conversationId)
        try conversationService.updateConversation(conv)
        
        XCTAssertTrue(result2.success, "Second message should succeed")
        
        // Verify outputs
        let finalConv = try conversationService.loadConversation(id: conversationId)!
        let allResults = [result1, result2]
        
        // Run verifications
        let toolVerification = OutputVerificationHelpers.verifyToolUsage(
            result: result1,
            expectedTools: ["duckduckgo_search"],
            allowPartial: true
        )
        
        let qualityVerification = OutputVerificationHelpers.verifyResponseQuality(
            result: result2,
            minLength: 20,
            requiredKeywords: ["code", "thread", "safety"]
        )
        
        let collaborationVerification = OutputVerificationHelpers.verifyMultiAgentCollaboration(
            results: allResults
        )
        
        let verificationResults: [String: VerificationResult] = [
            "tool_usage": toolVerification,
            "response_quality": qualityVerification,
            "collaboration": collaborationVerification
        ]
        
        // Generate report
        let report = TestOutputFormatter.createReport(
            scenarioName: "Research + Code Analysis",
            agents: [AgentName.webSearch, AgentName.codeAnalysis, AgentName.coordinator],
            results: allResults,
            conversation: finalConv,
            verificationResults: verificationResults
        )
        
        let savedFiles = try TestOutputFormatter.saveReport(report, to: testOutputsDir!)
        print("✓ Report saved to: \(savedFiles.joined(separator: ", "))")
        
        // Assertions
        XCTAssertTrue(toolVerification.passed || result1.toolCalls.isEmpty == false, 
                     "Tool usage: \(toolVerification.message)")
        XCTAssertTrue(qualityVerification.passed, "Quality: \(qualityVerification.message)")
    }
    
    // MARK: - Scenario 2: Data Processing Pipeline
    
    /// Scenario: FileReaderAgent + DataAnalysisAgent
    /// Task: Read file and calculate statistics
    func testDataProcessingPipelineScenario() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == AgentName.fileReader }),
              let dataAnalysis = agents.first(where: { $0.name == AgentName.dataAnalysis }),
              let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Required agents not found")
            return
        }
        
        let conversation = try conversationService.createConversation(title: "Data Processing Pipeline")
        conversationId = conversation.id
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, fileReader.id, dataAnalysis.id],
            pattern: .orchestrator
        )
        
        var conv = try conversationService.loadConversation(id: conversationId)!
        conv.agentConfiguration = config
        try conversationService.updateConversation(conv)
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Create a test CSV file
        let testCSV = """
        name,age,score
        Alice,25,85
        Bob,30,92
        Charlie,28,78
        """
        let csvPath = "\(testOutputsDir!)/test_data.csv"
        try testCSV.write(toFile: csvPath, atomically: true, encoding: .utf8)
        
        // Step 1: Read the file
        let message1 = "Read the data from \(csvPath) and show me the contents"
        let userMessage1 = Message(role: .user, content: message1)
        conv.messages.append(userMessage1)
        try await conversationService.addMessage(userMessage1, to: conversationId)
        
        let result1 = try await agentService.processMessage(
            message1,
            conversationId: conversationId,
            conversation: conv
        )
        
        XCTAssertTrue(result1.success, "File reading should succeed")
        
        // Add assistant message
        let assistantMessage1 = Message(role: .assistant, content: result1.content, toolCalls: result1.toolCalls)
        conv.messages.append(assistantMessage1)
        try await conversationService.addMessage(assistantMessage1, to: conversationId)
        try conversationService.updateConversation(conv)
        
        // Reload to get updated conversation
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Step 2: Analyze the data
        let message2 = "Calculate summary statistics for the data: average age and average score"
        let userMessage2 = Message(role: .user, content: message2)
        conv.messages.append(userMessage2)
        try await conversationService.addMessage(userMessage2, to: conversationId)
        
        let result2 = try await agentService.processMessage(
            message2,
            conversationId: conversationId,
            conversation: conv
        )
        
        // Add assistant message
        let assistantMessage2 = Message(role: .assistant, content: result2.content, toolCalls: result2.toolCalls)
        conv.messages.append(assistantMessage2)
        try await conversationService.addMessage(assistantMessage2, to: conversationId)
        try conversationService.updateConversation(conv)
        
        XCTAssertTrue(result2.success, "Data analysis should succeed")
        
        // Verify outputs
        let finalConv = try conversationService.loadConversation(id: conversationId)!
        let allResults = [result1, result2]
        
        let qualityVerification = OutputVerificationHelpers.verifyResponseQuality(
            result: result2,
            minLength: 20,
            requiredKeywords: ["average", "age", "score"]
        )
        
        let collaborationVerification = OutputVerificationHelpers.verifyMultiAgentCollaboration(
            results: allResults,
            minAgents: 1 // At least coordinator should be involved
        )
        
        let verificationResults: [String: VerificationResult] = [
            "response_quality": qualityVerification,
            "collaboration": collaborationVerification
        ]
        
        // Generate report
        let report = TestOutputFormatter.createReport(
            scenarioName: "Data Processing Pipeline",
            agents: [AgentName.fileReader, AgentName.dataAnalysis, AgentName.coordinator],
            results: allResults,
            conversation: finalConv,
            verificationResults: verificationResults
        )
        
        let savedFiles = try TestOutputFormatter.saveReport(report, to: testOutputsDir!)
        print("✓ Report saved to: \(savedFiles.joined(separator: ", "))")
        
        XCTAssertTrue(qualityVerification.passed, "Quality: \(qualityVerification.message)")
    }
    
    // MARK: - Scenario 3: Comprehensive Code Review
    
    /// Scenario: FileReaderAgent + CodeAnalysisAgent + WebSearchAgent + Coordinator
    /// Task: Review code, search for patterns, provide recommendations
    func testComprehensiveCodeReviewScenario() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let fileReader = agents.first(where: { $0.name == AgentName.fileReader }),
              let codeAnalysis = agents.first(where: { $0.name == AgentName.codeAnalysis }),
              let webSearch = agents.first(where: { $0.name == AgentName.webSearch }),
              let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Required agents not found")
            return
        }
        
        let conversation = try conversationService.createConversation(title: "Comprehensive Code Review")
        conversationId = conversation.id
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, fileReader.id, codeAnalysis.id, webSearch.id],
            pattern: .orchestrator
        )
        
        var conv = try conversationService.loadConversation(id: conversationId)!
        conv.agentConfiguration = config
        try conversationService.updateConversation(conv)
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Create a test Swift file
        let testCode = """
        class DataProcessor {
            var data: [String] = []
            
            func process() {
                for item in data {
                    print(item)
                }
            }
        }
        """
        let codePath = "\(testOutputsDir!)/test_code.swift"
        try testCode.write(toFile: codePath, atomically: true, encoding: .utf8)
        
        // Multi-step task
        let message = "Review the code in \(codePath), search for Swift best practices online, and provide improvement recommendations"
        let userMessage = Message(role: .user, content: message)
        conv.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        let result = try await agentService.processMessage(
            message,
            conversationId: conversationId,
            conversation: conv
        )
        
        // Add assistant message
        let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
        conv.messages.append(assistantMessage)
        try await conversationService.addMessage(assistantMessage, to: conversationId)
        try conversationService.updateConversation(conv)
        
        XCTAssertTrue(result.success, "Code review should succeed")
        
        // Verify outputs
        let finalConv = try conversationService.loadConversation(id: conversationId)!
        
        let toolVerification = OutputVerificationHelpers.verifyToolUsage(
            result: result,
            expectedTools: ["duckduckgo_search"],
            allowPartial: true
        )
        
        let qualityVerification = OutputVerificationHelpers.verifyResponseQuality(
            result: result,
            minLength: 50
        )
        
        let verificationResults: [String: VerificationResult] = [
            "tool_usage": toolVerification,
            "response_quality": qualityVerification
        ]
        
        // Generate report
        let report = TestOutputFormatter.createReport(
            scenarioName: "Comprehensive Code Review",
            agents: [AgentName.fileReader, AgentName.codeAnalysis, AgentName.webSearch, AgentName.coordinator],
            results: [result],
            conversation: finalConv,
            verificationResults: verificationResults
        )
        
        let savedFiles = try TestOutputFormatter.saveReport(report, to: testOutputsDir!)
        print("✓ Report saved to: \(savedFiles.joined(separator: ", "))")
        
        XCTAssertTrue(qualityVerification.passed, "Quality: \(qualityVerification.message)")
    }
    
    // MARK: - Scenario 4: Information Synthesis
    
    /// Scenario: WebSearchAgent + DataAnalysisAgent (collaborative pattern)
    /// Task: Search for trends and analyze data
    func testInformationSynthesisScenario() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let webSearch = agents.first(where: { $0.name == AgentName.webSearch }),
              let dataAnalysis = agents.first(where: { $0.name == AgentName.dataAnalysis }),
              let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Required agents not found")
            return
        }
        
        let conversation = try conversationService.createConversation(title: "Information Synthesis")
        conversationId = conversation.id
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id, dataAnalysis.id],
            pattern: .collaborative
        )
        
        var conv = try conversationService.loadConversation(id: conversationId)!
        conv.agentConfiguration = config
        try conversationService.updateConversation(conv)
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Collaborative task
        let message = "Search for current AI/ML trends and analyze the information to identify key patterns"
        let userMessage = Message(role: .user, content: message)
        conv.messages.append(userMessage)
        try await conversationService.addMessage(userMessage, to: conversationId)
        
        let result = try await agentService.processMessage(
            message,
            conversationId: conversationId,
            conversation: conv
        )
        
        // Add assistant message
        let assistantMessage = Message(role: .assistant, content: result.content, toolCalls: result.toolCalls)
        conv.messages.append(assistantMessage)
        try await conversationService.addMessage(assistantMessage, to: conversationId)
        try conversationService.updateConversation(conv)
        
        XCTAssertTrue(result.success, "Information synthesis should succeed")
        
        // Verify outputs
        let finalConv = try conversationService.loadConversation(id: conversationId)!
        
        let toolVerification = OutputVerificationHelpers.verifyToolUsage(
            result: result,
            expectedTools: ["duckduckgo_search"],
            allowPartial: true
        )
        
        let qualityVerification = OutputVerificationHelpers.verifyResponseQuality(
            result: result,
            minLength: 30
        )
        
        let verificationResults: [String: VerificationResult] = [
            "tool_usage": toolVerification,
            "response_quality": qualityVerification
        ]
        
        // Generate report
        let report = TestOutputFormatter.createReport(
            scenarioName: "Information Synthesis",
            agents: [AgentName.webSearch, AgentName.dataAnalysis, AgentName.coordinator],
            results: [result],
            conversation: finalConv,
            verificationResults: verificationResults
        )
        
        let savedFiles = try TestOutputFormatter.saveReport(report, to: testOutputsDir!)
        print("✓ Report saved to: \(savedFiles.joined(separator: ", "))")
        
        XCTAssertTrue(qualityVerification.passed, "Quality: \(qualityVerification.message)")
    }
    
    // MARK: - Scenario 5: Multi-Step Research
    
    /// Scenario: WebSearchAgent + Coordinator (orchestrator pattern)
    /// Task: Multi-step research with context maintenance
    func testMultiStepResearchScenario() async throws {
        let agents = await agentService.getAvailableAgents()
        guard let webSearch = agents.first(where: { $0.name == AgentName.webSearch }),
              let coordinator = agents.first(where: { $0.name == AgentName.coordinator }) else {
            XCTFail("Required agents not found")
            return
        }
        
        let conversation = try conversationService.createConversation(title: "Multi-Step Research")
        conversationId = conversation.id
        
        let config = await agentService.createAgentConfiguration(
            agentIds: [coordinator.id, webSearch.id],
            pattern: .orchestrator
        )
        
        var conv = try conversationService.loadConversation(id: conversationId)!
        conv.agentConfiguration = config
        try conversationService.updateConversation(conv)
        conv = try conversationService.loadConversation(id: conversationId)!
        
        var allResults: [AgentResult] = []
        
        // Step 1: Initial research
        let message1 = "Research Swift async/await patterns"
        let userMessage1 = Message(role: .user, content: message1)
        conv.messages.append(userMessage1)
        try await conversationService.addMessage(userMessage1, to: conversationId)
        
        let result1 = try await agentService.processMessage(
            message1,
            conversationId: conversationId,
            conversation: conv
        )
        allResults.append(result1)
        XCTAssertTrue(result1.success, "First research step should succeed")
        
        // Add assistant message
        let assistantMessage1 = Message(role: .assistant, content: result1.content, toolCalls: result1.toolCalls)
        conv.messages.append(assistantMessage1)
        try await conversationService.addMessage(assistantMessage1, to: conversationId)
        try conversationService.updateConversation(conv)
        
        // Reload to get updated conversation
        conv = try conversationService.loadConversation(id: conversationId)!
        
        // Step 2: Follow-up with context
        let message2 = "Based on what you found, provide a comprehensive guide with examples"
        let userMessage2 = Message(role: .user, content: message2)
        conv.messages.append(userMessage2)
        try await conversationService.addMessage(userMessage2, to: conversationId)
        
        let result2 = try await agentService.processMessage(
            message2,
            conversationId: conversationId,
            conversation: conv
        )
        
        // Add assistant message
        let assistantMessage2 = Message(role: .assistant, content: result2.content, toolCalls: result2.toolCalls)
        conv.messages.append(assistantMessage2)
        try await conversationService.addMessage(assistantMessage2, to: conversationId)
        try conversationService.updateConversation(conv)
        allResults.append(result2)
        XCTAssertTrue(result2.success, "Second step should succeed")
        
        // Reload to get final conversation state
        let finalConv = try conversationService.loadConversation(id: conversationId)!
        
        let contextVerification = OutputVerificationHelpers.verifyContextSharing(
            conversation: finalConv,
            messageIndex: finalConv.messages.count - 1,
            minContextReferences: 1
        )
        
        let toolVerification = OutputVerificationHelpers.verifyToolUsage(
            result: result1,
            expectedTools: ["duckduckgo_search"],
            allowPartial: true
        )
        
        let qualityVerification = OutputVerificationHelpers.verifyResponseQuality(
            result: result2,
            minLength: 50
        )
        
        let verificationResults: [String: VerificationResult] = [
            "context_sharing": contextVerification,
            "tool_usage": toolVerification,
            "response_quality": qualityVerification
        ]
        
        // Generate report
        let report = TestOutputFormatter.createReport(
            scenarioName: "Multi-Step Research",
            agents: [AgentName.webSearch, AgentName.coordinator],
            results: allResults,
            conversation: finalConv,
            verificationResults: verificationResults
        )
        
        let savedFiles = try TestOutputFormatter.saveReport(report, to: testOutputsDir!)
        print("✓ Report saved to: \(savedFiles.joined(separator: ", "))")
        
        XCTAssertTrue(qualityVerification.passed, "Quality: \(qualityVerification.message)")
    }
}
