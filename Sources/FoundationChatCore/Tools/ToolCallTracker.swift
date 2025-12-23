//
//  ToolCallTracker.swift
//  FoundationChatCore
//
//  Thread-safe tracker for tool invocations
//

import Foundation

/// Information about a tool call
@available(macOS 26.0, iOS 26.0, *)
struct ToolCallInfo: Sendable {
    let toolName: String
    let timestamp: Date
    let arguments: String?
    
    init(toolName: String, arguments: String? = nil) {
        self.toolName = toolName
        self.timestamp = Date()
        self.arguments = arguments
    }
}

/// Thread-safe actor for tracking tool calls per session
@available(macOS 26.0, iOS 26.0, *)
public actor ToolCallTracker {
    /// Active tool calls organized by session ID
    private var sessionCalls: [String: [ToolCallInfo]] = [:]
    
    /// Record a tool call for a session
    /// - Parameters:
    ///   - sessionId: Unique identifier for the session
    ///   - toolName: Name of the tool that was called
    ///   - arguments: Optional arguments string for debugging
    func recordCall(sessionId: String, toolName: String, arguments: String? = nil) {
        let callInfo = ToolCallInfo(toolName: toolName, arguments: arguments)
        if sessionCalls[sessionId] == nil {
            sessionCalls[sessionId] = []
        }
        sessionCalls[sessionId]?.append(callInfo)
    }
    
    /// Get unique tool names used in a session
    /// - Parameter sessionId: Session identifier
    /// - Returns: Array of unique tool names (in order of first use)
    func getUniqueToolNames(for sessionId: String) -> [String] {
        guard let calls = sessionCalls[sessionId] else {
            return []
        }
        
        // Return unique tool names in order of first appearance
        var seen = Set<String>()
        var unique: [String] = []
        for call in calls {
            if !seen.contains(call.toolName) {
                seen.insert(call.toolName)
                unique.append(call.toolName)
            }
        }
        return unique
    }
    
    /// Get all tool calls for a session
    /// - Parameter sessionId: Session identifier
    /// - Returns: Array of tool call information
    func getCalls(for sessionId: String) -> [ToolCallInfo] {
        return sessionCalls[sessionId] ?? []
    }
    
    /// Clear tracking for a session
    /// - Parameter sessionId: Session identifier
    func clearSession(_ sessionId: String) {
        sessionCalls[sessionId] = nil
    }
    
    /// Clear all sessions
    func clearAll() {
        sessionCalls.removeAll()
    }
}








