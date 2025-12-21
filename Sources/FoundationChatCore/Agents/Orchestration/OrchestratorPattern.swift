//
//  OrchestratorPattern.swift
//  FoundationChatCore
//
//  Orchestrator pattern: Single coordinator delegates to specialists
//

import Foundation

/// Orchestrator pattern implementation
/// A single coordinator agent analyzes the task and delegates to specialized agents
@available(macOS 26.0, iOS 26.0, *)
public struct OrchestratorPattern: OrchestrationPattern {
    /// Coordinator agent (for task decomposition)
    private let coordinator: any Agent
    
    /// Task decomposition parser
    private let parser: TaskDecompositionParser
    
    /// Dynamic pruner for removing redundant subtasks
    private let pruner: DynamicPruner
    
    /// Progressive context builder
    private let contextBuilder: ProgressiveContextBuilder
    
    /// Result summarizer
    private let resultSummarizer: ResultSummarizer
    
    /// Token tracker
    private let tokenTracker: AgentTokenTracker
    
    /// Token budget guard
    private let budgetGuard: TokenBudgetGuard
    
    /// Delegation metrics (stored in a class wrapper to allow mutation in struct)
    private final class MetricsStorage: @unchecked Sendable {
        var metrics: DelegationMetrics?
    }
    private let metricsStorage = MetricsStorage()
    
    public init(
        coordinator: any Agent,
        parser: TaskDecompositionParser = TaskDecompositionParser(),
        pruner: DynamicPruner = DynamicPruner(),
        contextBuilder: ProgressiveContextBuilder = ProgressiveContextBuilder(),
        resultSummarizer: ResultSummarizer = ResultSummarizer(),
        tokenTracker: AgentTokenTracker = AgentTokenTracker(),
        budgetGuard: TokenBudgetGuard = TokenBudgetGuard()
    ) {
        self.coordinator = coordinator
        self.parser = parser
        self.pruner = pruner
        self.contextBuilder = contextBuilder
        self.resultSummarizer = resultSummarizer
        self.tokenTracker = tokenTracker
        self.budgetGuard = budgetGuard
    }
    
    public func execute(
        task: AgentTask,
        agents: [any Agent],
        context: AgentContext
    ) async throws -> AgentResult {
        let _ = Date()
        var coordinatorAnalysisTime: TimeInterval = 0
        var coordinatorSynthesisTime: TimeInterval = 0
        var specializedAgentsTime: TimeInterval = 0
        
        print("🎯 OrchestratorPattern: Starting execution for task '\(task.description.prefix(50))...'")
        
        // Check if smart delegation is enabled (default: true if key doesn't exist)
        let smartDelegationEnabled: Bool
        if UserDefaults.standard.object(forKey: "smartDelegation") != nil {
            smartDelegationEnabled = UserDefaults.standard.bool(forKey: "smartDelegation")
        } else {
            smartDelegationEnabled = true // Default to enabled
        }
        if smartDelegationEnabled {
            // Step 0: Decision step - should we delegate or respond directly?
            let shouldDelegate = try await shouldDelegate(task: task, context: context)
            
            if !shouldDelegate {
                print("💬 OrchestratorPattern: Coordinator decided to respond directly (no delegation)")
                return try await respondDirectly(task: task, context: context)
            }
            
            print("🔄 OrchestratorPattern: Coordinator decided to delegate to specialized agents")
        }
        
        // Step 1: Use coordinator to analyze task and determine which agents are needed
        let analysisStartTime = Date()
        
        // Build analysis task description with file information
        var analysisTaskDescription = """
            Analyze the following task and break it down into subtasks. For each subtask, specify:
            1. The specific task description
            2. Which agent should handle it (from available agents)
            3. What capabilities are needed
            4. Dependencies on other subtasks (if any)
            5. Whether it can run in parallel with other subtasks
            
            Format your response with clear subtask sections (numbered list, bullet points, or "Subtask:" labels).
            
            Available agents: \(agents.map { "\($0.name) (capabilities: \($0.capabilities.map { $0.rawValue }.joined(separator: ", ")))" }.joined(separator: "; "))
            """
        
        if !context.fileReferences.isEmpty {
            analysisTaskDescription += "\n\nAttached files: \(context.fileReferences.count) file(s)"
            analysisTaskDescription += "\n- If the task involves analyzing text files, delegate to the File Reader agent"
            analysisTaskDescription += "\n- If the task involves analyzing images (photos, screenshots, diagrams, etc.), delegate to the Vision Agent"
        }
        
        analysisTaskDescription += """
            
            Task: \(task.description)
            
            Provide a breakdown of subtasks and which agent should handle each subtask.
            """
        
        let analysisTask = AgentTask(
            description: analysisTaskDescription,
            requiredCapabilities: [.generalReasoning]
        )
        
        // Track coordinator analysis tokens
        let analysisPrompt = try await buildPrompt(from: analysisTask, context: context)
        await tokenTracker.trackPrompt(agentId: coordinator.id, prompt: analysisPrompt)
        await tokenTracker.trackContext(agentId: coordinator.id, context: context)
        
        let analysisResult = try await coordinator.process(task: analysisTask, context: context)
        coordinatorAnalysisTime = Date().timeIntervalSince(analysisStartTime)
        
        await tokenTracker.trackResponse(agentId: coordinator.id, response: analysisResult.content)
        await tokenTracker.trackToolCalls(agentId: coordinator.id, toolCalls: analysisResult.toolCalls)
        
        print("📊 OrchestratorPattern: Coordinator analysis completed in \(String(format: "%.2f", coordinatorAnalysisTime))s")
        print("📝 OrchestratorPattern: Coordinator analysis output:\n\(analysisResult.content)")
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:execute",
            message: "Coordinator analysis output before parsing",
            hypothesisId: "A",
            data: [
                "analysisLength": analysisResult.content.count,
                "analysisPreview": String(analysisResult.content.prefix(500))
            ]
        )
        
