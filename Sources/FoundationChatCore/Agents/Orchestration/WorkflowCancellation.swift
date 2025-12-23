//
//  WorkflowCancellation.swift
//  FoundationChatCore
//
//  Workflow cancellation and modification support
//

import Foundation

/// Cancellation token for workflow execution
@available(macOS 26.0, iOS 26.0, *)
public final class WorkflowCancellationToken: @unchecked Sendable {
    /// Whether cancellation has been requested
    private var _isCancelled: Bool = false
    private let lock = NSLock()
    
    /// Cancellation reason
    private var _reason: String?
    
    public init() {}
    
    /// Check if cancellation has been requested
    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }
    
    /// Get cancellation reason
    public var reason: String? {
        lock.lock()
        defer { lock.unlock() }
        return _reason
    }
    
    /// Request cancellation
    /// - Parameter reason: Optional reason for cancellation
    public func cancel(reason: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        _isCancelled = true
        _reason = reason
    }
    
    /// Reset cancellation state (for resuming)
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _isCancelled = false
        _reason = nil
    }
    
    /// Throw if cancelled
    /// - Throws: WorkflowCancellationError if cancelled
    public func checkCancellation() throws {
        if isCancelled {
            throw WorkflowCancellationError.cancelled(reason: reason)
        }
    }
}

/// Cancellation error
@available(macOS 26.0, iOS 26.0, *)
public enum WorkflowCancellationError: Error, Sendable {
    case cancelled(reason: String?)
    
    public var localizedDescription: String {
        switch self {
        case .cancelled(let reason):
            return reason ?? "Workflow was cancelled"
        }
    }
}


