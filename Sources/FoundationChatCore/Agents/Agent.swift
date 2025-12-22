//
//  Agent.swift
//  FoundationChatCore
//
//  Base protocol and infrastructure for agents
//

import Foundation
import FoundationModels

/// Base protocol that all agents must conform to
@available(macOS 26.0, iOS 26.0, *)
public protocol Agent: Sendable {
    /// Unique identifier for this agent
    var id: UUID { get }
    
    /// Human-readable name of the agent
    var name: String { get }
    
    /// Description of what this agent does
    var description: String { get }
    
    /// Capabilities this agent has
    var capabilities: Set<AgentCapability> { get }
    
    /// Process a task and return a result
    /// - Parameters:
    ///   - task: The task to process
    ///   - context: Shared context available to all agents
    /// - Returns: Result of processing the task
    func process(task: AgentTask, context: AgentContext) async throws -> AgentResult
}

/// Base implementation providing common functionality for agents
@available(macOS 26.0, iOS 26.0, *)
public class BaseAgent: Agent, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let capabilities: Set<AgentCapability>
    
    /// Model service for this agent (lazy initialization to avoid blocking)
    private var _modelService: ModelService?
    internal var modelService: ModelService {
        get async {
            if _modelService == nil {
                let agentName = self.name
                print("🤖 BaseAgent '\(agentName)' creating ModelService lazily...")
                
                // Create ModelService off the main thread to avoid blocking
                _modelService = await Task.detached(priority: .userInitiated) {
                    print("🤖 BaseAgent '\(agentName)' Creating ModelService in detached task...")
                    let service = ModelService()
                    print("✅ BaseAgent '\(agentName)' ModelService created in detached task")
                    return service
                }.value
                
                print("✅ BaseAgent '\(agentName)' ModelService created and assigned")
                
                // Update tools after creating service
                if !tools.isEmpty {
                    print("🤖 BaseAgent '\(agentName)' updating tools...")
                    
                    // Debug logging
                    await DebugLogger.shared.log(
                        location: "BaseAgent.swift:modelService",
                        message: "Updating ModelService with tools",
                        hypothesisId: "A",
                        data: [
                            "agentName": agentName,
                            "toolsCount": tools.count,
                            "toolNames": tools.map { $0.name }
                        ]
                    )
                    
                    await _modelService!.updateTools(tools)
                    print("✅ BaseAgent '\(agentName)' tools updated")
                }
            }
            return _modelService!
        }
    }
    
    /// Tools available to this agent
    private var tools: [any Tool] = []
    
    /// Initialize a base agent
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Agent name
    ///   - description: Agent description
    ///   - capabilities: Agent capabilities
    ///   - tools: Tools to make available to this agent
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        capabilities: Set<AgentCapability>,
        tools: [any Tool] = []
    ) {
        print("🤖 BaseAgent '\(name)' init starting (no ModelService created yet)...")
        self.id = id
        self.name = name
        self.description = description
        self.capabilities = capabilities
        self.tools = tools
        print("✅ BaseAgent '\(name)' init complete (ModelService will be created lazily)")
    }
    
    /// Update the tools available to this agent
    /// - Parameter newTools: New tools to add
    public func updateTools(_ newTools: [any Tool]) {
        self.tools = newTools
        Task {
            let service = await modelService
            await service.updateTools(newTools)
        }
    }
    
    /// Process a task using the agent's model service
    /// - Parameters:
    ///   - task: The task to process
    ///   - context: Shared context
    /// - Returns: Result of processing
    public func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        print("🤖 BaseAgent '\(name)' process() called for task: \(task.description.prefix(50))...")
        
        // Build a prompt that includes context (now async)
        print("🤖 BaseAgent '\(name)' building prompt...")
        let prompt = try await buildPrompt(from: task, context: context)
        print("✅ BaseAgent '\(name)' prompt built")
        
        // Get response from model (lazy ModelService creation)
        print("🤖 BaseAgent '\(name)' accessing modelService (may create it)...")
        let service = await modelService
        print("✅ BaseAgent '\(name)' modelService obtained, calling respond()...")
        let response = try await service.respond(to: prompt)
        print("✅ BaseAgent '\(name)' got response")
        
        // Create result
        return AgentResult(
            agentId: id,
            taskId: task.id,
            content: response.content,
            success: true,
            toolCalls: response.toolCalls,
            updatedContext: context
        )
    }
    
    /// Build a prompt from task and context
    /// - Parameters:
    ///   - task: The task
    ///   - context: The context
    /// - Returns: Formatted prompt string
    private func buildPrompt(from task: AgentTask, context: AgentContext) async throws -> String {
        let contextOptimizer = ContextOptimizer()
        let tokenCounter = TokenCounter()
        
        // Calculate available tokens for the prompt (reserve for system, tools, output)
        let maxPromptTokens = 3500 // Reserve ~600 tokens for system/tools/output
        let systemAndToolTokens = 200 // Rough estimate for system prompt and tool definitions
        let outputReserve = 500
        let availableForContent = maxPromptTokens - systemAndToolTokens - outputReserve
        
        // Optimize conversation history if present
        var optimizedMessages = context.conversationHistory
        if !optimizedMessages.isEmpty {
            let optimized = try await contextOptimizer.optimizeContext(
                messages: optimizedMessages,
                systemPrompt: nil,
                tools: tools
            )
            optimizedMessages = optimized.messages
        }
        
        // Count tokens for conversation history
        let historyTokens = await tokenCounter.countTokens(optimizedMessages)
        
        // Truncate task description if needed to fit within token budget
        var taskDescription = task.description
        let taskTokens = await tokenCounter.countTokens(taskDescription)
        let availableForTask = max(100, availableForContent - historyTokens) // At least 100 tokens for task
        
        if taskTokens > availableForTask {
            // Truncate task description
            let maxChars = availableForTask * 4 // Rough char-to-token conversion
            let truncated = String(taskDescription.prefix(maxChars))
            taskDescription = truncated + "\n\n[Message truncated due to length. Full content available in conversation history.]"
            print("⚠️ Agent '\(name)': Truncated task description from \(taskTokens) to ~\(availableForTask) tokens")
        }
        
        var prompt = "Task: \(taskDescription)\n\n"
        
        if !optimizedMessages.isEmpty {
            prompt += "Conversation History:\n"
            // Use optimized messages (already compacted)
            for message in optimizedMessages.suffix(AppConstants.optimizedMessagesCount) {
                prompt += "\(message.role.rawValue.capitalized): \(message.content)\n"
            }
            prompt += "\n"
        }
        
        if !context.fileReferences.isEmpty {
            prompt += "Available Files: \(context.fileReferences.joined(separator: ", "))\n\n"
        }
        
        if !context.toolResults.isEmpty {
            prompt += "Previous Results:\n"
            for (key, value) in context.toolResults {
                prompt += "- \(key): \(value)\n"
            }
            prompt += "\n"
        }
        
        prompt += "Please process this task and provide a response."
        
        return prompt
    }
}


