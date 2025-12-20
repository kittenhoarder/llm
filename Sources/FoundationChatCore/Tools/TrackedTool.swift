//
//  TrackedTool.swift
//  FoundationChatCore
//
//  Wrapper that tracks tool invocations while delegating to the wrapped tool
//

import Foundation
import FoundationModels

/// Wraps a tool to track its invocations
/// This is a generic wrapper that works with any Tool type
@available(macOS 26.0, iOS 26.0, *)
public struct TrackedTool<T: Tool>: Tool, Sendable where T: Sendable {
    public typealias Output = T.Output
    public typealias Arguments = T.Arguments
    
    /// The wrapped tool
    private let wrappedTool: T
    
    /// The tool's name (delegated from wrapped tool)
    public var name: String {
        wrappedTool.name
    }
    
    /// The tool's description (delegated from wrapped tool)
    public var description: String {
        wrappedTool.description
    }
    
    /// The tool's parameters schema (delegated from wrapped tool)
    public var parameters: GenerationSchema {
        wrappedTool.parameters
    }
    
    /// Session ID for tracking
    private let sessionId: String
    
    /// Tracker instance
    private let tracker: ToolCallTracker
    
    /// Initialize a tracked tool
    /// - Parameters:
    ///   - tool: The tool to wrap
    ///   - sessionId: Unique session identifier
    ///   - tracker: The tracker instance
    public init(wrapping tool: T, sessionId: String, tracker: ToolCallTracker) {
        self.wrappedTool = tool
        self.sessionId = sessionId
        self.tracker = tracker
    }
    
    /// Call the wrapped tool and record the invocation
    /// - Parameter arguments: Tool arguments
    /// - Returns: Tool output
    /// - Throws: Any error from the wrapped tool
    public func call(arguments: T.Arguments) async throws -> T.Output {
        // DEBUG: Log that the tracked tool is being called
        print("[DEBUG TrackedTool] Tool '\(name)' called with sessionId: \(sessionId)")
        
        // Record the tool call
        await tracker.recordCall(
            sessionId: sessionId,
            toolName: name,
            arguments: formatArguments(arguments)
        )
        
        print("[DEBUG TrackedTool] Tool call recorded for '\(name)'")
        
        // Delegate to wrapped tool
        let result = try await wrappedTool.call(arguments: arguments)
        
        let resultString = String(describing: result)
        print("[DEBUG TrackedTool] Tool '\(name)' completed, result length: \(resultString.count)")
        // Show first 200 chars of result for debugging
        let preview = resultString.count > 200 ? String(resultString.prefix(200)) + "..." : resultString
        print("[DEBUG TrackedTool] Tool result preview: \(preview)")
        
        return result
    }
    
    /// Format arguments for logging (optional, for debugging)
    private func formatArguments(_ arguments: T.Arguments) -> String? {
        // Try to convert arguments to a readable string
        if let codable = arguments as? any Codable {
            if let data = try? JSONEncoder().encode(codable),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return String(describing: arguments)
    }
}

/// Helper to wrap tools with tracking
@available(macOS 26.0, iOS 26.0, *)
public func wrapToolWithTracking<T: Tool>(_ tool: T, sessionId: String, tracker: ToolCallTracker) -> TrackedTool<T> where T: Sendable {
    return TrackedTool(wrapping: tool, sessionId: sessionId, tracker: tracker)
}

