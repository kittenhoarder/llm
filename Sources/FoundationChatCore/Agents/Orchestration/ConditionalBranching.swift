//
//  ConditionalBranching.swift
//  FoundationChatCore
//
//  Conditional branching and dynamic routing based on intermediate results
//

import Foundation

/// A conditional branch that evaluates results and determines next steps
@available(macOS 26.0, iOS 26.0, *)
public struct ConditionalBranch: Sendable, Codable {
    /// Unique identifier for this branch
    public let id: UUID
    
    /// Condition description (natural language or structured)
    public let condition: String
    
    /// Condition type
    public let conditionType: ConditionType
    
    /// Subtasks to execute if condition is true
    public let trueSubtasks: [DecomposedSubtask]
    
    /// Subtasks to execute if condition is false (optional)
    public let falseSubtasks: [DecomposedSubtask]?
    
    /// Parent subtask ID this branch depends on
    public let dependsOnSubtaskId: UUID?
    
    public init(
        id: UUID = UUID(),
        condition: String,
        conditionType: ConditionType = .naturalLanguage,
        trueSubtasks: [DecomposedSubtask],
        falseSubtasks: [DecomposedSubtask]? = nil,
        dependsOnSubtaskId: UUID? = nil
    ) {
        self.id = id
        self.condition = condition
        self.conditionType = conditionType
        self.trueSubtasks = trueSubtasks
        self.falseSubtasks = falseSubtasks
        self.dependsOnSubtaskId = dependsOnSubtaskId
    }
}

/// Type of condition evaluation
@available(macOS 26.0, iOS 26.0, *)
public enum ConditionType: String, Sendable, Codable {
    /// Natural language condition (evaluated by LLM)
    case naturalLanguage
    
    /// Structured condition (evaluated programmatically)
    case structured
    
    /// Result-based condition (checks if result contains specific content)
    case resultBased
}

/// Result of branch evaluation
@available(macOS 26.0, iOS 26.0, *)
public struct BranchEvaluationResult: Sendable {
    /// Whether the condition evaluated to true
    public let conditionMet: Bool
    
    /// Confidence score (0.0 to 1.0)
    public let confidence: Double
    
    /// Reasoning for the evaluation
    public let reasoning: String
    
    /// Subtasks to execute based on evaluation
    public let subtasksToExecute: [DecomposedSubtask]
    
    public init(
        conditionMet: Bool,
        confidence: Double = 1.0,
        reasoning: String = "",
        subtasksToExecute: [DecomposedSubtask]
    ) {
        self.conditionMet = conditionMet
        self.confidence = confidence
        self.reasoning = reasoning
        self.subtasksToExecute = subtasksToExecute
    }
}