        // Step 2: Parse coordinator's analysis
        let decomposition = await parser.parse(analysisResult.content, availableAgents: agents)
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:execute",
            message: "Parsed subtasks before pruning",
            hypothesisId: "B",
            data: [
                "subtaskCount": decomposition?.subtasks.count ?? 0,
                "subtasks": decomposition?.subtasks.map { [
                    "id": $0.id.uuidString,
                    "description": String($0.description.prefix(100)),
                    "agentName": $0.agentName ?? "none",
                    "capabilities": Array($0.requiredCapabilities).map { $0.rawValue }
                ] } ?? []
            ]
        )
        
        // Step 3: Apply dynamic pruning
        let prunedResult = await pruner.prune(decomposition ?? TaskDecomposition(subtasks: []))
        let finalDecomposition = prunedResult.decomposition
        
        let subtasksCreated = decomposition?.subtasks.count ?? 0
        let subtasksPruned = prunedResult.removalRationales.count
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:execute",
            message: "Pruned subtasks",
            hypothesisId: "C",
            data: [
                "subtasksBefore": subtasksCreated,
                "subtasksAfter": finalDecomposition.subtasks.count,
                "removedCount": subtasksPruned,
                "removalRationales": Dictionary(uniqueKeysWithValues: prunedResult.removalRationales.map { ($0.key.uuidString, $0.value) }),
                "finalSubtasks": finalDecomposition.subtasks.map { [
                    "id": $0.id.uuidString,
                    "description": String($0.description.prefix(100)),
                    "agentName": $0.agentName ?? "none"
                ] }
            ]
        )
        
        print("✂️ OrchestratorPattern: Pruned \(subtasksPruned) subtasks, \(finalDecomposition.subtasks.count) remaining")
        if !prunedResult.removalRationales.isEmpty {
            for (id, rationale) in prunedResult.removalRationales {
                print("  - Removed subtask \(id.uuidString.prefix(8)): \(rationale)")
            }
        }
        
        // Step 4: Delegate subtasks to appropriate agents
        var results: [AgentResult] = []
        var updatedContext = context
        var previousResults: [AgentResult] = []
        
        // Check if we successfully parsed subtasks
        guard !finalDecomposition.subtasks.isEmpty else {
            print("⚠️ OrchestratorPattern: No subtasks parsed, falling back to capability-based matching")
            return try await fallbackExecution(task: task, agents: agents, context: context)
        }
        
        // Get parallelizable groups
        let parallelGroups = finalDecomposition.getParallelizableGroups()
        print("🔄 OrchestratorPattern: Executing \(parallelGroups.count) groups of subtasks")
        
        let specializedStartTime = Date()
        
        // Execute groups sequentially, but subtasks within groups in parallel
        for (groupIndex, group) in parallelGroups.enumerated() {
            print("📦 OrchestratorPattern: Executing group \(groupIndex + 1)/\(parallelGroups.count) with \(group.count) subtasks")
            
            if group.count == 1 || !group.allSatisfy({ $0.canExecuteInParallel }) {
                // Sequential execution
                for subtask in group {
                    let result = try await executeSubtask(
                        subtask: subtask,
                        agents: agents,
                        context: updatedContext,
                        previousResults: previousResults
                    )
                    results.append(result)
                    previousResults.append(result)
                    
                    if let updated = result.updatedContext {
                        updatedContext.merge(updated)
                    }
                }
            } else {
                // Parallel execution - capture context snapshot for each task
                let contextSnapshot = updatedContext
                let previousResultsSnapshot = previousResults
                
                try await withThrowingTaskGroup(of: AgentResult.self) { taskGroup in
                    for subtask in group {
                        taskGroup.addTask {
                            try await self.executeSubtask(
                                subtask: subtask,
                                agents: agents,
                                context: contextSnapshot,
                                previousResults: previousResultsSnapshot
                            )
                        }
                    }
                    
                    var groupResults: [AgentResult] = []
                    for try await result in taskGroup {
                        groupResults.append(result)
                    }
                    
                    // Merge all results after parallel execution
                    for result in groupResults {
                        if let updated = result.updatedContext {
                            updatedContext.merge(updated)
                        }
                    }
                    
                    results.append(contentsOf: groupResults)
                    previousResults.append(contentsOf: groupResults)
                }
            }
        }
        
        specializedAgentsTime = Date().timeIntervalSince(specializedStartTime)
        print("✅ OrchestratorPattern: All specialized agents completed in \(String(format: "%.2f", specializedAgentsTime))s")
        
        // Step 5: Synthesize results using coordinator
        let synthesisStartTime = Date()
        let synthesizedContent = try await synthesizeResults(results, context: updatedContext)
        coordinatorSynthesisTime = Date().timeIntervalSince(synthesisStartTime)
        
        await tokenTracker.trackPrompt(agentId: coordinator.id, prompt: "Synthesize results")
        await tokenTracker.trackResponse(agentId: coordinator.id, response: synthesizedContent)
        
        // Calculate metrics
        let totalTokens = await tokenTracker.getTotalTokenUsage()
        let singleAgentEstimate = await estimateSingleAgentTokens(task: task, context: context)
        let savingsPercentage = await tokenTracker.calculateSavings(singleAgentEstimate: singleAgentEstimate)
        
        metricsStorage.metrics = DelegationMetrics(
            subtasksCreated: subtasksCreated,
            subtasksPruned: subtasksPruned,
            agentsUsed: results.count,
            totalTokens: totalTokens,
            tokenSavingsPercentage: savingsPercentage,
            executionTimeBreakdown: ExecutionTimeBreakdown(
                coordinatorAnalysisTime: coordinatorAnalysisTime,
                coordinatorSynthesisTime: coordinatorSynthesisTime,
                specializedAgentsTime: specializedAgentsTime
            )
        )
        
        print("📊 OrchestratorPattern: Token usage - Total: \(totalTokens), Savings: \(String(format: "%.1f", savingsPercentage))%")
        
        // Store token usage in context
        var finalContext = updatedContext
        finalContext = await tokenTracker.storeInContext(finalContext)
        finalContext.metadata["tokens_saved_vs_single_agent"] = String(format: "%.1f", savingsPercentage)
        
        // Store full results in toolResults for reference
        for (index, result) in results.enumerated() {
            finalContext.toolResults["agent_result_\(index)_full"] = result.content
        }
        
        return AgentResult(
            agentId: coordinator.id,
            taskId: task.id,
            content: synthesizedContent,
            success: results.allSatisfy { $0.success },
            error: results.compactMap { $0.error }.first,
            toolCalls: results.flatMap { $0.toolCalls },
            updatedContext: finalContext
        )
    }
    
    /// Execute a single subtask
    private func executeSubtask(
        subtask: DecomposedSubtask,
        agents: [any Agent],
        context: AgentContext,
        previousResults: [AgentResult]
    ) async throws -> AgentResult {
        print("🎯 OrchestratorPattern: Executing subtask '\(subtask.description.prefix(50))...'")
        
        // Find matching agent
        let agent = findAgent(for: subtask, in: agents)
        
        guard let selectedAgent = agent else {
            print("⚠️ OrchestratorPattern: No agent found for subtask, using coordinator")
            // Debug logging
            await DebugLogger.shared.log(
                location: "OrchestratorPattern.swift:executeSubtask",
                message: "No agent found, using coordinator",
                hypothesisId: "F",
                data: [
                    "subtaskId": subtask.id.uuidString,
                    "subtaskDescription": String(subtask.description.prefix(100)),
                    "requiredCapabilities": Array(subtask.requiredCapabilities).map { $0.rawValue },
                    "agentName": subtask.agentName ?? "none"
                ]
            )
            let subtaskTask = AgentTask(description: subtask.description, requiredCapabilities: subtask.requiredCapabilities)
            return try await coordinator.process(task: subtaskTask, context: context)
        }
        
        print("🤖 OrchestratorPattern: Selected agent '\(selectedAgent.name)' for subtask")
        
        // Build isolated context
        let isolatedContext = try await contextBuilder.buildContext(
            for: subtask,
            baseContext: context,
            previousResults: previousResults,
            tokenBudget: 2000 // Default budget per agent
        )
        
        // Track context tokens
        await tokenTracker.trackContext(agentId: selectedAgent.id, context: isolatedContext)
        
        // Create subtask
        let subtaskTask = AgentTask(
            description: subtask.description,
            requiredCapabilities: subtask.requiredCapabilities,
            parameters: [:]
        )
        
        // Track prompt tokens
        let prompt = try await buildPrompt(from: subtaskTask, context: isolatedContext)
        await tokenTracker.trackPrompt(agentId: selectedAgent.id, prompt: prompt)
        
        // Execute subtask
        let result = try await selectedAgent.process(task: subtaskTask, context: isolatedContext)
        
        // Track response and tool call tokens
        await tokenTracker.trackResponse(agentId: selectedAgent.id, response: result.content)
        await tokenTracker.trackToolCalls(agentId: selectedAgent.id, toolCalls: result.toolCalls)
        
        print("✅ OrchestratorPattern: Subtask completed by '\(selectedAgent.name)'")
        
        return result
    }
    
    /// Find agent for a subtask
    private func findAgent(for subtask: DecomposedSubtask, in agents: [any Agent]) -> (any Agent)? {
        // First try to match by name
        if let agentName = subtask.agentName {
            if let agent = agents.first(where: { $0.name == agentName }) {
                return agent
            }
        }
        
        // Then try to match by capabilities
        if !subtask.requiredCapabilities.isEmpty {
            let matchingAgents = agents.filter { agent in
                !subtask.requiredCapabilities.isDisjoint(with: agent.capabilities)
            }
            
            // Prefer agents that match all required capabilities
            if let perfectMatch = matchingAgents.first(where: { subtask.requiredCapabilities.isSubset(of: $0.capabilities) }) {
                return perfectMatch
            }
            
            // Otherwise return first match
            return matchingAgents.first
        }
        
        return nil
    }
    
    /// Synthesize results using coordinator
    private func synthesizeResults(_ results: [AgentResult], context: AgentContext) async throws -> String {
        guard !results.isEmpty else {
            return "No results from agents."
        }
        
        if results.count == 1 {
            return results[0].content
        }
        
        // Summarize results
        let summarizedResults = try await resultSummarizer.summarizeResults(results, level: .medium)
        
        // Create synthesis task
        let synthesisTask = AgentTask(
            description: """
            Synthesize the following agent results into a coherent, comprehensive response.
            Focus on the key findings and present them clearly.
            
            Agent Results:
            \(summarizedResults)
            """,
            requiredCapabilities: [.generalReasoning]
        )
        
        // Use minimal context (only summarized results, no full history)
        var synthesisContext = AgentContext()
        synthesisContext.conversationHistory = [
            Message(role: .user, content: synthesisTask.description)
        ]
        
        // Enforce budget for synthesis
        let enforcedContext = try await budgetGuard.enforceBudget(
            context: synthesisContext,
            budget: 1500, // Budget for synthesis
            summarizer: ContextSummarizer()
        )
        
        let synthesisResult = try await coordinator.process(task: synthesisTask, context: enforcedContext)
        return synthesisResult.content
    }
    
    /// Fallback execution when parsing fails
    private func fallbackExecution(
        task: AgentTask,
        agents: [any Agent],
        context: AgentContext
    ) async throws -> AgentResult {
        print("⚠️ OrchestratorPattern: Using fallback capability-based matching")
        
        let relevantAgents = agents.filter { agent in
            !task.requiredCapabilities.isDisjoint(with: agent.capabilities) ||
            task.requiredCapabilities.isEmpty
        }
        
        var results: [AgentResult] = []
        var updatedContext = context
        
        if !relevantAgents.isEmpty {
            for agent in relevantAgents {
                let result = try await agent.process(task: task, context: updatedContext)
                results.append(result)
                
                if let updated = result.updatedContext {
                    updatedContext.merge(updated)
                }
            }
        } else {
            let result = try await coordinator.process(task: task, context: updatedContext)
            results.append(result)
            if let updated = result.updatedContext {
                updatedContext.merge(updated)
            }
        }
        
        let aggregatedContent = aggregateResults(results)
        
        return AgentResult(
            agentId: coordinator.id,
            taskId: task.id,
            content: aggregatedContent,
            success: results.allSatisfy { $0.success },
            error: results.compactMap { $0.error }.first,
            toolCalls: results.flatMap { $0.toolCalls },
            updatedContext: updatedContext
        )
    }
    
    /// Build prompt from task and context (helper method)
    private func buildPrompt(from task: AgentTask, context: AgentContext) async throws -> String {
        var prompt = "Task: \(task.description)\n\n"
        
        if !context.conversationHistory.isEmpty {
            prompt += "Conversation History:\n"
            for message in context.conversationHistory.suffix(5) {
                prompt += "\(message.role.rawValue.capitalized): \(message.content)\n"
            }
            prompt += "\n"
        }
        
        if !context.fileReferences.isEmpty {
            prompt += "Available Files: \(context.fileReferences.joined(separator: ", "))\n\n"
        }
        
        return prompt
    }
    
    /// Estimate tokens for single-agent approach (for comparison)
    private func estimateSingleAgentTokens(task: AgentTask, context: AgentContext) async -> Int {
        let taskTokens = await TokenCounter().countTokens(task.description)
        let contextTokens = await TokenCounter().countTokens(context.conversationHistory)
        // Rough estimate: assume single agent would see full context + task
        return taskTokens + contextTokens + 500 // Add buffer for response
    }
    
    /// Aggregate multiple agent results into a single response (fallback method)
    private func aggregateResults(_ results: [AgentResult]) -> String {
        guard !results.isEmpty else {
            return "No results from agents."
        }
        
        if results.count == 1 {
            return results[0].content
        }
        
        var aggregated = "Combined results from \(results.count) agents:\n\n"
        
        for (index, result) in results.enumerated() {
            aggregated += "Agent \(index + 1) (\(result.agentId.uuidString.prefix(8))):\n"
            aggregated += "\(result.content)\n\n"
        }
        
        return aggregated
    }
    
    /// Check if coordinator is working (verification method)
    public func isCoordinatorWorking() -> Bool {
        // This would need to be called after execution to check metrics
        // For now, return true if we have metrics indicating successful delegation
        return metricsStorage.metrics != nil && (metricsStorage.metrics?.subtasksCreated ?? 0) > 0
    }
    
    /// Get delegation metrics
    public func getDelegationMetrics() -> DelegationMetrics? {
        return metricsStorage.metrics
    }
    
    /// Determine if the task should be delegated to specialized agents or handled directly
    /// - Parameters:
    ///   - task: The task to evaluate
    ///   - context: The current context
    /// - Returns: true if task should be delegated, false if coordinator should respond directly
    private func shouldDelegate(task: AgentTask, context: AgentContext) async throws -> Bool {
        print("🤔 OrchestratorPattern: Evaluating delegation decision for task '\(task.description.prefix(50))...'")
        
        // Build decision prompt with file information
        var decisionPrompt = """
            Analyze this task and decide: Should I respond directly or delegate to specialized agents?
            
            Task: \(task.description)
            """
        
        if !context.fileReferences.isEmpty {
            decisionPrompt += "\n\nAttached files: \(context.fileReferences.count) file(s)"
            decisionPrompt += "\n- Files require specialized file reading capabilities"
        }
        
        decisionPrompt += """
            
            Rules:
            - DIRECT if: greeting, simple question, basic conversation, simple follow-up
            - DELEGATE if: needs file/web/code/data tools, complex multi-step task, requires specialized capabilities, files are attached
            
            Respond with ONLY: "DIRECT" or "DELEGATE"
            If DIRECT, provide your response. If DELEGATE, explain why.
            """
        
        let decisionTask = AgentTask(
            description: decisionPrompt,
            requiredCapabilities: [.generalReasoning]
        )
        
        // Use minimal context for decision (just the task, no full history)
        // But include file references and conversationId so coordinator knows about files
        var decisionContext = AgentContext()
        decisionContext.conversationHistory = context.conversationHistory.suffix(2) // Only last 2 messages for context
        decisionContext.fileReferences = context.fileReferences // Include file references
        decisionContext.metadata = context.metadata // Include conversationId and other metadata
        
        let decisionResult = try await coordinator.process(task: decisionTask, context: decisionContext)
        let decisionText = decisionResult.content.uppercased()
        
        // Parse decision from response
        let shouldDelegate = parseDelegationDecision(from: decisionText)
        
        print("🤔 OrchestratorPattern: Decision result - \(shouldDelegate ? "DELEGATE" : "DIRECT")")
        if shouldDelegate {
            print("   Reason: \(decisionResult.content)")
        }
        
        return shouldDelegate
    }
    
    /// Parse delegation decision from coordinator's response
    /// - Parameter response: The coordinator's decision response
    /// - Returns: true if should delegate, false if should respond directly
    private func parseDelegationDecision(from response: String) -> Bool {
        // Look for explicit keywords
        if response.contains("DELEGATE") || response.contains("DELEGATION") {
            return true
        }
        
        if response.contains("DIRECT") || response.contains("RESPOND DIRECTLY") {
            return false
        }
        
        // Heuristic: If response looks like delegation instructions or mentions agents/tools, delegate
        let delegationKeywords = ["agent", "subtask", "delegate", "specialized", "tool", "file", "web", "search", "code", "analyze"]
        let hasDelegationKeywords = delegationKeywords.contains { keyword in
            response.lowercased().contains(keyword)
        }
        
        // Heuristic: If response is very short and conversational, likely direct response
        let isShortConversational = response.count < 200 && (
            response.lowercased().contains("hi") ||
            response.lowercased().contains("hello") ||
            response.lowercased().contains("thanks") ||
            response.lowercased().contains("thank you")
        )
        
        // Default: If we can't determine, delegate (safer default for complex tasks)
        if isShortConversational {
            return false
        }
        
        if hasDelegationKeywords {
            return true
        }
        
        // Fallback: If response looks like a direct answer (not instructions), treat as direct
        // Direct answers typically don't mention "agent", "subtask", "delegate", etc.
        return false
    }
    
    /// Respond directly without delegation (for simple tasks)
    /// - Parameters:
    ///   - task: The task to respond to
    ///   - context: The current context
    /// - Returns: Direct response from coordinator
    private func respondDirectly(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        print("💬 OrchestratorPattern: Coordinator responding directly to task")
        
        // Use coordinator to respond directly
        let directResult = try await coordinator.process(task: task, context: context)
        
        // Track tokens for direct response
        let prompt = try await buildPrompt(from: task, context: context)
        await tokenTracker.trackPrompt(agentId: coordinator.id, prompt: prompt)
        await tokenTracker.trackContext(agentId: coordinator.id, context: context)
        await tokenTracker.trackResponse(agentId: coordinator.id, response: directResult.content)
        
        return AgentResult(
            agentId: coordinator.id,
            taskId: task.id,
            content: directResult.content,
            success: directResult.success,
            error: directResult.error,
            toolCalls: directResult.toolCalls,
            updatedContext: directResult.updatedContext ?? context
        )
    }
}
