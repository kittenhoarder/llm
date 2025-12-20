//
//  DynamicPruner.swift
//  FoundationChatCore
//
//  Dynamic pruning of redundant subtasks to save tokens
//

import Foundation

/// Result of pruning operation
@available(macOS 26.0, iOS 26.0, *)
public struct PruningResult: Sendable {
    /// The pruned task decomposition
    public let decomposition: TaskDecomposition
    
    /// Rationale for each removed subtask
    public let removalRationales: [UUID: String]
    
    public init(decomposition: TaskDecomposition, removalRationales: [UUID: String] = [:]) {
        self.decomposition = decomposition
        self.removalRationales = removalRationales
    }
}

/// Dynamic pruner for removing redundant subtasks
@available(macOS 26.0, iOS 26.0, *)
public actor DynamicPruner {
    /// Similarity threshold for considering subtasks as duplicates (0.0 to 1.0)
    private let similarityThreshold: Double
    
    public init(similarityThreshold: Double = 0.7) {
        self.similarityThreshold = similarityThreshold
    }
    
    /// Prune redundant subtasks from decomposition
    /// - Parameters:
    ///   - decomposition: The original task decomposition
    ///   - tokenBudget: Optional token budget constraint
    /// - Returns: Pruned decomposition with removal rationales
    public func prune(_ decomposition: TaskDecomposition, tokenBudget: Int? = nil) -> PruningResult {
        print("✂️ DynamicPruner: Starting pruning of \(decomposition.subtasks.count) subtasks...")
        
        var subtasks = decomposition.subtasks
        var removalRationales: [UUID: String] = [:]
        var removedCount = 0
        
        // Step 1: Remove exact duplicates
        var seenDescriptions: Set<String> = []
        subtasks = subtasks.filter { subtask in
            let normalized = normalizeDescription(subtask.description)
            if seenDescriptions.contains(normalized) {
                removalRationales[subtask.id] = "Duplicate of another subtask"
                removedCount += 1
                return false
            }
            seenDescriptions.insert(normalized)
            return true
        }
        
        // Step 2: Merge similar subtasks
        var mergedSubtasks: [DecomposedSubtask] = []
        var processed: Set<UUID> = []
        
        for subtask in subtasks {
            guard !processed.contains(subtask.id) else { continue }
            
            // Find similar subtasks
            var similar: [DecomposedSubtask] = [subtask]
            for other in subtasks {
                guard other.id != subtask.id,
                      !processed.contains(other.id),
                      areSimilar(subtask, other) else { continue }
                
                similar.append(other)
                processed.insert(other.id)
                removalRationales[other.id] = "Merged with similar subtask: \(subtask.description.prefix(50))"
                removedCount += 1
            }
            
            // Merge similar subtasks into one
            if similar.count > 1 {
                let merged = mergeSubtasks(similar)
                mergedSubtasks.append(merged)
            } else {
                mergedSubtasks.append(subtask)
            }
            
            processed.insert(subtask.id)
        }
        
        subtasks = mergedSubtasks
        
        // Step 3: Remove low-value subtasks (very short or vague descriptions)
        subtasks = subtasks.filter { subtask in
            let description = subtask.description.trimmingCharacters(in: .whitespaces)
            if description.count < 10 {
                removalRationales[subtask.id] = "Subtask description too vague or short"
                removedCount += 1
                return false
            }
            return true
        }
        
        // Step 4: Apply token budget constraint if provided
        if let budget = tokenBudget {
            let currentEstimate = subtasks.compactMap { $0.estimatedTokenCost }.reduce(0, +)
            if currentEstimate > budget {
                // Remove lowest priority subtasks until within budget
                subtasks.sort { ($0.priority, $0.estimatedTokenCost ?? 0) < ($1.priority, $1.estimatedTokenCost ?? 0) }
                
                var remainingBudget = budget
                var keptSubtasks: [DecomposedSubtask] = []
                
                for subtask in subtasks {
                    let cost = subtask.estimatedTokenCost ?? 0
                    if remainingBudget >= cost {
                        keptSubtasks.append(subtask)
                        remainingBudget -= cost
                    } else {
                        removalRationales[subtask.id] = "Removed to stay within token budget"
                        removedCount += 1
                    }
                }
                
                subtasks = keptSubtasks
            }
        }
        
        print("✅ DynamicPruner: Pruned \(removedCount) subtasks, \(subtasks.count) remaining")
        
        // Recalculate execution order
        let executionOrder = calculateExecutionOrder(subtasks: subtasks)
        
        let prunedDecomposition = TaskDecomposition(
            subtasks: subtasks,
            executionOrder: executionOrder
        )
        
        return PruningResult(
            decomposition: prunedDecomposition,
            removalRationales: removalRationales
        )
    }
    
    /// Normalize description for comparison
    private func normalizeDescription(_ description: String) -> String {
        return description.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
    
    /// Check if two subtasks are similar enough to merge
    private func areSimilar(_ a: DecomposedSubtask, _ b: DecomposedSubtask) -> Bool {
        let normalizedA = normalizeDescription(a.description)
        let normalizedB = normalizeDescription(b.description)
        
        // Check exact match
        if normalizedA == normalizedB {
            return true
        }
        
        // Check if one contains the other
        if normalizedA.contains(normalizedB) || normalizedB.contains(normalizedA) {
            return true
        }
        
        // Simple word overlap check
        let wordsA = Set(normalizedA.components(separatedBy: .whitespaces))
        let wordsB = Set(normalizedB.components(separatedBy: .whitespaces))
        
        let intersection = wordsA.intersection(wordsB)
        let union = wordsA.union(wordsB)
        
        guard !union.isEmpty else { return false }
        
        let similarity = Double(intersection.count) / Double(union.count)
        return similarity >= similarityThreshold
    }
    
    /// Merge multiple subtasks into one
    private func mergeSubtasks(_ subtasks: [DecomposedSubtask]) -> DecomposedSubtask {
        guard let first = subtasks.first else {
            fatalError("Cannot merge empty subtasks")
        }
        
        // Combine descriptions
        let combinedDescription = subtasks.map { $0.description }.joined(separator: "; ")
        
        // Combine capabilities
        let combinedCapabilities = subtasks.reduce(Set<AgentCapability>()) { $0.union($1.requiredCapabilities) }
        
        // Use highest priority
        let maxPriority = subtasks.map { $0.priority }.max() ?? first.priority
        
        // Combine dependencies (excluding self-references)
        let allDependencies = Set(subtasks.flatMap { $0.dependencies })
        let filteredDependencies = allDependencies.filter { depId in
            !subtasks.contains { $0.id == depId }
        }
        
        // Can execute in parallel if all can
        let canParallel = subtasks.allSatisfy { $0.canExecuteInParallel }
        
        // Sum token costs
        let totalCost = subtasks.compactMap { $0.estimatedTokenCost }.reduce(0, +)
        
        return DecomposedSubtask(
            id: first.id,
            description: combinedDescription,
            agentName: first.agentName,
            requiredCapabilities: combinedCapabilities,
            priority: maxPriority,
            dependencies: Array(filteredDependencies),
            canExecuteInParallel: canParallel,
            estimatedTokenCost: totalCost > 0 ? totalCost : nil
        )
    }
    
    /// Calculate execution order based on dependencies
    private func calculateExecutionOrder(subtasks: [DecomposedSubtask]) -> [UUID] {
        var order: [UUID] = []
        var visited: Set<UUID> = []
        let subtasksById = Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, $0) })
        
        func visit(_ subtaskId: UUID) {
            guard !visited.contains(subtaskId) else { return }
            guard let subtask = subtasksById[subtaskId] else { return }
            
            // Visit dependencies first
            for depId in subtask.dependencies {
                visit(depId)
            }
            
            visited.insert(subtaskId)
            order.append(subtaskId)
        }
        
        // Visit all subtasks
        for subtask in subtasks {
            visit(subtask.id)
        }
        
        return order
    }
}

