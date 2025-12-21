//
//  TaskDecomposition.swift
//  FoundationChatCore
//
//  Models for representing decomposed tasks and subtasks
//

import Foundation

/// Represents a single subtask within a decomposed task
@available(macOS 26.0, iOS 26.0, *)
public struct DecomposedSubtask: Sendable, Identifiable, Codable {
    /// Unique identifier for this subtask
    public let id: UUID
    
    /// The specific subtask description
    public let description: String
    
    /// Suggested agent name (optional)
    public let agentName: String?
    
    /// Required capabilities for this subtask
    public let requiredCapabilities: Set<AgentCapability>
    
    /// Execution priority/order (lower numbers execute first)
    public let priority: Int
    
    /// Subtask IDs this depends on (for sequencing)
    public let dependencies: [UUID]
    
    /// Whether this can run alongside other subtasks
    public let canExecuteInParallel: Bool
    
    /// Rough estimate for budget planning
    public let estimatedTokenCost: Int?
    
    public init(
        id: UUID = UUID(),
        description: String,
        agentName: String? = nil,
        requiredCapabilities: Set<AgentCapability> = [],
        priority: Int = 0,
        dependencies: [UUID] = [],
        canExecuteInParallel: Bool = true,
        estimatedTokenCost: Int? = nil
    ) {
        self.id = id
        self.description = description
        self.agentName = agentName
        self.requiredCapabilities = requiredCapabilities
        self.priority = priority
        self.dependencies = dependencies
        self.canExecuteInParallel = canExecuteInParallel
        self.estimatedTokenCost = estimatedTokenCost
    }
}

/// Represents a complete task decomposition with subtasks and execution order
@available(macOS 26.0, iOS 26.0, *)
public struct TaskDecomposition: Sendable, Codable {
    /// All subtasks in this decomposition
    public let subtasks: [DecomposedSubtask]
    
    /// Sum of all subtask token estimates
    public let totalEstimatedTokens: Int
    
    /// Ordered list of subtask IDs for execution
    public let executionOrder: [UUID]
    
    /// Mapping of subtask ID to subtask for quick lookup
    public var subtasksById: [UUID: DecomposedSubtask] {
        Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, $0) })
    }
    
    public init(
        subtasks: [DecomposedSubtask],
        totalEstimatedTokens: Int? = nil,
        executionOrder: [UUID]? = nil
    ) {
        self.subtasks = subtasks
        self.totalEstimatedTokens = totalEstimatedTokens ?? subtasks.compactMap { $0.estimatedTokenCost }.reduce(0, +)
        self.executionOrder = executionOrder ?? subtasks.map { $0.id }
    }
    
    /// Get a subtask by ID
    public func getSubtask(byId id: UUID) -> DecomposedSubtask? {
        return subtasksById[id]
    }
    
    /// Get subtasks that can be executed in parallel (no dependencies on each other)
    public func getParallelizableGroups() -> [[DecomposedSubtask]] {
        var groups: [[DecomposedSubtask]] = []
        var processed: Set<UUID> = []
        
        // Build dependency graph
        let dependencyMap = Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, Set($0.dependencies)) })
        
        // Find all subtasks with no unprocessed dependencies
        func findReadySubtasks() -> [DecomposedSubtask] {
            return subtasks.filter { subtask in
                guard !processed.contains(subtask.id) else { return false }
                guard subtask.canExecuteInParallel else { return false }
                
                // Check if all dependencies are processed
                let deps = dependencyMap[subtask.id] ?? []
                return deps.allSatisfy { processed.contains($0) }
            }
        }
        
        // Group subtasks by dependency level
        while processed.count < subtasks.count {
            let ready = findReadySubtasks()
            guard !ready.isEmpty else {
                // If no parallelizable tasks, process remaining sequentially
                let remaining = subtasks.filter { !processed.contains($0.id) }
                if !remaining.isEmpty {
                    groups.append(remaining)
                }
                break
            }
            
            groups.append(ready)
            processed.formUnion(ready.map { $0.id })
        }
        
        return groups
    }
}

/// Metrics about delegation performance
@available(macOS 26.0, iOS 26.0, *)
public struct DelegationMetrics: Sendable, Codable {
    /// Number of subtasks created
    public let subtasksCreated: Int
    
    /// Number of subtasks pruned
    public let subtasksPruned: Int
    
    /// Number of agents used
    public let agentsUsed: Int
    
    /// Total tokens used
    public let totalTokens: Int
    
    /// Token savings percentage vs single-agent approach
    public let tokenSavingsPercentage: Double
    
    /// Execution time breakdown (in seconds)
    public let executionTimeBreakdown: ExecutionTimeBreakdown
    
    public init(
        subtasksCreated: Int,
        subtasksPruned: Int,
        agentsUsed: Int,
        totalTokens: Int,
        tokenSavingsPercentage: Double,
        executionTimeBreakdown: ExecutionTimeBreakdown
    ) {
        self.subtasksCreated = subtasksCreated
        self.subtasksPruned = subtasksPruned
        self.agentsUsed = agentsUsed
        self.totalTokens = totalTokens
        self.tokenSavingsPercentage = tokenSavingsPercentage
        self.executionTimeBreakdown = executionTimeBreakdown
    }
}

/// Execution time breakdown for delegation
@available(macOS 26.0, iOS 26.0, *)
public struct ExecutionTimeBreakdown: Sendable, Codable {
    /// Time spent in coordinator analysis
    public let coordinatorAnalysisTime: TimeInterval
    
    /// Time spent in coordinator synthesis
    public let coordinatorSynthesisTime: TimeInterval
    
    /// Time spent executing specialized agents
    public let specializedAgentsTime: TimeInterval
    
    /// Total execution time
    public var totalTime: TimeInterval {
        coordinatorAnalysisTime + coordinatorSynthesisTime + specializedAgentsTime
    }
    
    public init(
        coordinatorAnalysisTime: TimeInterval = 0,
        coordinatorSynthesisTime: TimeInterval = 0,
        specializedAgentsTime: TimeInterval = 0
    ) {
        self.coordinatorAnalysisTime = coordinatorAnalysisTime
        self.coordinatorSynthesisTime = coordinatorSynthesisTime
        self.specializedAgentsTime = specializedAgentsTime
    }
}

/// Detailed token usage breakdown for an agent
@available(macOS 26.0, iOS 26.0, *)
public struct AgentTokenUsage: Sendable {
    /// Input prompt tokens
    public let inputTokens: Int
    
    /// Response/output tokens
    public let outputTokens: Int
    
    /// Tool call tokens (input + output)
    public let toolCallTokens: Int
    
    /// Context tokens (conversation history, file references, etc.)
    public let contextTokens: Int
    
    /// Total tokens
    public var totalTokens: Int {
        inputTokens + outputTokens + toolCallTokens + contextTokens
    }
    
    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        toolCallTokens: Int = 0,
        contextTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.toolCallTokens = toolCallTokens
        self.contextTokens = contextTokens
    }
}

