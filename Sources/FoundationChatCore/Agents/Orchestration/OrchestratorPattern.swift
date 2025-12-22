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
        context: AgentContext,
        progressTracker: OrchestrationProgressTracker? = nil
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
            let (shouldDelegate, decisionReason) = try await shouldDelegateWithReason(task: task, context: context)
            
            // Emit delegation decision event
            if let tracker = progressTracker {
                await tracker.emit(.delegationDecision(shouldDelegate: shouldDelegate, reason: decisionReason))
            }
            
            if !shouldDelegate {
                print("💬 OrchestratorPattern: Coordinator decided to respond directly (no delegation)")
                // Don't emit metrics here - respondDirectly() will calculate and emit proper metrics
                return try await respondDirectly(task: task, context: context, progressTracker: progressTracker)
            }
            
            print("🔄 OrchestratorPattern: Coordinator decided to delegate to specialized agents")
        }
        
        // Step 1: Use coordinator to analyze task and determine which agents are needed
        let analysisStartTime = Date()
        
        // Build comprehensive analysis task description with web search guidance
        var analysisTaskDescription = """
            # Task Analysis and Decomposition
            
            Your role is to analyze complex tasks and break them down into well-structured subtasks that can be executed by specialized agents. Follow these guidelines carefully.
            
            ## 1. Web Search Decision Framework
            
            **When to use Web Search Agent:**
            - The task requires current information, real-time data, or recent updates
            - The task asks about external knowledge not available in the codebase or files
            - The task involves facts, statistics, news, or information that changes over time
            - The task requires searching for documentation, tutorials, or best practices from external sources
            - The task asks "search for", "find information about", "look up", or similar web search requests
            
            **When NOT to use Web Search Agent:**
            - The task involves analyzing code, files, or data already in context
            - The task is a calculation or data analysis that doesn't require external information
            - The task can be answered from the conversation history or provided files
            - The task is about understanding or modifying existing code in the codebase
            
            ## 2. Web Search Query Best Practices
            
            When creating web search subtasks, structure queries effectively:
            
            **Good Query Examples:**
            - "Swift async await best practices 2024"
            - "Python pandas dataframe filtering tutorial"
            - "React useState hook examples and patterns"
            - "SQLite migration best practices"
            
            **Poor Query Examples:**
            - "stuff about Swift" (too vague)
            - "help" (not actionable)
            - "everything about programming" (too broad)
            
            **Query Guidelines:**
            - Be specific and focused on a single topic or question
            - Include relevant keywords that match how people search
            - Break complex topics into multiple focused searches if needed
            - Use natural language that search engines understand
            - Include year or version numbers for time-sensitive information
            
            ## 3. Task Decomposition Patterns
            
            **Pattern 1: Search then Analyze**
            ```
            Subtask 1: Search for [specific topic] using Web Search Agent
            Subtask 2: Analyze search results and extract key insights (depends on Subtask 1)
            Subtask 3: Synthesize findings into final answer (depends on Subtask 2)
            ```
            
            **Pattern 2: Parallel Searches**
            ```
            Subtask 1: Search for [topic A] using Web Search Agent (can run in parallel)
            Subtask 2: Search for [topic B] using Web Search Agent (can run in parallel)
            Subtask 3: Compare and synthesize both search results (depends on Subtasks 1 and 2)
            ```
            
            **Pattern 3: Sequential Search Chain**
            ```
            Subtask 1: Search for [foundational concept] using Web Search Agent
            Subtask 2: Search for [advanced topic] using Web Search Agent (depends on Subtask 1)
            Subtask 3: Analyze and combine both search results (depends on Subtask 2)
            ```
            
            **Key Principles:**
            - If a task requires web search, create a dedicated subtask for the search
            - Always create a follow-up subtask to analyze search results (don't just search and stop)
            - Break complex searches into multiple focused queries rather than one broad query
            - Make dependencies explicit: analysis subtasks depend on their search subtasks
            
            ## 4. Output Format Requirements
            
            For each subtask, you MUST specify:
            
            **Format:**
            ```
            #### Subtask N: [Clear, specific task description]
            
            **Specific Task Description:** [Detailed description of what needs to be done]
            **Agent to Handle:** [Agent name from available agents]
            **Capabilities Needed:** [List of required capabilities]
            **Dependencies:** [List any subtask numbers this depends on, or "None"]
            **Parallel Capability:** [Yes/No - can this run in parallel with other subtasks?]
            ```
            
            **Important:**
            - Use clear, actionable task descriptions (e.g., "Search the web for 'Swift async await best practices'")
            - Specify the exact agent name from the available agents list
            - List all dependencies explicitly (e.g., "Dependencies: Subtask 1")
            - Indicate if subtasks can run in parallel (default to Yes unless dependencies exist)
            
            ## 5. Available Agents
            
            \(agents.map { "**\($0.name)**: \($0.description) (capabilities: \($0.capabilities.map { $0.rawValue }.joined(separator: ", ")))" }.joined(separator: "\n\n"))
            """
        
        if !context.fileReferences.isEmpty {
            analysisTaskDescription += """
            
            ## 6. Attached Files
            
            This task has \(context.fileReferences.count) attached file(s).
            - If the task involves analyzing text files, code files, or documents, delegate to the File Reader agent
            - If the task involves analyzing images (photos, screenshots, diagrams, etc.), delegate to the Vision Agent
            - File analysis can often run in parallel with web searches if they're independent
            """
        }
        
        // Truncate task description if too long for analysis prompt
        let tokenCounter = TokenCounter()
        var taskDescriptionForAnalysis = task.description
        let taskTokens = await tokenCounter.countTokens(taskDescriptionForAnalysis)
        
        // Reserve tokens for the analysis prompt structure and context
        // The analysis prompt itself is quite long, so limit task description
        if taskTokens > 2000 {
            let maxChars = 2000 * 4 // Rough char-to-token conversion
            let truncated = String(taskDescriptionForAnalysis.prefix(maxChars))
            taskDescriptionForAnalysis = truncated + "\n\n[Full message content available in conversation history above]"
            print("⚠️ OrchestratorPattern: Truncated task description in analysis prompt from \(taskTokens) to ~2000 tokens")
        }
        
        analysisTaskDescription += """
            
            ## 7. Task to Analyze
            
            **Task:** \(taskDescriptionForAnalysis)
            
            Now analyze this task and provide a complete breakdown following all the guidelines above. Be thorough, specific, and ensure web search tasks are properly structured with clear queries and follow-up analysis subtasks.
            """
        
        let analysisTask = AgentTask(
            description: analysisTaskDescription,
            requiredCapabilities: [.generalReasoning]
        )
        
        // Track coordinator analysis tokens
        let analysisPrompt = try await buildPrompt(from: analysisTask, context: context)
        await tokenTracker.trackPrompt(agentId: coordinator.id, prompt: analysisPrompt)
        await tokenTracker.trackContext(agentId: coordinator.id, context: context)
        
        // Emit analysis started event
        if let tracker = progressTracker {
            await tracker.emit(.coordinatorAnalysisStarted)
        }
        
        let analysisResult = try await coordinator.process(task: analysisTask, context: context)
        coordinatorAnalysisTime = Date().timeIntervalSince(analysisStartTime)
        
        // Emit analysis completed event
        if let tracker = progressTracker {
            await tracker.emit(.coordinatorAnalysisCompleted(analysis: analysisResult.content))
        }
        
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
        
        // Emit task decomposition event if parsing succeeded
        if let decomposition = decomposition, let tracker = progressTracker {
            await tracker.emit(.taskDecomposition(decomposition: decomposition))
        }
        
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
                // Emit subtask pruned event
                if let tracker = progressTracker {
                    await tracker.emit(.subtaskPruned(subtaskId: id, rationale: rationale))
                }
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
                        previousResults: previousResults,
                        progressTracker: progressTracker
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
                                previousResults: previousResultsSnapshot,
                                progressTracker: progressTracker
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
        
        // Emit synthesis started event
        if let tracker = progressTracker {
            await tracker.emit(.synthesisStarted)
        }
        
        let synthesizedContent = try await synthesizeResults(results, context: updatedContext)
        coordinatorSynthesisTime = Date().timeIntervalSince(synthesisStartTime)
        
        // Emit synthesis completed event
        if let tracker = progressTracker {
            await tracker.emit(.synthesisCompleted)
        }
        
        await tokenTracker.trackPrompt(agentId: coordinator.id, prompt: "Synthesize results")
        await tokenTracker.trackResponse(agentId: coordinator.id, response: synthesizedContent)
        
        // Calculate metrics
        let totalTokens = await tokenTracker.getTotalTokenUsage()
        
        // Check for SVDB savings in context metadata and track them
        if let originalContextTokens = updatedContext.metadata["tokens_original_context"],
           let optimizedContextTokens = updatedContext.metadata["tokens_optimized_context"],
           let original = Int(originalContextTokens),
           let optimized = Int(optimizedContextTokens),
           original > optimized {
            // Track SVDB savings for coordinator (who received the optimized context)
            await tokenTracker.trackSVDBSavings(
                agentId: coordinator.id,
                originalTokens: original,
                optimizedTokens: optimized
            )
        }
        
        // Estimate single-agent tokens (assumes full conversation history)
        let singleAgentEstimate = await estimateSingleAgentTokens(task: task, context: context)
        
        // Calculate savings (now includes SVDB savings)
        let savingsPercentage = await tokenTracker.calculateSavings(singleAgentEstimate: singleAgentEstimate)
        
        // Get total SVDB savings for logging
        let totalSVDBSavings = await tokenTracker.getTotalSVDBSavings()
        
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
        
        if totalSVDBSavings > 0 {
            print("📊 OrchestratorPattern: Token usage - Total: \(totalTokens), SVDB Savings: \(totalSVDBSavings), Net Total: \(totalTokens - totalSVDBSavings), Overall Savings: \(String(format: "%.1f", savingsPercentage))%")
        } else {
            print("📊 OrchestratorPattern: Token usage - Total: \(totalTokens), Savings: \(String(format: "%.1f", savingsPercentage))%")
        }
        
        // Store token usage in context
        var finalContext = updatedContext
        finalContext = await tokenTracker.storeInContext(finalContext)
        finalContext.metadata["tokens_saved_vs_single_agent"] = String(format: "%.1f", savingsPercentage)
        
        // Store full results in toolResults for reference
        for (index, result) in results.enumerated() {
            finalContext.toolResults["agent_result_\(index)_full"] = result.content
        }
        
        // Emit orchestration completed event
        if let tracker = progressTracker, let metrics = metricsStorage.metrics {
            await tracker.emit(.orchestrationCompleted(metrics: metrics))
            await tracker.finish()
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
        previousResults: [AgentResult],
        progressTracker: OrchestrationProgressTracker? = nil
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
            // Emit subtask started with coordinator
            if let tracker = progressTracker {
                await tracker.emit(.subtaskStarted(subtask: subtask, agentId: coordinator.id, agentName: coordinator.name))
            }
            let result = try await coordinator.process(task: subtaskTask, context: context)
            // Emit subtask completed
            if let tracker = progressTracker {
                await tracker.emit(.subtaskCompleted(subtask: subtask, result: result))
            }
            return result
        }
        
        print("🤖 OrchestratorPattern: Selected agent '\(selectedAgent.name)' for subtask")
        
        // Emit subtask started event
        if let tracker = progressTracker {
            await tracker.emit(.subtaskStarted(subtask: subtask, agentId: selectedAgent.id, agentName: selectedAgent.name))
        }
        
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
        
        // Emit subtask completed event
        if let tracker = progressTracker {
            if result.success {
                await tracker.emit(.subtaskCompleted(subtask: subtask, result: result))
            } else {
                await tracker.emit(.subtaskFailed(subtask: subtask, error: result.error ?? "Unknown error"))
            }
        }
        
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
        let tokenCounter = TokenCounter()
        
        // Calculate available tokens for the prompt (reserve for system, tools, output)
        let maxPromptTokens = 3500 // Reserve ~600 tokens for system/tools/output
        let systemAndToolTokens = 200 // Rough estimate
        let outputReserve = 500
        let availableForContent = maxPromptTokens - systemAndToolTokens - outputReserve
        
        // Count tokens for conversation history
        let historyTokens = await tokenCounter.countTokens(context.conversationHistory)
        
        // Truncate task description if needed
        var taskDescription = task.description
        let taskTokens = await tokenCounter.countTokens(taskDescription)
        let availableForTask = max(100, availableForContent - historyTokens)
        
        if taskTokens > availableForTask {
            // Truncate task description
            let maxChars = availableForTask * 4 // Rough char-to-token conversion
            let truncated = String(taskDescription.prefix(maxChars))
            taskDescription = truncated + "\n\n[Message truncated due to length. Full content available in conversation history.]"
            print("⚠️ OrchestratorPattern: Truncated task description from \(taskTokens) to ~\(availableForTask) tokens")
        }
        
        var prompt = "Task: \(taskDescription)\n\n"
        
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
    /// Note: This assumes full conversation history is sent (baseline for comparison)
    private func estimateSingleAgentTokens(task: AgentTask, context: AgentContext) async -> Int {
        let tokenCounter = TokenCounter()
        
        // Calculate base input tokens
        let taskTokens = await tokenCounter.countTokens(task.description)
        
        // Use original context tokens if available (from SVDB optimization), otherwise use current
        let contextTokens: Int
        if let originalTokensStr = context.metadata["tokens_original_context"],
           let originalTokens = Int(originalTokensStr) {
            // Use original token count (before SVDB optimization) for accurate comparison
            contextTokens = originalTokens
        } else {
            // No SVDB optimization was applied, use current context tokens
            contextTokens = await tokenCounter.countTokens(context.conversationHistory)
        }
        
        let fileRefTokens = context.fileReferences.joined(separator: ", ").count / 4 // Rough estimate
        let baseInputTokens = taskTokens + contextTokens + fileRefTokens
        
        // Estimate response tokens: typical LLM responses are 1.5-3x input tokens
        // For complex tasks requiring research/analysis, use higher multiplier
        let requiresTools = !task.requiredCapabilities.isEmpty
        let responseMultiplier = requiresTools ? 3.0 : 2.0 // More tokens if tools are needed
        let estimatedResponseTokens = Int(Double(baseInputTokens) * responseMultiplier)
        
        // Add tool call overhead if task requires tools
        var toolCallTokens = 0
        if requiresTools {
            // Estimate tool calls: each tool call adds ~100-200 tokens (name + args + result)
            // For web search tasks, estimate 1-2 tool calls
            // For file reading, estimate 1 tool call per file
            if task.requiredCapabilities.contains(.webSearch) {
                toolCallTokens = 300 // Search query + results
            } else if task.requiredCapabilities.contains(.fileReading) {
                toolCallTokens = 200 * max(1, context.fileReferences.count)
            } else {
                toolCallTokens = 200 // Generic tool call overhead
            }
        }
        
        // Add overhead for multiple interaction rounds if task is complex
        // Complex tasks might need follow-up prompts
        let complexityOverhead = task.description.count > 200 ? 500 : 0
        
        let totalEstimate = baseInputTokens + estimatedResponseTokens + toolCallTokens + complexityOverhead
        
        print("📊 OrchestratorPattern: Single-agent estimate - Input: \(baseInputTokens), Response: \(estimatedResponseTokens), Tools: \(toolCallTokens), Overhead: \(complexityOverhead), Total: \(totalEstimate)")
        
        return totalEstimate
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
    
    /// Determine if the task should be delegated to specialized agents or handled directly (with reason)
    /// - Parameters:
    ///   - task: The task to evaluate
    ///   - context: The current context
    /// - Returns: Tuple of (shouldDelegate, reason)
    private func shouldDelegateWithReason(task: AgentTask, context: AgentContext) async throws -> (Bool, String?) {
        let result = try await shouldDelegateInternal(task: task, context: context)
        return (result.shouldDelegate, result.reason)
    }
    
    /// Determine if the task should be delegated to specialized agents or handled directly
    /// - Parameters:
    ///   - task: The task to evaluate
    ///   - context: The current context
    /// - Returns: true if task should be delegated, false if coordinator should respond directly
    private func shouldDelegate(task: AgentTask, context: AgentContext) async throws -> Bool {
        let result = try await shouldDelegateInternal(task: task, context: context)
        return result.shouldDelegate
    }
    
    /// Internal method that returns both decision and reason
    private func shouldDelegateInternal(task: AgentTask, context: AgentContext) async throws -> (shouldDelegate: Bool, reason: String?) {
        print("🤔 OrchestratorPattern: Evaluating delegation decision for task '\(task.description.prefix(50))...'")
        
        // Truncate task description for decision prompt if too long
        let tokenCounter = TokenCounter()
        var taskDescription = task.description
        let taskTokens = await tokenCounter.countTokens(taskDescription)
        
        // Limit decision prompt task description to ~500 tokens to avoid context window issues
        if taskTokens > 500 {
            let maxChars = 500 * 4 // Rough char-to-token conversion
            let truncated = String(taskDescription.prefix(maxChars))
            taskDescription = truncated + "\n\n[Message truncated - full content available if delegated]"
        }
        
        // Build decision prompt with file information
        var decisionPrompt = """
            Analyze this task and decide: Should I respond directly or delegate to specialized agents?
            
            Task: \(taskDescription)
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
        
        return (shouldDelegate, shouldDelegate ? decisionResult.content : nil)
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
    ///   - progressTracker: Optional progress tracker for visualization
    /// - Returns: Direct response from coordinator
    private func respondDirectly(
        task: AgentTask,
        context: AgentContext,
        progressTracker: OrchestrationProgressTracker?
    ) async throws -> AgentResult {
        print("💬 OrchestratorPattern: Coordinator responding directly to task")
        
        let responseStartTime = Date()
        
        // Use coordinator to respond directly
        let directResult = try await coordinator.process(task: task, context: context)
        
        let responseTime = Date().timeIntervalSince(responseStartTime)
        
        // Track tokens for direct response
        let prompt = try await buildPrompt(from: task, context: context)
        await tokenTracker.trackPrompt(agentId: coordinator.id, prompt: prompt)
        await tokenTracker.trackContext(agentId: coordinator.id, context: context)
        await tokenTracker.trackResponse(agentId: coordinator.id, response: directResult.content)
        
        // Track tool calls if any
        if !directResult.toolCalls.isEmpty {
            await tokenTracker.trackToolCalls(agentId: coordinator.id, toolCalls: directResult.toolCalls)
        }
        
        // Calculate total tokens
        let totalTokens = await tokenTracker.getTotalTokenUsage()
        
        // Check for SVDB savings in context metadata and track them
        var updatedContext = directResult.updatedContext ?? context
        if let originalContextTokens = updatedContext.metadata["tokens_original_context"],
           let optimizedContextTokens = updatedContext.metadata["tokens_optimized_context"],
           let original = Int(originalContextTokens),
           let optimized = Int(optimizedContextTokens),
           original > optimized {
            // Track SVDB savings for coordinator
            await tokenTracker.trackSVDBSavings(
                agentId: coordinator.id,
                originalTokens: original,
                optimizedTokens: optimized
            )
        }
        
        // Estimate single-agent tokens (assumes full conversation history)
        let singleAgentEstimate = await estimateSingleAgentTokens(task: task, context: context)
        
        // Calculate savings (now includes SVDB savings)
        let savingsPercentage = await tokenTracker.calculateSavings(singleAgentEstimate: singleAgentEstimate)
        
        // Get total SVDB savings for logging
        let totalSVDBSavings = await tokenTracker.getTotalSVDBSavings()
        
        // Store metrics
        metricsStorage.metrics = DelegationMetrics(
            subtasksCreated: 0,
            subtasksPruned: 0,
            agentsUsed: 1,
            totalTokens: totalTokens,
            tokenSavingsPercentage: savingsPercentage,
            executionTimeBreakdown: ExecutionTimeBreakdown(
                coordinatorAnalysisTime: 0.0,
                coordinatorSynthesisTime: 0.0,
                specializedAgentsTime: responseTime
            )
        )
        
        if totalSVDBSavings > 0 {
            print("📊 OrchestratorPattern: Direct response - Total: \(totalTokens), SVDB Savings: \(totalSVDBSavings), Net Total: \(totalTokens - totalSVDBSavings), Overall Savings: \(String(format: "%.1f", savingsPercentage))%")
        } else {
            print("📊 OrchestratorPattern: Direct response - Total: \(totalTokens), Savings: \(String(format: "%.1f", savingsPercentage))%")
        }
        
        // Store token usage in context metadata
        updatedContext = await tokenTracker.storeInContext(updatedContext)
        updatedContext.metadata["tokens_saved_vs_single_agent"] = String(format: "%.1f", savingsPercentage)
        
        // Emit orchestration completed event with proper metrics
        if let tracker = progressTracker, let metrics = metricsStorage.metrics {
            await tracker.emit(.orchestrationCompleted(metrics: metrics))
            await tracker.finish()
        }
        
        return AgentResult(
            agentId: coordinator.id,
            taskId: task.id,
            content: directResult.content,
            success: directResult.success,
            error: directResult.error,
            toolCalls: directResult.toolCalls,
            updatedContext: updatedContext
        )
    }
}
