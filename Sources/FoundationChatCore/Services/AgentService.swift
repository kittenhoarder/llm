//
//  AgentService.swift
//  FoundationChatCore
//
//  High-level service for agent operations and lifecycle management
//

import Foundation

/// Service for managing agent operations
@available(macOS 26.0, iOS 26.0, *)
public actor AgentService {
    /// Shared singleton instance
    public static let shared = AgentService()
    
    /// Agent registry
    private let registry: AgentRegistry
    
    /// Agent orchestrator
    private let orchestrator: AgentOrchestrator
    
    /// Active agent contexts per conversation
    private var conversationContexts: [UUID: AgentContext] = [:]
    
    /// Track initialization state to prevent race conditions
    private var isInitializing = false
    private var initializationTask: Task<Void, Never>?
    
    /// Helper function to append log entry to debug.log file
    private func appendToDebugLog(_ jsonString: String) {
        let logPath = "/Users/owenperry/dev/llm/.cursor/debug.log"
        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
            fileHandle.seekToEndOfFile()
            if let data = (jsonString + "\n").data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // File doesn't exist, create it
            try? (jsonString + "\n").write(toFile: logPath, atomically: false, encoding: .utf8)
        }
    }
    
    /// Initialize the agent service
    /// - Parameters:
    ///   - registry: Agent registry (defaults to shared)
    ///   - orchestrator: Agent orchestrator
    public init(
        registry: AgentRegistry = .shared,
        orchestrator: AgentOrchestrator? = nil
    ) {
        print("🤖 AgentService init() starting...")
        self.registry = registry
        self.orchestrator = orchestrator ?? AgentOrchestrator(registry: registry)
        print("✅ AgentService init() complete (agents will be initialized lazily via ensureAgentsInitialized())")
    }
    
    /// Initialize default agents
    private func initializeDefaultAgents() async {
        print("🤖 Registering FileReaderAgent...")
        await registry.register(FileReaderAgent())
        print("✅ FileReaderAgent registered")
        
        print("🤖 Registering WebSearchAgent...")
        await registry.register(WebSearchAgent())
        print("✅ WebSearchAgent registered")
        
        print("🤖 Registering CodeAnalysisAgent...")
        await registry.register(CodeAnalysisAgent())
        print("✅ CodeAnalysisAgent registered")
        
        print("🤖 Registering DataAnalysisAgent...")
        await registry.register(DataAnalysisAgent())
        print("✅ DataAnalysisAgent registered")
        
        // Create a coordinator agent
        // **Status**: ⚠️ Basic Agent - No special tools, just general reasoning
        // Used for orchestrating multi-agent workflows
        print("🤖 Creating coordinator agent...")
        let coordinator = BaseAgent(
            name: "Coordinator",
            description: "Coordinates tasks and delegates to specialized agents",
            capabilities: [.generalReasoning]
        )
        print("✅ Coordinator agent created, registering...")
        await registry.register(coordinator)
        print("✅ Coordinator registered")
        
        // Set default pattern
        print("🤖 Setting default orchestration pattern...")
        if let coordinatorAgent = await registry.getAgent(byId: coordinator.id) {
            await orchestrator.setPattern(OrchestratorPattern(coordinator: coordinatorAgent))
            print("✅ Orchestration pattern set")
        }
        print("✅ All default agents initialized")
    }
    
    /// Process a message in an agent conversation
    /// - Parameters:
    ///   - message: User message
    ///   - conversationId: Conversation ID
    ///   - conversation: The conversation
    ///   - tokenBudget: Optional token budget constraint
    /// - Returns: Agent result
    public func processMessage(
        _ message: String,
        conversationId: UUID,
        conversation: Conversation,
        tokenBudget: Int? = nil
    ) async throws -> AgentResult {
        print("🤖 AgentService.processMessage() called with message: \(message.prefix(50))...")
        
        // Get or create context for this conversation
        var context = conversationContexts[conversationId] ?? AgentContext()
        print("🤖 Context obtained")
        
        // Update context with conversation history
        context.conversationHistory = conversation.messages
        print("🤖 Conversation history updated (\(conversation.messages.count) messages)")
        
        // Create task
        let task = AgentTask(
            description: message,
            requiredCapabilities: extractRequiredCapabilities(from: message),
            parameters: [:]
        )
        print("🤖 Task created with capabilities: \(task.requiredCapabilities)")
        
        // Get agent configuration
        guard let config = conversation.agentConfiguration else {
            print("❌ No agent configuration found")
            throw AgentServiceError.noAgentConfiguration
        }
        print("🤖 Agent configuration found: \(config.selectedAgents.count) agents selected")
        
        // Execute task
        print("🤖 Calling orchestrator.execute()...")
        let result = try await orchestrator.execute(
            task: task,
            context: context,
            agentIds: config.selectedAgents.isEmpty ? nil : config.selectedAgents
        )
        print("✅ Orchestrator.execute() completed")
        
        // Extract and log token usage from result
        if let updated = result.updatedContext {
            // Log detailed token breakdown
            if let coordinatorInput = updated.metadata["tokens_\(result.agentId.uuidString.prefix(8))_input"],
               let coordinatorOutput = updated.metadata["tokens_\(result.agentId.uuidString.prefix(8))_output"],
               let totalTokens = updated.metadata["tokens_total_task"],
               let savings = updated.metadata["tokens_saved_vs_single_agent"] {
                print("📊 AgentService: Token breakdown:")
                print("  - Coordinator input: \(coordinatorInput) tokens")
                print("  - Coordinator output: \(coordinatorOutput) tokens")
                print("  - Total tokens: \(totalTokens)")
                print("  - Token savings: \(savings)%")
            }
            
            // Check budget if provided
            if let budget = tokenBudget,
               let totalStr = updated.metadata["tokens_total_task"],
               let total = Int(totalStr) {
                if total > budget {
                    print("⚠️ AgentService: Token usage (\(total)) exceeds budget (\(budget))")
                } else if Double(total) >= Double(budget) * 0.8 {
                    print("⚠️ AgentService: Approaching token budget (\(total)/\(budget))")
                }
            }
            
            conversationContexts[conversationId] = updated
            
            // Store total token usage in conversation metadata (if conversation supports it)
            // Note: This would require updating Conversation model to support metadata
        }
        
        return result
    }
    
    /// Process a message with a single agent (no orchestrator)
    /// This is used when orchestrator mode is disabled - direct single-agent processing
    /// - Parameters:
    ///   - message: User message
    ///   - agentId: Selected agent ID
    ///   - conversationId: Conversation ID
    ///   - conversation: The conversation
    /// - Returns: Agent result
    public func processSingleAgentMessage(
        _ message: String,
        agentId: UUID,
        conversationId: UUID,
        conversation: Conversation,
        fileReferences: [String] = []
    ) async throws -> AgentResult {
        print("🤖 AgentService.processSingleAgentMessage() called for agent: \(agentId)")
        
        // #region debug log
        let allAgents = await registry.listAll()
        let agentInfo = allAgents.map { ["id": $0.id.uuidString, "name": $0.name] }
        let logData: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A",
            "location": "AgentService.swift:processSingleAgentMessage",
            "message": "Looking up agent by ID",
            "data": [
                "requestedAgentId": agentId.uuidString,
                "availableAgents": agentInfo,
                "availableAgentIds": allAgents.map { $0.id.uuidString },
                "agentCount": allAgents.count
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
        // Get the agent from registry
        // Note: Agent IDs may change on app restart, so we need to handle ID mismatches
        var agent = await registry.getAgent(byId: agentId)
        
        // If agent not found by ID, this likely means agent IDs changed on app restart.
        // In single-agent mode with exactly one selected agent, we can safely use the first
        // available specialized agent (excluding Coordinator) as a fallback.
        if agent == nil {
            print("⚠️ Agent not found by ID: \(agentId) - IDs may have changed on app restart")
            print("⚠️ Attempting fallback resolution for single-agent mode...")
            
            // Get all available agents (excluding Coordinator for single-agent mode)
            let availableAgents = allAgents.filter { $0.name != "Coordinator" }
            
            // For single-agent mode, if there's exactly one specialized agent available,
            // use it as a fallback. This handles the common case where only one agent is enabled.
            if availableAgents.count == 1, let fallbackAgent = availableAgents.first {
                agent = fallbackAgent
                print("✅ Resolved to single available agent: \(fallbackAgent.name)")
            } else if !availableAgents.isEmpty {
                // Multiple agents available - try to match by checking which agent was likely intended
                // Check if conversation config has hints about which agent to use
                // For now, prefer WebSearchAgent if available (common use case)
                agent = availableAgents.first { $0.capabilities.contains(.webSearch) }
                if agent == nil {
                    // Fallback to first available agent
                    agent = availableAgents.first
                }
                if let resolvedAgent = agent {
                    print("⚠️ Using fallback agent resolution: \(resolvedAgent.name)")
                }
            }
        }
        
        guard let resolvedAgent = agent else {
            print("❌ Agent not found: \(agentId) and could not resolve to any available agent")
            
            // #region debug log
            let logData2: [String: Any] = [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "A",
                "location": "AgentService.swift:processSingleAgentMessage",
                "message": "Agent lookup failed and resolution failed",
                "data": [
                    "requestedAgentId": agentId.uuidString,
                    "availableAgentIds": allAgents.map { $0.id.uuidString },
                    "availableAgentNames": allAgents.map { $0.name },
                    "matchFound": false
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: logData2),
               let jsonString2 = String(data: jsonData, encoding: .utf8) {
                appendToDebugLog(jsonString2)
            }
            // #endregion
            
            throw AgentServiceError.agentNotFound(agentId)
        }
        
        print("✅ Agent found: \(resolvedAgent.name)")
        
        // Get or create context for this conversation
        var context = conversationContexts[conversationId] ?? AgentContext()
        
        // Update context with conversation history
        context.conversationHistory = conversation.messages
        
        // Add file references from attachments in recent messages and from parameter
        var allFileReferences = fileReferences
        for message in conversation.messages.suffix(10) {
            allFileReferences.append(contentsOf: message.attachments.map { $0.sandboxPath })
        }
        context.fileReferences = Array(Set(allFileReferences)) // Remove duplicates
        
        print("🤖 Conversation history updated (\(conversation.messages.count) messages)")
        print("🤖 File references: \(context.fileReferences.count) files")
        
        // Create a simple task for the agent
        let task = AgentTask(
            description: message,
            requiredCapabilities: [],
            parameters: [:]
        )
        
        // Process the task directly with the agent (no orchestration)
        print("🤖 Processing task directly with agent: \(resolvedAgent.name)...")
        
        // #region debug log
        let logDataProcess: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "E",
            "location": "AgentService.swift:processSingleAgentMessage",
            "message": "About to call agent.process()",
            "data": [
                "agentId": resolvedAgent.id.uuidString,
                "agentName": resolvedAgent.name,
                "taskDescription": task.description,
                "taskParameters": task.parameters,
                "contextHistoryCount": context.conversationHistory.count
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logDataProcess),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
        let result = try await resolvedAgent.process(task: task, context: context)
        print("✅ Agent processing completed")
        
        // #region debug log
        let logDataResult: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "E",
            "location": "AgentService.swift:processSingleAgentMessage",
            "message": "Agent.process() completed",
            "data": [
                "agentId": resolvedAgent.id.uuidString,
                "agentName": resolvedAgent.name,
                "resultSuccess": result.success,
                "resultContentLength": result.content.count,
                "resultToolCallsCount": result.toolCalls.count,
                "resultToolCalls": result.toolCalls.map { ["toolName": $0.toolName, "arguments": $0.arguments] }
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logDataResult),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
        // Update conversation context
        if let updated = result.updatedContext {
            conversationContexts[conversationId] = updated
        }
        
        return result
    }
    
    /// Get available agents
    /// - Returns: Array of all registered agents
    public func getAvailableAgents() async -> [any Agent] {
        print("🔧 getAvailableAgents() called...")
        // Ensure agents are initialized (idempotent)
        await ensureAgentsInitialized()
        let agents = await registry.listAll()
        print("🔧 Returning \(agents.count) agents")
        return agents
    }
    
    /// Ensure agents are initialized (idempotent)
    private func ensureAgentsInitialized() async {
        // Check if already initialized
        let existing = await registry.listAll()
        if !existing.isEmpty {
            print("🔧 Agents already initialized (\(existing.count) found)")
            return
        }
        
        // Check if initialization is in progress
        if isInitializing {
            print("🔧 Agent initialization already in progress, waiting...")
            // Wait for the existing initialization task to complete
            if let task = initializationTask {
                await task.value
            }
            return
        }
        
        // Start initialization
        isInitializing = true
        print("🔧 No agents found, initializing...")
        
        let task = Task {
            await initializeDefaultAgents()
            isInitializing = false
        }
        
        initializationTask = task
        await task.value
    }
    
    /// Get agents by capability
    /// - Parameter capability: The capability
    /// - Returns: Array of agents with that capability
    public func getAgents(byCapability capability: AgentCapability) async -> [any Agent] {
        return await registry.getAgents(byCapability: capability)
    }
    
    /// Create a new agent conversation configuration
    /// - Parameters:
    ///   - agentIds: Selected agent IDs
    ///   - pattern: Orchestration pattern
    /// - Returns: Agent configuration
    public func createAgentConfiguration(
        agentIds: [UUID],
        pattern: OrchestrationPatternType = .orchestrator
    ) async -> AgentConfiguration {
        // Validate agent IDs
        let validIds = await validateAgentIds(agentIds)
        
        return AgentConfiguration(
            selectedAgents: validIds,
            orchestrationPattern: pattern,
            agentSettings: [:]
        )
    }
    
    /// Validate agent IDs
    /// - Parameter ids: Agent IDs to validate
    /// - Returns: Valid agent IDs
    private func validateAgentIds(_ ids: [UUID]) async -> [UUID] {
        var validIds: [UUID] = []
        
        for id in ids {
            if await registry.getAgent(byId: id) != nil {
                validIds.append(id)
            }
        }
        
        return validIds
    }
    
    /// Clear context for a conversation
    /// - Parameter conversationId: Conversation ID
    public func clearContext(for conversationId: UUID) {
        conversationContexts.removeValue(forKey: conversationId)
    }
    
    /// Extract required capabilities from a message
    /// - Parameter message: The message
    /// - Returns: Set of required capabilities
    private func extractRequiredCapabilities(from message: String) -> Set<AgentCapability> {
        let lowercased = message.lowercased()
        var capabilities: Set<AgentCapability> = []
        
        // Simple keyword-based detection
        if lowercased.contains("file") || lowercased.contains("read") || lowercased.contains("document") {
            capabilities.insert(.fileReading)
        }
        
        if lowercased.contains("search") || lowercased.contains("look up") || lowercased.contains("find") {
            capabilities.insert(.webSearch)
        }
        
        if lowercased.contains("code") || lowercased.contains("analyze") || lowercased.contains("swift") {
            capabilities.insert(.codeAnalysis)
        }
        
        if lowercased.contains("data") || lowercased.contains("calculate") || lowercased.contains("statistics") {
            capabilities.insert(.dataAnalysis)
        }
        
        return capabilities
    }
}

/// Errors for agent service
@available(macOS 26.0, iOS 26.0, *)
public enum AgentServiceError: Error, Sendable {
    case noAgentConfiguration
    case agentNotFound(UUID)
    case invalidConfiguration
    case executionFailed(String)
}





