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
    
    /// Initialize the agent service
    /// - Parameters:
    ///   - registry: Agent registry (defaults to shared)
    ///   - orchestrator: Agent orchestrator
    public init(
        registry: AgentRegistry = .shared,
        orchestrator: AgentOrchestrator? = nil
    ) {
        Log.debug("🤖 AgentService init() starting...")
        self.registry = registry
        self.orchestrator = orchestrator ?? AgentOrchestrator(registry: registry)
        Log.debug("✅ AgentService init() complete (agents will be initialized lazily via ensureAgentsInitialized())")
    }
    
    /// Initialize default agents
    private func initializeDefaultAgents() async {
        Log.debug("🤖 Registering FileReaderAgent...")
        await registry.register(FileReaderAgent())
        Log.debug("✅ FileReaderAgent registered")
        
        Log.debug("🤖 Registering WebSearchAgent...")
        await registry.register(WebSearchAgent())
        Log.debug("✅ WebSearchAgent registered")
        
        Log.debug("🤖 Registering CodeAnalysisAgent...")
        await registry.register(CodeAnalysisAgent())
        Log.debug("✅ CodeAnalysisAgent registered")
        
        Log.debug("🤖 Registering DataAnalysisAgent...")
        await registry.register(DataAnalysisAgent())
        Log.debug("✅ DataAnalysisAgent registered")
        
        Log.debug("🤖 Registering VisionAgent...")
        await registry.register(VisionAgent())
        Log.debug("✅ VisionAgent registered")
        
        // Create a coordinator agent
        // **Status**: ⚠️ Basic Agent - No special tools, just general reasoning
        // Used for orchestrating multi-agent workflows
        Log.debug("🤖 Creating coordinator agent...")
        let coordinator = BaseAgent(
            id: AgentId.coordinator,
            name: AgentName.coordinator,
            description: "Coordinates tasks and delegates to specialized agents",
            capabilities: [.generalReasoning]
        )
        Log.debug("✅ Coordinator agent created, registering...")
        await registry.register(coordinator)
        Log.debug("✅ Coordinator registered")
        
        // Set default pattern
        Log.debug("🤖 Setting default orchestration pattern...")
        if let coordinatorAgent = await registry.getAgent(byId: coordinator.id) {
            await orchestrator.setPattern(OrchestratorPattern(coordinator: coordinatorAgent))
            Log.debug("✅ Orchestration pattern set")
        }
        Log.debug("✅ All default agents initialized")
    }
    
    /// Process a message in an agent conversation
    /// - Parameters:
    ///   - message: User message
    ///   - conversationId: Conversation ID
    ///   - conversation: The conversation
    ///   - tokenBudget: Optional token budget constraint
    ///   - progressTracker: Optional progress tracker for visualization
    /// - Returns: Agent result
    public func processMessage(
        _ message: String,
        conversationId: UUID,
        conversation: Conversation,
        tokenBudget: Int? = nil,
        progressTracker: OrchestrationProgressTracker? = nil
    ) async throws -> AgentResult {
        Log.debug("🤖 AgentService.processMessage() called with message: \(message.prefix(50))...")
        
        let baseContext = conversationContexts[conversationId] ?? AgentContext()
        let context = await ContextAssemblyService.shared.assemble(
            baseContext: baseContext,
            conversationId: conversationId,
            conversation: conversation,
            currentMessage: message
        )
        
        Log.debug("🤖 Conversation history updated (\(context.conversationHistory.count) messages from \(conversation.messages.count) total)")
        Log.debug("🤖 File references: \(context.fileReferences.count) files")
        
        // Create task
        let task = AgentTask(
            description: message,
            requiredCapabilities: extractRequiredCapabilities(from: message),
            parameters: [:]
        )
        Log.debug("🤖 Task created with capabilities: \(task.requiredCapabilities)")
        
        // Get agent configuration
        guard let config = conversation.agentConfiguration else {
            Log.error("❌ No agent configuration found")
            throw AgentServiceError.noAgentConfiguration
        }
        Log.debug("🤖 Agent configuration found: \(config.selectedAgents.count) agents selected")
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "AgentService.swift:processMessage",
            message: "About to call orchestrator.execute()",
            hypothesisId: "A,D",
            data: [
                "selectedAgentCount": config.selectedAgents.count,
                "selectedAgentIds": config.selectedAgents.map { $0.uuidString },
                "willPassAgentIds": config.selectedAgents.isEmpty ? "nil" : "array"
            ]
        )
        // #endregion
        
        // Execute task
        Log.debug("🤖 Calling orchestrator.execute()...")
        let result = try await orchestrator.execute(
            task: task,
            context: context,
            agentIds: config.selectedAgents.isEmpty ? nil : config.selectedAgents,
            progressTracker: progressTracker
        )
        Log.debug("✅ Orchestrator.execute() completed")
        
        // Extract and log token usage from result
        if let updated = result.updatedContext {
            // Log detailed token breakdown
            if let coordinatorInput = updated.metadata["tokens_\(result.agentId.uuidString.prefix(8))_input"],
               let coordinatorOutput = updated.metadata["tokens_\(result.agentId.uuidString.prefix(8))_output"],
               let totalTokens = updated.metadata["tokens_total_task"],
               let savings = updated.metadata["tokens_saved_vs_single_agent"] {
                Log.debug("📊 AgentService: Token breakdown:")
                Log.debug("  - Coordinator input: \(coordinatorInput) tokens")
                Log.debug("  - Coordinator output: \(coordinatorOutput) tokens")
                Log.debug("  - Total tokens: \(totalTokens)")
                Log.debug("  - Token savings: \(savings)%")
            }
            
            // Check budget if provided
            if let budget = tokenBudget,
               let totalStr = updated.metadata["tokens_total_task"],
               let total = Int(totalStr) {
                if total > budget {
                    Log.warn("⚠️ AgentService: Token usage (\(total)) exceeds budget (\(budget))")
                } else if Double(total) >= Double(budget) * 0.8 {
                    Log.warn("⚠️ AgentService: Approaching token budget (\(total)/\(budget))")
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
        Log.debug("🤖 AgentService.processSingleAgentMessage() called for agent: \(agentId)")
        
        // Resolve agent (with fallback logic for ID mismatches)
        let resolvedAgent = try await resolveAgent(byId: agentId)
        
        Log.debug("✅ Agent found: \(resolvedAgent.name)")
        
        let baseContext = conversationContexts[conversationId] ?? AgentContext()
        let context = await ContextAssemblyService.shared.assemble(
            baseContext: baseContext,
            conversationId: conversationId,
            conversation: conversation,
            fileReferences: fileReferences,
            currentMessage: message
        )
        
        Log.debug("🤖 Conversation history updated (\(context.conversationHistory.count) messages from \(conversation.messages.count) total)")
        Log.debug("🤖 File references: \(context.fileReferences.count) files")
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "AgentService.swift:processSingleAgentMessage",
            message: "Context built for agent",
            hypothesisId: "A",
            data: [
                "agentId": agentId.uuidString,
                "agentName": resolvedAgent.name,
                "fileReferencesCount": context.fileReferences.count,
                "fileReferences": context.fileReferences,
                "message": message
            ]
        )
        // #endregion
        
        // Create a simple task for the agent
        let task = AgentTask(
            description: message,
            requiredCapabilities: [],
            parameters: [:]
        )
        
        // Process the task directly with the agent (no orchestration)
        Log.debug("🤖 Processing task directly with agent: \(resolvedAgent.name)...")
        
        // Debug logging
        await logAgentProcessing(agent: resolvedAgent, task: task, context: context)
        
        let result = try await resolvedAgent.process(task: task, context: context)
        Log.debug("✅ Agent processing completed")
        
        // Debug logging for result
        await logAgentResult(agent: resolvedAgent, result: result)
        
        // Update conversation context
        if let updated = result.updatedContext {
            conversationContexts[conversationId] = updated
        }
        
        return result
    }
    
    /// Get available agents
    /// - Returns: Array of all registered agents
    public func getAvailableAgents() async -> [any Agent] {
        Log.debug("🔧 getAvailableAgents() called...")
        // Ensure agents are initialized (idempotent)
        await ensureAgentsInitialized()
        let agents = await registry.listAll()
        Log.debug("🔧 Returning \(agents.count) agents")
        return agents
    }
    
    /// Check if all default agents are registered
    private func hasAllDefaultAgents() async -> Bool {
        let expectedAgentNames: Set<String> = [
            AgentName.fileReader,
            AgentName.webSearch,
            AgentName.codeAnalysis,
            AgentName.dataAnalysis,
            AgentName.visionAgent,
            AgentName.coordinator
        ]
        
        let existing = await registry.listAll()
        let existingNames = Set(existing.map { $0.name })
        
        let hasAll = expectedAgentNames.isSubset(of: existingNames)
        if !hasAll {
            let missing = expectedAgentNames.subtracting(existingNames)
            Log.warn("⚠️ Missing agents: \(missing.joined(separator: ", "))")
        }
        return hasAll
    }
    
    /// Ensure agents are initialized (idempotent)
    private func ensureAgentsInitialized() async {
        // Check if all expected agents are already initialized
        if await hasAllDefaultAgents() {
            let existing = await registry.listAll()
            Log.debug("🔧 All default agents already initialized (\(existing.count) found)")
            return
        }
        
        // Check if initialization is in progress
        if isInitializing {
            Log.debug("🔧 Agent initialization already in progress, waiting...")
            // Wait for the existing initialization task to complete
            if let task = initializationTask {
                await task.value
            }
            // After waiting, check again if all agents are present
            if await hasAllDefaultAgents() {
                return
            }
            // If still missing, continue to initialize
        }
        
        // Start initialization
        isInitializing = true
        let existing = await registry.listAll()
        Log.debug("🔧 Initializing default agents (currently \(existing.count) agents found)...")
        
        let task = Task {
            await initializeDefaultAgents()
            isInitializing = false
        }
        
        initializationTask = task
        await task.value
        
        // Verify all agents were registered
        if await hasAllDefaultAgents() {
            let final = await registry.listAll()
            Log.debug("✅ All default agents initialized (\(final.count) agents)")
        } else {
            Log.warn("⚠️ Warning: Some agents may not have been initialized")
        }
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
    
    // MARK: - Helper Methods
    
    // Context assembly is handled by ContextAssemblyService.
    
    /// Resolve agent by ID with fallback logic
    /// - Parameter agentId: Agent ID to resolve
    /// - Returns: Resolved agent
    /// - Throws: AgentServiceError if agent cannot be resolved
    private func resolveAgent(byId agentId: UUID) async throws -> any Agent {
        let allAgents = await registry.listAll()
        
        // Debug logging for agent lookup
        await logAgentLookup(agentId: agentId, availableAgents: allAgents)
        
        // Get the agent from registry
        // Note: Agent IDs may change on app restart, so we need to handle ID mismatches
        var agent = await registry.getAgent(byId: agentId)
        
        // If agent not found by ID, this likely means agent IDs changed on app restart.
        // In single-agent mode with exactly one selected agent, we can safely use the first
        // available specialized agent (excluding Coordinator) as a fallback.
        if agent == nil {
            Log.warn("⚠️ Agent not found by ID: \(agentId) - IDs may have changed on app restart")
            Log.warn("⚠️ Attempting fallback resolution for single-agent mode...")
            
            // Get all available agents (excluding Coordinator for single-agent mode)
            let availableAgents = allAgents.filter { $0.name != AgentName.coordinator }
            
            // For single-agent mode, if there's exactly one specialized agent available,
            // use it as a fallback. This handles the common case where only one agent is enabled.
            if availableAgents.count == 1, let fallbackAgent = availableAgents.first {
                agent = fallbackAgent
                Log.debug("✅ Resolved to single available agent: \(fallbackAgent.name)")
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
                    Log.warn("⚠️ Using fallback agent resolution: \(resolvedAgent.name)")
                }
            }
        }
        
        guard let resolvedAgent = agent else {
            Log.error("❌ Agent not found: \(agentId) and could not resolve to any available agent")
            
            // Debug logging for failed lookup
            await logAgentLookupFailed(agentId: agentId, availableAgents: allAgents)
            
            throw AgentServiceError.agentNotFound(agentId)
        }
        
        return resolvedAgent
    }
    
    /// Log agent lookup for debugging
    /// - Parameters:
    ///   - agentId: Requested agent ID
    ///   - availableAgents: Available agents
    private func logAgentLookup(agentId: UUID, availableAgents: [any Agent]) async {
        let agentInfo = availableAgents.map { ["id": $0.id.uuidString, "name": $0.name] }
        await DebugLogger.shared.log(
            location: "AgentService.swift:processSingleAgentMessage",
            message: "Looking up agent by ID",
            hypothesisId: "A",
            data: [
                "requestedAgentId": agentId.uuidString,
                "availableAgents": agentInfo,
                "availableAgentIds": availableAgents.map { $0.id.uuidString },
                "agentCount": availableAgents.count
            ]
        )
    }
    
    /// Log failed agent lookup for debugging
    /// - Parameters:
    ///   - agentId: Requested agent ID
    ///   - availableAgents: Available agents
    private func logAgentLookupFailed(agentId: UUID, availableAgents: [any Agent]) async {
        await DebugLogger.shared.log(
            location: "AgentService.swift:processSingleAgentMessage",
            message: "Agent lookup failed and resolution failed",
            hypothesisId: "A",
            data: [
                "requestedAgentId": agentId.uuidString,
                "availableAgentIds": availableAgents.map { $0.id.uuidString },
                "availableAgentNames": availableAgents.map { $0.name },
                "matchFound": false
            ]
        )
    }
    
    /// Log agent processing for debugging
    /// - Parameters:
    ///   - agent: The agent being processed
    ///   - task: The task being processed
    ///   - context: The context being used
    private func logAgentProcessing(agent: any Agent, task: AgentTask, context: AgentContext) async {
        await DebugLogger.shared.log(
            location: "AgentService.swift:processSingleAgentMessage",
            message: "About to call agent.process()",
            hypothesisId: "E",
            data: [
                "agentId": agent.id.uuidString,
                "agentName": agent.name,
                "taskDescription": task.description,
                "taskParameters": task.parameters,
                "contextHistoryCount": context.conversationHistory.count
            ]
        )
    }
    
    /// Log agent result for debugging
    /// - Parameters:
    ///   - agent: The agent that processed
    ///   - result: The result
    private func logAgentResult(agent: any Agent, result: AgentResult) async {
        await DebugLogger.shared.log(
            location: "AgentService.swift:processSingleAgentMessage",
            message: "Agent.process() completed",
            hypothesisId: "E",
            data: [
                "agentId": agent.id.uuidString,
                "agentName": agent.name,
                "resultSuccess": result.success,
                "resultContentLength": result.content.count,
                "resultToolCallsCount": result.toolCalls.count,
                "resultToolCalls": result.toolCalls.map { ["toolName": $0.toolName, "arguments": $0.arguments] }
            ]
        )
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
