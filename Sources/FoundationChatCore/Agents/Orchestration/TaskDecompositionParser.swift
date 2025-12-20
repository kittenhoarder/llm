//
//  TaskDecompositionParser.swift
//  FoundationChatCore
//
//  Parser for extracting task decomposition from coordinator's natural language analysis
//

import Foundation

/// Parser for extracting subtasks from coordinator's natural language analysis
@available(macOS 26.0, iOS 26.0, *)
public actor TaskDecompositionParser {
    private let registry: AgentRegistry
    private let tokenCounter: TokenCounter
    
    public init(registry: AgentRegistry = .shared, tokenCounter: TokenCounter = TokenCounter()) {
        self.registry = registry
        self.tokenCounter = tokenCounter
    }
    
    /// Parse coordinator's analysis output into structured task decomposition
    /// - Parameters:
    ///   - analysis: The coordinator's natural language analysis
    ///   - availableAgents: List of available agents for matching
    /// - Returns: Parsed task decomposition, or nil if parsing fails
    public func parse(_ analysis: String, availableAgents: [any Agent]) async -> TaskDecomposition? {
        print("🔍 TaskDecompositionParser: Parsing coordinator analysis...")
        
        // Try to extract subtasks using various patterns
        let subtasks = extractSubtasks(from: analysis, availableAgents: availableAgents)
        
        guard !subtasks.isEmpty else {
            print("⚠️ TaskDecompositionParser: No subtasks extracted, parsing failed")
            return nil
        }
        
        print("✅ TaskDecompositionParser: Extracted \(subtasks.count) subtasks")
        
        // Estimate token costs
        let subtasksWithCosts = await estimateTokenCosts(subtasks)
        
        // Calculate execution order based on dependencies
        let executionOrder = calculateExecutionOrder(subtasks: subtasksWithCosts)
        
        return TaskDecomposition(
            subtasks: subtasksWithCosts,
            executionOrder: executionOrder
        )
    }
    
    /// Extract subtasks from natural language text
    private func extractSubtasks(from text: String, availableAgents: [any Agent]) -> [DecomposedSubtask] {
        var subtasks: [DecomposedSubtask] = []
        
        // Pattern 1: Numbered list (1., 2., etc.)
        let numberedPattern = #"(?m)^\s*(\d+)\.\s+(.+?)(?=\n\s*\d+\.|$)"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if match.numberOfRanges >= 3 {
                    let contentRange = match.range(at: 2)
                    if let content = Range(contentRange, in: text) {
                        let subtaskText = String(text[content])
                        if let subtask = parseSubtaskText(subtaskText, availableAgents: availableAgents) {
                            subtasks.append(subtask)
                        }
                    }
                }
            }
        }
        
        // Pattern 2: Bullet points (-, *, •)
        if subtasks.isEmpty {
            let bulletPattern = #"(?m)^\s*[-*•]\s+(.+?)(?=\n\s*[-*•]|$)"#
            if let regex = try? NSRegularExpression(pattern: bulletPattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        if let content = Range(contentRange, in: text) {
                            let subtaskText = String(text[content])
                            if let subtask = parseSubtaskText(subtaskText, availableAgents: availableAgents) {
                                subtasks.append(subtask)
                            }
                        }
                    }
                }
            }
        }
        
        // Pattern 3: "Subtask:" labels
        if subtasks.isEmpty {
            let subtaskPattern = #"(?i)subtask\s*[:\-]\s*(.+?)(?=\n\s*(?:subtask|task|$))"#
            if let regex = try? NSRegularExpression(pattern: subtaskPattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        if let content = Range(contentRange, in: text) {
                            let subtaskText = String(text[content])
                            if let subtask = parseSubtaskText(subtaskText, availableAgents: availableAgents) {
                                subtasks.append(subtask)
                            }
                        }
                    }
                }
            }
        }
        
        // If still no subtasks, try to split by paragraphs and treat each as a subtask
        if subtasks.isEmpty {
            let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            for paragraph in paragraphs {
                if let subtask = parseSubtaskText(paragraph, availableAgents: availableAgents) {
                    subtasks.append(subtask)
                }
            }
        }
        
        return subtasks
    }
    
    /// Parse a single subtask text into a DecomposedSubtask
    private func parseSubtaskText(_ text: String, availableAgents: [any Agent]) -> DecomposedSubtask? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Extract agent name mentions
        let agentName = extractAgentName(from: trimmed, availableAgents: availableAgents)
        
        // Extract capabilities
        let capabilities = extractCapabilities(from: trimmed)
        
        // Detect dependencies
        let dependencies = extractDependencies(from: trimmed)
        
        // Detect if can execute in parallel (default to true unless dependencies exist)
        let canExecuteInParallel = dependencies.isEmpty && !containsSequentialKeywords(trimmed)
        
        return DecomposedSubtask(
            description: trimmed,
            agentName: agentName,
            requiredCapabilities: capabilities,
            dependencies: dependencies,
            canExecuteInParallel: canExecuteInParallel
        )
    }
    
    /// Extract agent name from text
    private func extractAgentName(from text: String, availableAgents: [any Agent]) -> String? {
        let lowercased = text.lowercased()
        
        // Try to match agent names
        for agent in availableAgents {
            let agentNameLower = agent.name.lowercased()
            if lowercased.contains(agentNameLower) {
                return agent.name
            }
            
            // Also check for variations
            let variations = [
                "\(agentNameLower) agent",
                "\(agentNameLower) handler",
                "use \(agentNameLower)",
                "\(agentNameLower) should",
                "\(agentNameLower) will"
            ]
            
            for variation in variations {
                if lowercased.contains(variation) {
                    return agent.name
                }
            }
        }
        
        return nil
    }
    
    /// Extract required capabilities from text
    private func extractCapabilities(from text: String) -> Set<AgentCapability> {
        let lowercased = text.lowercased()
        var capabilities: Set<AgentCapability> = []
        
        if lowercased.contains("search") || lowercased.contains("web") || lowercased.contains("look up") {
            capabilities.insert(.webSearch)
        }
        
        if lowercased.contains("file") || lowercased.contains("read") || lowercased.contains("document") {
            capabilities.insert(.fileReading)
        }
        
        if lowercased.contains("code") || lowercased.contains("analyze code") || lowercased.contains("programming") {
            capabilities.insert(.codeAnalysis)
        }
        
        if lowercased.contains("data") || lowercased.contains("calculate") || lowercased.contains("statistics") {
            capabilities.insert(.dataAnalysis)
        }
        
        if lowercased.contains("coordinate") || lowercased.contains("reason") || lowercased.contains("plan") {
            capabilities.insert(.generalReasoning)
        }
        
        return capabilities
    }
    
    /// Extract dependencies from text (returns empty for now, as dependency parsing is complex)
    private func extractDependencies(from text: String) -> [UUID] {
        // TODO: Implement dependency extraction
        // Look for patterns like "after X", "using results from Y", "depends on Z"
        // For now, return empty array
        return []
    }
    
    /// Check if text contains keywords indicating sequential execution
    private func containsSequentialKeywords(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let sequentialKeywords = ["after", "then", "next", "following", "subsequently", "depends on", "requires"]
        return sequentialKeywords.contains { lowercased.contains($0) }
    }
    
    /// Estimate token costs for subtasks
    private func estimateTokenCosts(_ subtasks: [DecomposedSubtask]) async -> [DecomposedSubtask] {
        return await withTaskGroup(of: (Int, DecomposedSubtask).self, returning: [DecomposedSubtask].self) { group in
            for subtask in subtasks {
                group.addTask {
                    let cost = await self.tokenCounter.countTokens(subtask.description)
                    return (subtask.priority, DecomposedSubtask(
                        id: subtask.id,
                        description: subtask.description,
                        agentName: subtask.agentName,
                        requiredCapabilities: subtask.requiredCapabilities,
                        priority: subtask.priority,
                        dependencies: subtask.dependencies,
                        canExecuteInParallel: subtask.canExecuteInParallel,
                        estimatedTokenCost: cost
                    ))
                }
            }
            
            var results: [(Int, DecomposedSubtask)] = []
            for await result in group {
                results.append(result)
            }
            
            // Sort by priority to maintain order
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    /// Calculate execution order based on dependencies
    private func calculateExecutionOrder(subtasks: [DecomposedSubtask]) -> [UUID] {
        // Simple topological sort for dependency ordering
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

