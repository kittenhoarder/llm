//
//  Agent.swift
//  FoundationChatCore
//
//  Base protocol and infrastructure for agents
//

import Foundation
import FoundationModels

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
                    
                    // #region debug log
                    let logDataTools: [String: Any] = [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "A",
                        "location": "BaseAgent.swift:modelService",
                        "message": "Updating ModelService with tools",
                        "data": [
                            "agentName": agentName,
                            "toolsCount": tools.count,
                            "toolNames": tools.map { $0.name }
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: logDataTools),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        appendToDebugLog(jsonString)
                    }
                    // #endregion
                    
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
        
        var prompt = "Task: \(task.description)\n\n"
        
        if !optimizedMessages.isEmpty {
            prompt += "Conversation History:\n"
            // Use optimized messages (already compacted)
            for message in optimizedMessages.suffix(10) { // Use more messages since they're optimized
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


