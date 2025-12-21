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
        let subtasks = await extractSubtasks(from: analysis, availableAgents: availableAgents)
        
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
    private func extractSubtasks(from text: String, availableAgents: [any Agent]) async -> [DecomposedSubtask] {
        var subtasks: [DecomposedSubtask] = []
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "TaskDecompositionParser.swift:extractSubtasks",
            message: "Starting extraction",
            hypothesisId: "D",
            data: [
                "textLength": text.count,
                "textPreview": String(text.prefix(300))
            ]
        )
        
        // Pattern 1: Numbered list (1., 2., etc.)
        let numberedPattern = #"(?m)^\s*(\d+)\.\s+(.+?)(?=\n\s*\d+\.|$)"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            // Debug logging
            await DebugLogger.shared.log(
                location: "TaskDecompositionParser.swift:extractSubtasks",
                message: "Numbered pattern matches",
                hypothesisId: "D",
                data: [
                    "matchCount": matches.count,
                    "matches": matches.prefix(10).map { match in
                        if match.numberOfRanges >= 3 {
                            let contentRange = match.range(at: 2)
                            if let content = Range(contentRange, in: text) {
                                return String(text[content].prefix(100))
                            }
                        }
                        return ""
                    }
                ]
            )
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
                
                // Debug logging
                await DebugLogger.shared.log(
                    location: "TaskDecompositionParser.swift:extractSubtasks",
                    message: "Bullet pattern matches",
                    hypothesisId: "D",
                    data: [
                        "matchCount": matches.count,
                        "matches": matches.prefix(20).map { match in
                            if match.numberOfRanges >= 2 {
                                let contentRange = match.range(at: 1)
                                if let content = Range(contentRange, in: text) {
                                    return String(text[content].prefix(100))
                                }
                            }
                            return ""
                        }
                    ]
                )
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
            
            // Debug logging
            await DebugLogger.shared.log(
                location: "TaskDecompositionParser.swift:extractSubtasks",
                message: "Falling back to paragraph splitting",
                hypothesisId: "E",
                data: [
                    "paragraphCount": paragraphs.count,
                    "paragraphs": paragraphs.prefix(10).map { String($0.prefix(100)) }
                ]
            )
            for paragraph in paragraphs {
                if let subtask = parseSubtaskText(paragraph, availableAgents: availableAgents) {
                    subtasks.append(subtask)
                }
            }
        }
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "TaskDecompositionParser.swift:extractSubtasks",
            message: "Extraction complete",
            hypothesisId: "D",
            data: [
                "finalSubtaskCount": subtasks.count,
                "subtasks": subtasks.map { [
                    "id": $0.id.uuidString,
                    "description": String($0.description.prefix(150)),
                    "agentName": $0.agentName ?? "none"
                ] }
            ]
        )
        
        return subtasks
    }
    
    /// Parse a single subtask text into a DecomposedSubtask
    private func parseSubtaskText(_ text: String, availableAgents: [any Agent]) -> DecomposedSubtask? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Filter out metadata-only lines (like "**Capabilities Needed:** dataAnalysis")
        // These are not actual subtasks, just metadata fields
        if isMetadataField(trimmed) {
            print("🔍 TaskDecompositionParser: Skipping metadata field: \(trimmed.prefix(80))")
            return nil
        }
        
        // Also filter out very short descriptions that are likely just labels
        if trimmed.count < 15 {
            print("🔍 TaskDecompositionParser: Skipping very short text (likely label): \(trimmed)")
            return nil
        }
        
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
    
    /// Check if text is a metadata field (not an actual subtask)
    private func isMetadataField(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        // Check for markdown-style metadata patterns
        let metadataPatterns = [
            "**capabilities needed:**",
            "**agent:**",
            "**dependencies:**",
            "**dependencies on other subtasks:**",
            "**specific task description:**",
            "capabilities needed:",
            "agent:",
            "dependencies:",
            "specific task description:"
        ]
        
        // If text starts with a metadata pattern, it's likely a metadata field
        for pattern in metadataPatterns {
            if lowercased.hasPrefix(pattern) || lowercased.trimmingCharacters(in: .whitespaces).hasPrefix(pattern) {
                return true
            }
        }
        
        // Also check if it's very short and looks like a label
        if text.count < 50 && (text.contains(":") || text.contains("**")) {
            // Check if it's mostly just a label with minimal content
            let parts = text.split(separator: ":")
            if parts.count == 2 && parts[1].trimmingCharacters(in: .whitespaces).count < 20 {
                return true
            }
        }
        
        return false
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

