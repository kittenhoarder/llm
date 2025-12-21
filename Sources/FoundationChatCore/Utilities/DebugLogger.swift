//
//  DebugLogger.swift
//  FoundationChatCore
//
//  Centralized debug logging utility
//

import Foundation

/// Utility for debug logging throughout the application
@available(macOS 26.0, iOS 26.0, *)
public actor DebugLogger {
    /// Shared singleton instance
    public static let shared = DebugLogger()
    
    /// Default debug log path (relative to workspace root)
    private let defaultLogPath: String
    
    /// Current session ID
    private var sessionId: String = "debug-session"
    
    /// Current run ID
    private var runId: String = "run1"
    
    /// Initialize the debug logger
    private init() {
        // Default to workspace-relative path
        // This can be overridden via environment variable or configuration
        if let workspacePath = ProcessInfo.processInfo.environment["WORKSPACE_PATH"] {
            self.defaultLogPath = "\(workspacePath)/.cursor/debug.log"
        } else {
            // Fallback to hardcoded path (for development)
            self.defaultLogPath = "/Users/owenperry/dev/llm/.cursor/debug.log"
        }
    }
    
    /// Configure session and run IDs
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - runId: Run identifier
    public func configure(sessionId: String, runId: String) {
        self.sessionId = sessionId
        self.runId = runId
    }
    
    /// Log a debug entry
    /// - Parameters:
    ///   - location: File and function location (e.g., "AgentService.swift:processMessage")
    ///   - message: Log message
    ///   - hypothesisId: Optional hypothesis identifier
    ///   - data: Optional data dictionary
    ///   - logPath: Optional custom log path (defaults to configured path)
    public func log(
        location: String,
        message: String,
        hypothesisId: String? = nil,
        data: [String: Any]? = nil,
        logPath: String? = nil
    ) {
        let logData: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId ?? "A",
            "location": location,
            "message": message,
            "data": data ?? [:],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: logData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let path = logPath ?? defaultLogPath
        appendToDebugLog(jsonString, path: path)
    }
    
    /// Append a JSON string to the debug log file
    /// - Parameters:
    ///   - jsonString: JSON string to append
    ///   - path: Path to the log file
    private func appendToDebugLog(_ jsonString: String, path: String) {
        if let fileHandle = FileHandle(forWritingAtPath: path) {
            fileHandle.seekToEndOfFile()
            if let data = (jsonString + "\n").data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            // File doesn't exist, create it
            try? (jsonString + "\n").write(toFile: path, atomically: false, encoding: .utf8)
        }
    }
}


