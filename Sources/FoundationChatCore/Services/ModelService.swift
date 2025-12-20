//
//  ModelService.swift
//  FoundationChatCore
//
//  Service for interacting with Apple's SystemLanguageModel
//

import Foundation
import FoundationModels

/// Availability status of the language model
@available(macOS 26.0, iOS 26.0, *)
public enum ModelAvailability: Sendable {
    case available
    case unavailable(UnavailabilityReason)
    
    public enum UnavailabilityReason: Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case other(String)
    }
}

/// Response from the model with streaming support
@available(macOS 26.0, iOS 26.0, *)
public struct ModelResponse: Sendable {
    /// Full content of the response
    public let content: String
    
    /// Tool calls made during generation (if any)
    public let toolCalls: [ToolCall]
    
    public init(content: String, toolCalls: [ToolCall] = []) {
        self.content = content
        self.toolCalls = toolCalls
    }
}

/// Service for managing interactions with Apple's SystemLanguageModel
@available(macOS 26.0, iOS 26.0, *)
public actor ModelService {
    /// The underlying language model
    private let model: SystemLanguageModel
    
    /// Current session with tools
    private var session: LanguageModelSession?
    
    /// Tool call tracker
    private let tracker = ToolCallTracker()
    
    /// Current session ID for tracking
    private var currentSessionId: String?
    
    /// Available tools (for fallback inference)
    private var tools: [any Tool] = []
    
    /// Sessions per conversation ID (for contextual conversations)
    private var conversationSessions: [UUID: LanguageModelSession] = [:]
    
    /// Context optimizer for managing token limits
    private let contextOptimizer = ContextOptimizer()
    
    /// Initialize the model service
    public init() {
        print("🤖 ModelService init() starting...")
        print("🤖 About to access SystemLanguageModel.default...")
        self.model = SystemLanguageModel.default
        print("✅ ModelService init() complete - SystemLanguageModel.default accessed")
    }
    
    /// Check if the model is available
    public func checkAvailability() -> ModelAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable(let reason):
            return .unavailable(.other(String(describing: reason)))
        @unknown default:
            return .unavailable(.other("Unknown availability status"))
        }
    }
    
    /// Update the tools available to the model
    /// - Parameter tools: Array of tools to make available
    public func updateTools(_ tools: [any Tool]) {
        // Store tools for fallback inference
        self.tools = tools
        
        // Generate a new session ID for tracking
        let sessionId = UUID().uuidString
        self.currentSessionId = sessionId
        
        print("[DEBUG ModelService] updateTools called with \(tools.count) tools, sessionId: \(sessionId)")
        
        // Wrap tools with tracking
        // Since we can't easily type-erase Tool with associated types,
        // we'll wrap known tool types specifically
        var trackedTools: [any Tool] = []
        for tool in tools {
            // For DuckDuckGoFoundationTool specifically
            if let ddgTool = tool as? DuckDuckGoFoundationTool {
                print("[DEBUG ModelService] Wrapping DuckDuckGoFoundationTool with tracking")
                let tracked = TrackedTool(wrapping: ddgTool, sessionId: sessionId, tracker: tracker)
                trackedTools.append(tracked)
                print("[DEBUG ModelService] Successfully wrapped tool: \(tracked.name)")
            } else if let webSearchTool = tool as? WebSearchFoundationTool {
                // Track web search tool
                print("[DEBUG ModelService] Wrapping WebSearchFoundationTool with tracking")
                let tracked = TrackedTool(wrapping: webSearchTool, sessionId: sessionId, tracker: tracker)
                trackedTools.append(tracked)
                print("[DEBUG ModelService] Successfully wrapped tool: \(tracked.name)")
            } else if let serpapiTool = tool as? SerpAPIFoundationTool {
                // Track SerpAPI tool
                print("[DEBUG ModelService] Wrapping SerpAPIFoundationTool with tracking")
                let tracked = TrackedTool(wrapping: serpapiTool, sessionId: sessionId, tracker: tracker)
                trackedTools.append(tracked)
                print("[DEBUG ModelService] Successfully wrapped tool: \(tracked.name)")
            } else {
                // For other tools, add them as-is (they won't be tracked)
                // TODO: Add tracking for other tool types as needed
                print("[DEBUG ModelService] Tool '\(tool.name)' not wrapped (unknown type)")
                trackedTools.append(tool)
            }
        }
        
        print("[DEBUG ModelService] Created LanguageModelSession with \(trackedTools.count) tools")
        self.session = LanguageModelSession(tools: trackedTools)
    }
    
    /// Send a message and get a response (non-streaming)
    /// - Parameter message: The user's message
    /// - Returns: The model's response
    /// - Throws: Error if model is unavailable or request fails
    public func respond(to message: String) async throws -> ModelResponse {
        guard let session = session, let sessionId = currentSessionId else {
            print("[DEBUG ModelService] No session or sessionId, using default session")
            let defaultSession = LanguageModelSession(tools: [])
            let response = try await defaultSession.respond(to: message)
            return ModelResponse(content: response.content)
        }
        
        print("[DEBUG ModelService] respond() called with sessionId: \(sessionId)")
        
        // Clear previous tool calls for this session before making the request
        await tracker.clearSession(sessionId)
        print("[DEBUG ModelService] Cleared previous tool calls for session")
        
        print("[DEBUG ModelService] Calling session.respond()...")
        let response = try await session.respond(to: message)
        print("[DEBUG ModelService] session.respond() completed")
        
        // Extract tool calls from tracker
        var toolNames = await tracker.getUniqueToolNames(for: sessionId)
        print("[DEBUG ModelService] Extracted \(toolNames.count) tool names from tracker: \(toolNames)")
        
        // Fallback: If no tools were tracked but we have tools available, try to infer from content
        if toolNames.isEmpty {
            let availableToolNames = tools.map { $0.name }
            let inferred = ToolUsageInference.inferToolUsage(from: response.content, availableTools: availableToolNames)
            if !inferred.isEmpty {
                print("[DEBUG ModelService] No tools tracked, but inferred \(inferred.count) tools from content: \(inferred)")
                toolNames = inferred
            }
        }
        
        let toolCalls = toolNames.map { toolName in
            ToolCall(toolName: toolName, arguments: "")
        }
        
        print("[DEBUG ModelService] Returning ModelResponse with \(toolCalls.count) tool calls")
        
        return ModelResponse(content: response.content, toolCalls: toolCalls)
    }
    
    /// Send a message with conversation context
    /// - Parameters:
    ///   - message: The user's message
    ///   - conversationId: The conversation ID for session management
    ///   - previousMessages: Previous messages in the conversation (for contextual mode)
    ///   - useContextual: Whether to use contextual conversations (reuse session)
    /// - Returns: The model's response
    /// - Throws: Error if model is unavailable or request fails
    public func respond(
        to message: String,
        conversationId: UUID,
        previousMessages: [Message],
        useContextual: Bool
    ) async throws -> ModelResponse {
        let session: LanguageModelSession
        let sessionId: String
        
        if useContextual {
            // Use or create session for this conversation
            if let existingSession = conversationSessions[conversationId] {
                session = existingSession
                sessionId = currentSessionId ?? UUID().uuidString
                print("[DEBUG ModelService] Reusing session for conversation \(conversationId)")
            } else {
                // Create new session from transcript if we have previous messages
                if !previousMessages.isEmpty {
                    // Optimize context before creating transcript
                    let optimized = try await contextOptimizer.optimizeContext(
                        messages: previousMessages,
                        systemPrompt: nil,
                        tools: tools
                    )
                    
                    print("[DEBUG ModelService] Context optimized: \(optimized.messagesTruncated) messages truncated, \(optimized.tokenUsage.totalTokens) tokens used")
                    
                    let transcript = createTranscript(from: optimized.messages)
                    let trackedTools = createTrackedTools()
                    session = LanguageModelSession(tools: trackedTools, transcript: transcript)
                    sessionId = UUID().uuidString
                    currentSessionId = sessionId
                    conversationSessions[conversationId] = session
                    print("[DEBUG ModelService] Created new session from transcript for conversation \(conversationId)")
                } else {
                    // No previous messages, create fresh session
                    let trackedTools = createTrackedTools()
                    session = LanguageModelSession(tools: trackedTools)
                    sessionId = UUID().uuidString
                    currentSessionId = sessionId
                    conversationSessions[conversationId] = session
                    print("[DEBUG ModelService] Created new session for conversation \(conversationId)")
                }
            }
        } else {
            // Non-contextual: create new session each time
            let trackedTools = createTrackedTools()
            session = LanguageModelSession(tools: trackedTools)
            sessionId = UUID().uuidString
            currentSessionId = sessionId
            print("[DEBUG ModelService] Created new session (non-contextual mode)")
        }
        
        // Clear previous tool calls for this session before making the request
        await tracker.clearSession(sessionId)
        
        // Make the request
        let response = try await session.respond(to: message)
        
        // Update session in storage if contextual
        if useContextual {
            conversationSessions[conversationId] = session
        }
        
        // Extract tool calls from tracker
        var toolNames = await tracker.getUniqueToolNames(for: sessionId)
        
        // Fallback: If no tools were tracked but we have tools available, try to infer from content
        if toolNames.isEmpty {
            let availableToolNames = tools.map { $0.name }
            let inferred = ToolUsageInference.inferToolUsage(from: response.content, availableTools: availableToolNames)
            if !inferred.isEmpty {
                toolNames = inferred
            }
        }
        
        let toolCalls = toolNames.map { toolName in
            ToolCall(toolName: toolName, arguments: "")
        }
        
        return ModelResponse(content: response.content, toolCalls: toolCalls)
    }
    
    /// Clear session for a conversation
    /// - Parameter conversationId: The conversation ID
    public func clearSession(for conversationId: UUID) {
        conversationSessions.removeValue(forKey: conversationId)
        print("[DEBUG ModelService] Cleared session for conversation \(conversationId)")
    }
    
    // MARK: - Private Helpers
    
    private func createTrackedTools() -> [any Tool] {
        guard let sessionId = currentSessionId else {
            return tools
        }
        
        var trackedTools: [any Tool] = []
        for tool in tools {
            if let ddgTool = tool as? DuckDuckGoFoundationTool {
                let tracked = TrackedTool(wrapping: ddgTool, sessionId: sessionId, tracker: tracker)
                trackedTools.append(tracked)
            } else if let webSearchTool = tool as? WebSearchFoundationTool {
                // Track web search tool
                let tracked = TrackedTool(wrapping: webSearchTool, sessionId: sessionId, tracker: tracker)
                trackedTools.append(tracked)
                print("[DEBUG ModelService] Wrapping WebSearchFoundationTool with tracking")
            } else {
                trackedTools.append(tool)
            }
        }
        return trackedTools
    }
    
    private func createTranscript(from messages: [Message]) -> Transcript {
        var entries: [Transcript.Entry] = []
        
        for message in messages {
            switch message.role {
            case .user:
                // Create a Transcript.Prompt with text segment
                let textSegment = Transcript.TextSegment(content: message.content)
                let prompt = Transcript.Prompt(segments: [.text(textSegment)])
                entries.append(.prompt(prompt))
            case .assistant:
                // Create a Transcript.Response with text segment
                let textSegment = Transcript.TextSegment(content: message.content)
                let response = Transcript.Response(assetIDs: [], segments: [.text(textSegment)])
                entries.append(.response(response))
            case .system:
                // System messages are treated as prompts
                let textSegment = Transcript.TextSegment(content: message.content)
                let prompt = Transcript.Prompt(segments: [.text(textSegment)])
                entries.append(.prompt(prompt))
            }
        }
        
        return Transcript(entries: entries)
    }
    
    /// Send a message and stream the response
    /// - Parameter message: The user's message
    /// - Returns: Async sequence of response chunks
    /// - Throws: Error if model is unavailable or request fails
    /// Note: Streaming implementation will be added once the FoundationModels API is confirmed
    public func streamResponse(to message: String) async throws -> AsyncThrowingStream<String, Error> {
        // For now, return the full response as a single chunk
        // TODO: Implement proper streaming when FoundationModels streaming API is available
        let response = try await respond(to: message)
        return AsyncThrowingStream { continuation in
            continuation.yield(response.content)
            continuation.finish()
        }
    }
    
    /// Get a user-friendly error message for unavailability
    /// - Parameter availability: The availability status
    /// - Returns: Human-readable error message
    public static func errorMessage(for availability: ModelAvailability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled. Please enable it in Settings."
        case .unavailable(.modelNotReady):
            return "Model is not ready. It may be downloading or the system is busy."
        case .unavailable(.other(let reason)):
            return "Model unavailable: \(reason)"
        }
    }
}

