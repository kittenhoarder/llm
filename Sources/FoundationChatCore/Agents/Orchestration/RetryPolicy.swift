//
//  RetryPolicy.swift
//  FoundationChatCore
//
//  Retry policies for failed subtask execution
//

import Foundation

/// Retry policy strategies for handling failed subtasks
@available(macOS 26.0, iOS 26.0, *)
public enum RetryPolicy: Sendable, Codable {
    /// No retries - fail immediately
    case none
    
    /// Fixed retry policy with constant delay
    /// - maxAttempts: Maximum number of retry attempts (including initial attempt)
    /// - delay: Fixed delay in seconds between retries
    case fixed(maxAttempts: Int, delay: TimeInterval)
    
    /// Exponential backoff retry policy
    /// - maxAttempts: Maximum number of retry attempts (including initial attempt)
    /// - initialDelay: Initial delay in seconds, doubles after each retry
    case exponential(maxAttempts: Int, initialDelay: TimeInterval)
    
    /// Default retry policy (no retries)
    public static let `default`: RetryPolicy = .none
    
    /// Get the delay for a specific retry attempt
    /// - Parameter attemptNumber: The retry attempt number (0 = initial attempt, 1 = first retry, etc.)
    /// - Returns: Delay in seconds before the next attempt
    public func delay(for attemptNumber: Int) -> TimeInterval {
        switch self {
        case .none:
            return 0
        case .fixed(_, let delay):
            return delay
        case .exponential(_, let initialDelay):
            // Exponential backoff: initialDelay * 2^attemptNumber
            return initialDelay * pow(2.0, Double(attemptNumber))
        }
    }
    
    /// Check if another retry attempt should be made
    /// - Parameter attemptNumber: Current attempt number (0 = initial attempt)
    /// - Returns: True if another retry should be attempted
    public func shouldRetry(attemptNumber: Int) -> Bool {
        switch self {
        case .none:
            return false
        case .fixed(let maxAttempts, _):
            return attemptNumber < maxAttempts - 1
        case .exponential(let maxAttempts, _):
            return attemptNumber < maxAttempts - 1
        }
    }
    
    /// Get the maximum number of attempts
    public var maxAttempts: Int {
        switch self {
        case .none:
            return 1
        case .fixed(let maxAttempts, _):
            return maxAttempts
        case .exponential(let maxAttempts, _):
            return maxAttempts
        }
    }
}

/// Retry configuration for different agent capabilities
@available(macOS 26.0, iOS 26.0, *)
public struct RetryConfiguration: Sendable, Codable {
    /// Default retry policy
    public let defaultPolicy: RetryPolicy
    
    /// Per-capability retry policies
    public let capabilityPolicies: [AgentCapability: RetryPolicy]
    
    /// Per-agent retry policies (by agent name)
    public let agentPolicies: [String: RetryPolicy]
    
    public init(
        defaultPolicy: RetryPolicy = .default,
        capabilityPolicies: [AgentCapability: RetryPolicy] = [:],
        agentPolicies: [String: RetryPolicy] = [:]
    ) {
        self.defaultPolicy = defaultPolicy
        self.capabilityPolicies = capabilityPolicies
        self.agentPolicies = agentPolicies
    }
    
    /// Get retry policy for a specific agent and subtask
    /// - Parameters:
    ///   - agent: The agent executing the subtask
    ///   - subtask: The subtask being executed
    /// - Returns: The appropriate retry policy
    public func policy(for agent: any Agent, subtask: DecomposedSubtask) -> RetryPolicy {
        // Check agent-specific policy first
        if let agentPolicy = agentPolicies[agent.name] {
            return agentPolicy
        }
        
        // Check capability-specific policy
        for capability in subtask.requiredCapabilities {
            if let capabilityPolicy = capabilityPolicies[capability] {
                return capabilityPolicy
            }
        }
        
        // Fall back to default
        return defaultPolicy
    }
}

/// Retry attempt information
@available(macOS 26.0, iOS 26.0, *)
public struct RetryAttempt: Sendable, Codable {
    /// Attempt number (0 = initial attempt, 1 = first retry, etc.)
    public let attemptNumber: Int
    
    /// Timestamp of this attempt
    public let timestamp: Date
    
    /// Error from this attempt (if failed)
    public let error: String?
    
    /// Delay before this attempt (in seconds)
    public let delayBeforeAttempt: TimeInterval
    
    public init(
        attemptNumber: Int,
        timestamp: Date = Date(),
        error: String? = nil,
        delayBeforeAttempt: TimeInterval = 0
    ) {
        self.attemptNumber = attemptNumber
        self.timestamp = timestamp
        self.error = error
        self.delayBeforeAttempt = delayBeforeAttempt
    }
}


