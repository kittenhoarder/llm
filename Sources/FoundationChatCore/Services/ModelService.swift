//
//  ModelService.swift
//  FoundationChatCore
//
//  Service for interacting with Apple's SystemLanguageModel
//

import Foundation
import FoundationModels
import UniformTypeIdentifiers

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
    
    /// Tool call tracker
    private let tracker = ToolCallTracker()
    
    /// Available tools (for fallback inference)
    private var tools: [any Tool] = []
    
    /// Sessions per conversation ID (for contextual conversations)
    private var conversationSessions: [UUID: LanguageModelSession] = [:]
    
    /// Session IDs per conversation (for tracking tool calls in contextual conversations)
    private var conversationSessionIds: [UUID: String] = [:]
    
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
    /// Note: Tools are stored and will be used when creating request-scoped sessions.
    /// Session creation happens at request time, not during tool configuration.
    public func updateTools(_ tools: [any Tool]) {
        // Store tools for use in request-scoped sessions
        self.tools = tools
        print("[DEBUG ModelService] updateTools called with \(tools.count) tools")
    }
    
    /// Send a message with image attachments and get a response
    /// - Parameters:
    ///   - message: The user's message text
    ///   - imagePaths: Array of image file paths to include
    /// - Returns: The model's response
    /// - Throws: Error if model is unavailable or request fails
    /// Note: This method handles images by including them in the prompt.
    /// The exact API for image segments may need adjustment based on FoundationModels implementation.
    /// This method creates a request-scoped session for each call to support parallel execution.
    public func respond(to message: String, withImages imagePaths: [String]) async throws -> ModelResponse {
        // Create a request-scoped session for this request
        let requestSessionId = UUID().uuidString
        let requestSession = createRequestSession(sessionId: requestSessionId)
        
        print("[DEBUG ModelService] respond(withImages:) called with \(imagePaths.count) images, sessionId: \(requestSessionId)")
        
        // Clear previous tool calls for this session before making the request
        await tracker.clearSession(requestSessionId)
        
        // For now, include image references in the text message
        // TODO: Update to use proper Transcript.ImageSegment when API is confirmed
        let imageRefs = imagePaths.map { "[Image file: \(URL(fileURLWithPath: $0).lastPathComponent)]" }.joined(separator: "\n")
        let fullMessage = "\(message)\n\nAttached images:\n\(imageRefs)"
        
        print("[DEBUG ModelService] Calling session.respond() with image references...")
        let response = try await requestSession.respond(to: fullMessage)
        print("[DEBUG ModelService] session.respond() completed")
        
        // Extract tool calls from tracker using the session ID
        var toolNames = await tracker.getUniqueToolNames(for: requestSessionId)
        
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
    
    /// Send a message and get a response (non-streaming)
    /// - Parameter message: The user's message
    /// - Returns: The model's response
    /// - Throws: Error if model is unavailable or request fails
    /// Note: This method creates a request-scoped session for each call to support parallel execution.
    public func respond(to message: String) async throws -> ModelResponse {
        // #region debug log
        await DebugLogger.shared.log(
            location: "ModelService.swift:respond",
            message: "respond() called - entering",
            hypothesisId: "F",
            data: ["hasTools": !tools.isEmpty, "toolCount": tools.count]
        )
        // #endregion
        
        // Create a request-scoped session for this request
        // This ensures thread safety when multiple requests run in parallel
        let requestSessionId = UUID().uuidString
        let requestSession = createRequestSession(sessionId: requestSessionId)
        
        print("[DEBUG ModelService] Created request-scoped session (sessionId: \(requestSessionId))")
        
        // Clear previous tool calls for this session before making the request
        await tracker.clearSession(requestSessionId)
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "ModelService.swift:respond",
            message: "About to call session.respond()",
            hypothesisId: "F",
            data: ["sessionId": requestSessionId]
        )
        // #endregion
        
        print("[DEBUG ModelService] Calling session.respond()...")
        let response = try await requestSession.respond(to: message)
        print("[DEBUG ModelService] session.respond() completed")
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "ModelService.swift:respond",
            message: "session.respond() completed successfully",
            hypothesisId: "F",
            data: ["sessionId": requestSessionId]
        )
        // #endregion
        
        // Extract tool calls from tracker using the session ID
        var toolNames = await tracker.getUniqueToolNames(for: requestSessionId)
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
    /// Note: This method manages conversation-scoped sessions for contextual conversations.
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
            if let existingSession = conversationSessions[conversationId],
               let existingSessionId = conversationSessionIds[conversationId] {
                session = existingSession
                sessionId = existingSessionId
                print("[DEBUG ModelService] Reusing session for conversation \(conversationId)")
            } else {
                // Create new session from transcript if we have previous messages
                sessionId = UUID().uuidString
                conversationSessionIds[conversationId] = sessionId
                
                if !previousMessages.isEmpty {
                    // Optimize context before creating transcript
                    let optimized = try await contextOptimizer.optimizeContext(
                        messages: previousMessages,
                        systemPrompt: nil,
                        tools: tools
                    )
                    
                    print("[DEBUG ModelService] Context optimized: \(optimized.messagesTruncated) messages truncated, \(optimized.tokenUsage.totalTokens) tokens used")
                    
                    let transcript = createTranscript(from: optimized.messages)
                    let trackedTools = createTrackedTools(for: sessionId)
                    session = LanguageModelSession(tools: trackedTools, transcript: transcript)
                    conversationSessions[conversationId] = session
                    print("[DEBUG ModelService] Created new session from transcript for conversation \(conversationId)")
                } else {
                    // No previous messages, create fresh session
                    let trackedTools = createTrackedTools(for: sessionId)
                    session = LanguageModelSession(tools: trackedTools)
                    conversationSessions[conversationId] = session
                    print("[DEBUG ModelService] Created new session for conversation \(conversationId)")
                }
            }
        } else {
            // Non-contextual: create new session each time (request-scoped)
            sessionId = UUID().uuidString
            session = createRequestSession(sessionId: sessionId)
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
        conversationSessionIds.removeValue(forKey: conversationId)
        print("[DEBUG ModelService] Cleared session for conversation \(conversationId)")
    }
    
    // MARK: - Private Helpers
    
    /// Create a request-scoped session with tracked tools
    /// - Parameter sessionId: Session ID for tool tracking
    /// - Returns: A new LanguageModelSession configured with tracked tools
    private func createRequestSession(sessionId: String) -> LanguageModelSession {
        let trackedTools = createTrackedTools(for: sessionId)
        return LanguageModelSession(tools: trackedTools)
    }
    
    /// Create tracked tools for a given session ID
    /// - Parameter sessionId: Session ID for tool tracking
    /// - Returns: Array of tools with tracking wrappers where applicable
    private func createTrackedTools(for sessionId: String) -> [any Tool] {
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
            } else if let serpapiTool = tool as? SerpAPIFoundationTool {
                // Track SerpAPI tool
                let tracked = TrackedTool(wrapping: serpapiTool, sessionId: sessionId, tracker: tracker)
                trackedTools.append(tracked)
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
                // Create segments for this prompt
                var segments: [Transcript.Segment] = []
                
                // Add text segment if there's content
                if !message.content.isEmpty {
                    let textSegment = Transcript.TextSegment(content: message.content)
                    segments.append(.text(textSegment))
                }
                
                // Add image segments for any image attachments
                // Note: Image segment support will be added when FoundationModels API is confirmed
                // For now, we include image references in the text content
                var imageReferences: [String] = []
                for attachment in message.attachments {
                    // Check if attachment is an image
                    if let mimeType = attachment.mimeType,
                       let utType = UTType(mimeType: mimeType),
                       utType.conforms(to: UTType.image) {
                        imageReferences.append(attachment.originalName)
                    }
                }
                
                // If we have image references but no text content, add them to the text
                if !imageReferences.isEmpty && message.content.isEmpty {
                    let imageText = "Images attached: \(imageReferences.joined(separator: ", "))"
                    let textSegment = Transcript.TextSegment(content: imageText)
                    segments.append(.text(textSegment))
                } else if !imageReferences.isEmpty {
                    // Append image references to existing content
                    let combinedContent = "\(message.content)\n\n[Images: \(imageReferences.joined(separator: ", "))]"
                    // Replace the text segment with the combined content
                    segments.removeAll { if case .text = $0 { return true } else { return false } }
                    let textSegment = Transcript.TextSegment(content: combinedContent)
                    segments.append(.text(textSegment))
                }
                
                // If no segments were created, add an empty text segment
                if segments.isEmpty {
                    let textSegment = Transcript.TextSegment(content: message.content.isEmpty ? "" : message.content)
                    segments.append(.text(textSegment))
                }
                
                let prompt = Transcript.Prompt(segments: segments)
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