/// Evaluator for conditional branches
@available(macOS 26.0, iOS 26.0, *)
public actor ConditionalBranchEvaluator {
    public init() {}
    /// Evaluate a conditional branch based on intermediate results
    /// - Parameters:
    ///   - branch: The branch to evaluate
    ///   - results: Current subtask results
    ///   - coordinator: Coordinator agent for LLM-based evaluation
    /// - Returns: Evaluation result
    public func evaluate(
        branch: ConditionalBranch,
        results: [UUID: AgentResult],
        coordinator: any Agent
    ) async throws -> BranchEvaluationResult {
        switch branch.conditionType {
        case .naturalLanguage:
            return try await evaluateNaturalLanguage(
                branch: branch,
                results: results,
                coordinator: coordinator
            )
        case .structured:
            return try await evaluateStructured(
                branch: branch,
                results: results
            )
        case .resultBased:
            return try await evaluateResultBased(
                branch: branch,
                results: results
            )
        }
    }
    
    /// Evaluate natural language condition using coordinator
    private func evaluateNaturalLanguage(
        branch: ConditionalBranch,
        results: [UUID: AgentResult],
        coordinator: any Agent
    ) async throws -> BranchEvaluationResult {
        // Build context from relevant results
        var contextDescription = "Evaluate the following condition:\n\n\(branch.condition)\n\n"
        
        if let dependsOnId = branch.dependsOnSubtaskId,
           let result = results[dependsOnId] {
            contextDescription += "Result from dependent subtask:\n\(result.content)\n\n"
        } else {
            // Include all results for context
            contextDescription += "Current subtask results:\n"
            for (id, result) in results {
                contextDescription += "- Subtask \(id.uuidString.prefix(8)): \(result.content.prefix(200))\n"
            }
        }
        
        contextDescription += """
        
        Respond with ONLY:
        - "TRUE" if the condition is met
        - "FALSE" if the condition is not met
        - A brief explanation (one sentence)
        """
        
        let evaluationTask = AgentTask(
            description: contextDescription,
            requiredCapabilities: [.generalReasoning]
        )
        
        let context = AgentContext()
        let evaluationResult = try await coordinator.process(task: evaluationTask, context: context)
        
        let response = evaluationResult.content.uppercased()
        let conditionMet = response.contains("TRUE")
        let confidence: Double = conditionMet ? 0.9 : 0.9 // Default confidence for LLM evaluation
        
        let subtasksToExecute = conditionMet ? branch.trueSubtasks : (branch.falseSubtasks ?? [])
        
        return BranchEvaluationResult(
            conditionMet: conditionMet,
            confidence: confidence,
            reasoning: evaluationResult.content,
            subtasksToExecute: subtasksToExecute
        )
    }
    
    /// Evaluate structured condition programmatically
    private func evaluateStructured(
        branch: ConditionalBranch,
        results: [UUID: AgentResult]
    ) async throws -> BranchEvaluationResult {
        // For structured conditions, parse and evaluate programmatically
        // This is a simplified implementation - can be extended with more sophisticated parsing
        guard let dependsOnId = branch.dependsOnSubtaskId,
              let result = results[dependsOnId] else {
            // No dependent result, default to false
            return BranchEvaluationResult(
                conditionMet: false,
                confidence: 1.0,
                reasoning: "No dependent result available",
                subtasksToExecute: branch.falseSubtasks ?? []
            )
        }
        
        // Simple keyword-based evaluation
        let conditionLower = branch.condition.lowercased()
        let resultLower = result.content.lowercased()
        
        // Check for common condition patterns
        var conditionMet = false
        
        if conditionLower.contains("contains") {
            let searchTerm = conditionLower.replacingOccurrences(of: "contains", with: "").trimmingCharacters(in: .whitespaces)
            conditionMet = resultLower.contains(searchTerm)
        } else if conditionLower.contains("success") || conditionLower.contains("succeeded") {
            conditionMet = result.success
        } else if conditionLower.contains("error") || conditionLower.contains("failed") {
            conditionMet = !result.success || result.error != nil
        } else {
            // Default: check if result content matches condition keywords
            let keywords = conditionLower.components(separatedBy: .whitespaces).filter { $0.count > 3 }
            conditionMet = keywords.allSatisfy { resultLower.contains($0) }
        }
        
        let subtasksToExecute = conditionMet ? branch.trueSubtasks : (branch.falseSubtasks ?? [])
        
        return BranchEvaluationResult(
            conditionMet: conditionMet,
            confidence: 0.8,
            reasoning: conditionMet ? "Condition met based on result content" : "Condition not met based on result content",
            subtasksToExecute: subtasksToExecute
        )
    }
    
    /// Evaluate result-based condition
    private func evaluateResultBased(
        branch: ConditionalBranch,
        results: [UUID: AgentResult]
    ) async throws -> BranchEvaluationResult {
        guard let dependsOnId = branch.dependsOnSubtaskId,
              let result = results[dependsOnId] else {
            return BranchEvaluationResult(
                conditionMet: false,
                confidence: 1.0,
                reasoning: "No dependent result available",
                subtasksToExecute: branch.falseSubtasks ?? []
            )
        }
        
        // Check if result contains the condition text
        let conditionMet = result.content.localizedCaseInsensitiveContains(branch.condition) || result.success
        
        let subtasksToExecute = conditionMet ? branch.trueSubtasks : (branch.falseSubtasks ?? [])
        
        return BranchEvaluationResult(
            conditionMet: conditionMet,
            confidence: 0.9,
            reasoning: conditionMet ? "Result contains condition or succeeded" : "Result does not meet condition",
            subtasksToExecute: subtasksToExecute
        )
    }
}

