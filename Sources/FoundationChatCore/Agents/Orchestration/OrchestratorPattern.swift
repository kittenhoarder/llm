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
    
    /// Retry configuration
    private let retryConfiguration: RetryConfiguration
    
    /// Conditional branch evaluator
    private let branchEvaluator: ConditionalBranchEvaluator
    
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
        budgetGuard: TokenBudgetGuard = TokenBudgetGuard(),
        retryConfiguration: RetryConfiguration = RetryConfiguration(),
        branchEvaluator: ConditionalBranchEvaluator = ConditionalBranchEvaluator()
    ) {
        self.coordinator = coordinator
        self.parser = parser
        self.pruner = pruner
        self.contextBuilder = contextBuilder
        self.resultSummarizer = resultSummarizer
        self.tokenTracker = tokenTracker
        self.budgetGuard = budgetGuard
        self.retryConfiguration = retryConfiguration
        self.branchEvaluator = branchEvaluator
    }
    
    public func execute(
        task: AgentTask,
        agents: [any Agent],
        context: AgentContext,
        progressTracker: OrchestrationProgressTracker? = nil,
        checkpointCallback: (@Sendable (WorkflowCheckpoint) async throws -> Void)? = nil,
        cancellationToken: WorkflowCancellationToken? = nil
    ) async throws -> AgentResult {
        // #region debug log
        let agentNames = agents.map { $0.name }
        let agentIds = agents.map { $0.id.uuidString }
        let agentCapabilitiesDict = Dictionary(uniqueKeysWithValues: agents.map { ($0.name, Array($0.capabilities.map { $0.rawValue })) })
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:execute",
            message: "execute() called with agents array",
            hypothesisId: "A,D",
            data: [
                "agentCount": agents.count,
                "agentNames": agentNames,
                "agentIds": agentIds,
                "agentCapabilities": agentCapabilitiesDict,
                "hasRAGChunks": !context.ragChunks.isEmpty,
                "ragChunksCount": context.ragChunks.count,
                "fileReferencesCount": context.fileReferences.count
            ]
        )
        // #endregion
        let _ = Date()
        var coordinatorAnalysisTime: TimeInterval = 0
        var coordinatorSynthesisTime: TimeInterval = 0
        var specializedAgentsTime: TimeInterval = 0
        
        Log.debug("🎯 OrchestratorPattern: Starting execution for task '\(task.description.prefix(50))...'")
        
        // Fast-path: if an image is attached, bypass LLM-based decomposition and route directly to Vision Agent.
        // This avoids incorrect plans like "web search for local file path" and ensures the image is actually analyzed.
        let currentAttachments = currentAttachmentPaths(from: context)
        if let imagePath = firstImagePath(in: currentAttachments),
           let visionAgent = agents.first(where: { $0.capabilities.contains(.imageAnalysis) || $0.name == AgentName.visionAgent }) {
            let start = Date()
            Log.debug("🖼️ OrchestratorPattern: Image attachment detected, routing directly to Vision Agent (\(visionAgent.name))")
            
            if let tracker = progressTracker {
                await tracker.emit(.delegationDecision(
                    shouldDelegate: true,
                    reason: "Image attachment detected; delegating directly to Vision Agent."
                ))
            }
            
            let subtask = DecomposedSubtask(
                description: "Describe/analyze attached image \(URL(fileURLWithPath: imagePath).lastPathComponent)",
                agentName: visionAgent.name,
                requiredCapabilities: [.imageAnalysis],
                canExecuteInParallel: false
            )
            let decomposition = TaskDecomposition(subtasks: [subtask])
            if let tracker = progressTracker {
                await tracker.emit(.taskDecomposition(decomposition: decomposition))
                await tracker.emit(.subtaskStarted(subtask: subtask, agentId: visionAgent.id, agentName: visionAgent.name))
            }
            
            let visionTask = AgentTask(
                description: task.description,
                requiredCapabilities: [.imageAnalysis],
                parameters: ["imagePath": imagePath]
            )
            let result = try await visionAgent.process(task: visionTask, context: context)
            
            if let tracker = progressTracker {
                await tracker.emit(.subtaskCompleted(subtask: subtask, result: result))
                await tracker.emit(.synthesisStarted)
                await tracker.emit(.synthesisCompleted)
            }
            
            // Best-effort metrics (specialized agent prompts aren't tracked by AgentTokenTracker today)
            let tokenCounter = TokenCounter()
            let inputTokens = await tokenCounter.countTokens(task.description)
            let outputTokens = await tokenCounter.countTokens(result.content)
            let totalTokens = inputTokens + outputTokens
            
            metricsStorage.metrics = DelegationMetrics(
                subtasksCreated: 1,
                subtasksPruned: 0,
                agentsUsed: 1,
                totalTokens: totalTokens,
                tokenSavingsPercentage: 0.0,
                executionTimeBreakdown: ExecutionTimeBreakdown(
                    coordinatorAnalysisTime: 0.0,
                    coordinatorSynthesisTime: 0.0,
                    specializedAgentsTime: Date().timeIntervalSince(start)
                )
            )
            
            if let tracker = progressTracker, let metrics = metricsStorage.metrics {
                await tracker.emit(.orchestrationCompleted(metrics: metrics))
                await tracker.finish()
            }
            
            specializedAgentsTime += Date().timeIntervalSince(start)
            return result
        }
        
        // Check for cancellation
        try cancellationToken?.checkCancellation()
        
        // Check if smart delegation is enabled (default: true if key doesn't exist)
        let smartDelegationEnabled: Bool
        if UserDefaults.standard.object(forKey: UserDefaultsKey.smartDelegation) != nil {
            smartDelegationEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKey.smartDelegation)
        } else {
            smartDelegationEnabled = true // Default to enabled
        }
        if smartDelegationEnabled {
            // Step 0: Decision step - should we delegate or respond directly?
            let (shouldDelegate, decisionReason) = try await shouldDelegateWithReason(task: task, context: context, agents: agents)
            
            // Emit delegation decision event
            if let tracker = progressTracker {
                await tracker.emit(.delegationDecision(shouldDelegate: shouldDelegate, reason: decisionReason))
            }
            
            if !shouldDelegate {
                Log.debug("💬 OrchestratorPattern: Coordinator decided to respond directly (no delegation)")
                // Don't emit metrics here - respondDirectly() will calculate and emit proper metrics
                return try await respondDirectly(task: task, context: context, progressTracker: progressTracker)
            }
            
            Log.debug("🔄 OrchestratorPattern: Coordinator decided to delegate to specialized agents")
        }
        
        // Step 1: Use coordinator to analyze task and determine which agents are needed
        let analysisStartTime = Date()
        
        let availableCapabilities = Set(agents.flatMap { $0.capabilities })
        let hasWebSearch = availableCapabilities.contains(.webSearch)
        let hasFileReader = availableCapabilities.contains(.fileReading)
        let hasVision = availableCapabilities.contains(.imageAnalysis)
        
        // Build comprehensive analysis task description with dynamic guidance
        // Initialize RAG content variable
        var ragContent = ""
        
        // Truncate task description if too long for analysis prompt (do this BEFORE adding RAG chunks)
        let tokenCounter = TokenCounter()
        var taskDescriptionForAnalysis = task.description
        let taskTokens = await tokenCounter.countTokens(taskDescriptionForAnalysis)
        
        let maxTaskTokens = 2000
        if taskTokens > maxTaskTokens {
            let maxChars = maxTaskTokens * 4 // Rough char-to-token conversion
            let truncated = String(taskDescriptionForAnalysis.prefix(maxChars))
            taskDescriptionForAnalysis = truncated + "\n\n[Full message content available in conversation history above]"
            Log.warn("⚠️ OrchestratorPattern: Truncated task description in analysis prompt from \(taskTokens) to ~\(maxTaskTokens) tokens")
        }
        
        // Add RAG chunks if available, with token-aware truncation
        if !context.ragChunks.isEmpty {
            // Calculate available tokens for RAG chunks
            let maxPromptTokens = 4096
            let reservedTokens = 2000 + 500 + 500 // prompt structure + task + output reserve
            let availableForRAG = max(0, maxPromptTokens - reservedTokens - Int(taskTokens))
            
            var ragTokensUsed = 0
            
            // Add chunks until we run out of token budget
            for chunk in context.ragChunks.prefix(5) {
                let chunkText = ragContent.isEmpty ? chunk.content : "\n\n---\n\n\(chunk.content)"
                let chunkTokens = await tokenCounter.countTokens(chunkText)
                
                if ragTokensUsed + chunkTokens <= availableForRAG {
                    ragContent += chunkText
                    ragTokensUsed += chunkTokens
                } else {
                    // Truncate this chunk to fit remaining budget
                    let remainingTokens = max(0, availableForRAG - ragTokensUsed)
                    if remainingTokens > 100 { // Only add if we have meaningful space
                        let maxChars = remainingTokens * 4
                        let truncatedChunk = String(chunk.content.prefix(maxChars))
                        ragContent += ragContent.isEmpty ? truncatedChunk : "\n\n---\n\n\(truncatedChunk)"
                        ragContent += "\n\n[Additional content truncated due to token limits]"
                    }
                    break
                }
            }
            
            if !ragContent.isEmpty {
                Log.debug("📄 OrchestratorPattern: Added \(ragTokensUsed) tokens of RAG content to analysis prompt")
            }
        }
        
        // Use the optimized prompt template
        var analysisTaskDescription = PromptTemplates.orchestratorAnalysis(
            task: taskDescriptionForAnalysis,
            agents: agents,
            fileReferences: context.fileReferences,
            hasWebSearch: hasWebSearch,
            ragContent: ragContent.isEmpty ? nil : ragContent
        )
        
        // Final token check on analysis task description before creating task
        let analysisTaskTokens = await tokenCounter.countTokens(analysisTaskDescription)
        let maxAnalysisTaskTokens = 3500 // Reserve ~600 for system/tools/output
        if analysisTaskTokens > maxAnalysisTaskTokens {
            Log.warn("⚠️ OrchestratorPattern: Analysis task description exceeds budget (\(analysisTaskTokens) > \(maxAnalysisTaskTokens)), truncating...")
            let maxChars = maxAnalysisTaskTokens * 4
            analysisTaskDescription = String(analysisTaskDescription.prefix(maxChars)) + "\n\n[Analysis prompt truncated due to length]"
        }
        
        var analysisTask = AgentTask(
            description: analysisTaskDescription,
            requiredCapabilities: [.generalReasoning]
        )
        
        // Track coordinator analysis tokens
        var analysisPrompt = try await buildPrompt(from: analysisTask, context: context)
        
        // Final safety check - ensure prompt doesn't exceed 4096 tokens
        let finalAnalysisPromptTokens = await tokenCounter.countTokens(analysisPrompt)
        if finalAnalysisPromptTokens > 4096 {
            Log.warn("⚠️ OrchestratorPattern: Analysis prompt exceeds 4096 tokens (\(finalAnalysisPromptTokens)), truncating aggressively...")
            let maxChars = 3500 * 4 // Reserve more aggressively for system/tools/output
            analysisPrompt = String(analysisPrompt.prefix(maxChars)) + "\n\n[Prompt truncated due to context window limits]"
            
            // #region debug log
            await DebugLogger.shared.log(
                location: "OrchestratorPattern.swift:execute",
                message: "Analysis prompt truncated due to context window",
                hypothesisId: "B",
                data: [
                    "originalTokens": finalAnalysisPromptTokens,
                    "truncatedTokens": await tokenCounter.countTokens(analysisPrompt),
                    "ragChunksCount": context.ragChunks.count
                ]
            )
            // #endregion
            
            // Update the task with truncated prompt
            analysisTask = AgentTask(
                description: analysisPrompt,
                requiredCapabilities: [.generalReasoning]
            )
        }
        
        // Also check if this is a synthesis prompt and enforce stricter limits
        let isSynthesisPrompt = analysisTask.description.contains("Synthesize") || analysisTask.description.contains("synthesis")
        if isSynthesisPrompt {
            // For synthesis, be more aggressive with token limits
            let synthesisMaxTokens = 3000 // Reserve more for system/tools/output
            if finalAnalysisPromptTokens > synthesisMaxTokens {
                let maxChars = synthesisMaxTokens * 4
                analysisPrompt = String(analysisPrompt.prefix(maxChars)) + "\n\n[Synthesis prompt truncated due to length]"
                analysisTask = AgentTask(
                    description: analysisPrompt,
                    requiredCapabilities: [.generalReasoning]
                )
                Log.warn("⚠️ OrchestratorPattern: Synthesis prompt truncated from \(finalAnalysisPromptTokens) to ~\(synthesisMaxTokens) tokens")
            }
        }
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:execute",
            message: "Coordinator analysis prompt built",
            hypothesisId: "B,D",
            data: [
                "promptLength": analysisPrompt.count,
                "promptTokens": await tokenCounter.countTokens(analysisPrompt),
                "promptPreview": String(analysisPrompt.prefix(2000)),
                "hasRAGChunksInPrompt": analysisPrompt.contains("Relevant Document Content") || analysisPrompt.contains("from attached files"),
                "hasRAGChunksInAnalysisTask": analysisTaskDescription.contains("Relevant Document Content"),
                "availableAgentsInPrompt": analysisPrompt.contains("Available Agents"),
                "ragChunksCount": context.ragChunks.count,
                "ragChunksInContext": context.ragChunks.map { String($0.content.prefix(100)) }
            ]
        )
        // #endregion
        
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
        
        Log.debug("📊 OrchestratorPattern: Coordinator analysis completed in \(String(format: "%.2f", coordinatorAnalysisTime))s")
        Log.debug("📝 OrchestratorPattern: Coordinator analysis output:\n\(analysisResult.content)")
        
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
        var finalDecomposition = prunedResult.decomposition
        
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
        
        Log.debug("✂️ OrchestratorPattern: Pruned \(subtasksPruned) subtasks, \(finalDecomposition.subtasks.count) remaining")
        if !prunedResult.removalRationales.isEmpty {
            for (id, rationale) in prunedResult.removalRationales {
                Log.debug("  - Removed subtask \(id.uuidString.prefix(8)): \(rationale)")
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
            Log.warn("⚠️ OrchestratorPattern: No subtasks parsed, falling back to capability-based matching")
            return try await fallbackExecution(task: task, agents: agents, context: context)
        }
        
        // Create checkpoint after decomposition (pre-execution)
        if let callback = checkpointCallback {
            await createCheckpoint(
                phase: .decomposition,
                orchestrationState: OrchestrationState(
                    currentPhase: .decomposition,
                    decomposition: finalDecomposition,
                    subtaskStates: Dictionary(uniqueKeysWithValues: finalDecomposition.subtasks.map { ($0.id, SubtaskExecutionState.pending) })
                ),
                task: task,
                context: context,
                agents: agents,
                callback: callback
            )
        }
        
        // Get parallelizable groups
        let parallelGroups = finalDecomposition.getParallelizableGroups()
        Log.debug("🔄 OrchestratorPattern: Executing \(parallelGroups.count) groups of subtasks")
        
        let specializedStartTime = Date()
        
        // Execute groups sequentially, but subtasks within groups in parallel
        for (groupIndex, group) in parallelGroups.enumerated() {
            Log.debug("📦 OrchestratorPattern: Executing group \(groupIndex + 1)/\(parallelGroups.count) with \(group.count) subtasks")
            
            if group.count == 1 || !group.allSatisfy({ $0.canExecuteInParallel }) {
                // Sequential execution
                for subtask in group {
                    // Check for cancellation before each subtask
                    try cancellationToken?.checkCancellation()
                    
                    let result = try await executeSubtask(
                        subtask: subtask,
                        agents: agents,
                        context: updatedContext,
                        previousResults: previousResults,
                        progressTracker: progressTracker,
                        cancellationToken: cancellationToken
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
                
                    // Check for cancellation before parallel execution
                    try cancellationToken?.checkCancellation()
                    
                    try await withThrowingTaskGroup(of: AgentResult.self) { taskGroup in
                        for subtask in group {
                            taskGroup.addTask {
                                // Check for cancellation in each parallel task
                                try cancellationToken?.checkCancellation()
                                
                                return try await self.executeSubtask(
                                    subtask: subtask,
                                    agents: agents,
                                    context: contextSnapshot,
                                    previousResults: previousResultsSnapshot,
                                    progressTracker: progressTracker,
                                    cancellationToken: cancellationToken
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
            
            // Evaluate conditional branches after each group
            let resultsMap = Dictionary(uniqueKeysWithValues: results.map { ($0.taskId, $0) })
            let newSubtasks = try await evaluateConditionalBranches(
                decomposition: finalDecomposition,
                results: resultsMap,
                agents: agents
            )
            
            if !newSubtasks.isEmpty {
                Log.debug("🔄 OrchestratorPattern: Adding \(newSubtasks.count) dynamically created subtasks from conditional branches")
                finalDecomposition.addSubtasks(newSubtasks)
                
                // Recalculate parallel groups with new subtasks
                let updatedParallelGroups = finalDecomposition.getParallelizableGroups()
                
                // Add new groups that can be executed
                if updatedParallelGroups.count > parallelGroups.count {
                    // There are new groups to execute
                    let newGroups = Array(updatedParallelGroups[parallelGroups.count...])
                    for newGroup in newGroups {
                        Log.debug("📦 OrchestratorPattern: Executing new group with \(newGroup.count) dynamically created subtasks")
                        
                        if newGroup.count == 1 || !newGroup.allSatisfy({ $0.canExecuteInParallel }) {
                            // Sequential execution
                            for subtask in newGroup {
                                let result = try await executeSubtask(
                                    subtask: subtask,
                                    agents: agents,
                                    context: updatedContext,
                                    previousResults: previousResults,
                                    progressTracker: progressTracker,
                                    cancellationToken: cancellationToken
                                )
                                results.append(result)
                                previousResults.append(result)
                                
                                if let updated = result.updatedContext {
                                    updatedContext.merge(updated)
                                }
                            }
                        } else {
                            // Parallel execution
                            let contextSnapshot = updatedContext
                            let previousResultsSnapshot = previousResults
                            
                            try await withThrowingTaskGroup(of: AgentResult.self) { taskGroup in
                                for subtask in newGroup {
                                    taskGroup.addTask {
                                        try cancellationToken?.checkCancellation()
                                        
                                        return try await self.executeSubtask(
                                            subtask: subtask,
                                            agents: agents,
                                            context: contextSnapshot,
                                            previousResults: previousResultsSnapshot,
                                            progressTracker: progressTracker,
                                            cancellationToken: cancellationToken
                                        )
                                    }
                                }
                                
                                var groupResults: [AgentResult] = []
                                for try await result in taskGroup {
                                    groupResults.append(result)
                                }
                                
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
                }
            }
        }
        
        specializedAgentsTime = Date().timeIntervalSince(specializedStartTime)
        Log.debug("✅ OrchestratorPattern: All specialized agents completed in \(String(format: "%.2f", specializedAgentsTime))s")
        
        // Check for cancellation before synthesis
        try cancellationToken?.checkCancellation()
        
        // Step 5: Synthesize results using coordinator
        let synthesisStartTime = Date()
        
        // Emit synthesis started event
        if let tracker = progressTracker {
            await tracker.emit(.synthesisStarted)
        }
        
        let synthesizedContent = try await synthesizeResults(results, context: updatedContext, originalTask: task, agents: agents)
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
        
        // Estimate single-agent tokens (assumes full conversation history and full file content)
        // Use updatedContext which has merged metadata from all agent results
        let singleAgentEstimate = await estimateSingleAgentTokens(task: task, context: updatedContext)
        
        // Add file content savings to the tracker if available
        // Check updatedContext (merged from all agent results) for file content savings
        if let fileSavingsStr = updatedContext.metadata["tokens_file_content_saved"],
           let fileSavings = Int(fileSavingsStr),
           fileSavings > 0 {
            // Track file content savings at coordinator level since it benefits overall orchestration
            // The savings are already reflected in the actual token usage, so we adjust the estimate
            await tokenTracker.trackSVDBSavings(
                agentId: coordinator.id,
                originalTokens: singleAgentEstimate,
                optimizedTokens: singleAgentEstimate - fileSavings
            )
        }
        
        // Calculate savings (now includes SVDB savings and file content savings)
        let savingsPercentage = await tokenTracker.calculateSavings(singleAgentEstimate: singleAgentEstimate)
        
        // Get total SVDB savings for logging (includes file content savings)
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
            Log.debug("📊 OrchestratorPattern: Token usage - Total: \(totalTokens), SVDB Savings: \(totalSVDBSavings), Net Total: \(totalTokens - totalSVDBSavings), Overall Savings: \(String(format: "%.1f", savingsPercentage))%")
        } else {
            Log.debug("📊 OrchestratorPattern: Token usage - Total: \(totalTokens), Savings: \(String(format: "%.1f", savingsPercentage))%")
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
    
    /// Execute a single subtask with retry logic
    private func executeSubtask(
        subtask: DecomposedSubtask,
        agents: [any Agent],
        context: AgentContext,
        previousResults: [AgentResult],
        progressTracker: OrchestrationProgressTracker? = nil,
        cancellationToken: WorkflowCancellationToken? = nil
    ) async throws -> AgentResult {
        Log.debug("🎯 OrchestratorPattern: Executing subtask '\(subtask.description.prefix(50))...'")
        
        // Find matching agent
        let agent = await findAgent(for: subtask, in: agents)
        
        guard let selectedAgent = agent else {
            Log.warn("⚠️ OrchestratorPattern: No agent found for subtask, using coordinator")
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
        
        // Get retry policy for this agent and subtask
        let retryPolicy = retryConfiguration.policy(for: selectedAgent, subtask: subtask)
        
        // Execute with retry logic
        var attemptNumber = 0
        var retryAttempts: [RetryAttempt] = []
        
        while true {
            // Check for cancellation before each attempt
            try cancellationToken?.checkCancellation()
            
            Log.debug("🤖 OrchestratorPattern: Selected agent '\(selectedAgent.name)' for subtask (attempt \(attemptNumber + 1)/\(retryPolicy.maxAttempts))")
            
            // Emit subtask started event (or retry event)
            if let tracker = progressTracker {
                if attemptNumber == 0 {
                    await tracker.emit(.subtaskStarted(subtask: subtask, agentId: selectedAgent.id, agentName: selectedAgent.name))
                } else {
                    let delay = retryPolicy.delay(for: attemptNumber - 1)
                    let previousError = retryAttempts.last?.error ?? "Unknown error"
                    await tracker.emit(.subtaskRetry(subtask: subtask, attemptNumber: attemptNumber, delay: delay, previousError: previousError))
                }
            }
            
            // Wait for retry delay if this is a retry
            if attemptNumber > 0 {
                let delay = retryPolicy.delay(for: attemptNumber - 1)
                if delay > 0 {
                    Log.debug("⏳ OrchestratorPattern: Waiting \(delay)s before retry attempt \(attemptNumber + 1)...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            
            do {
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
                
                // Check if result indicates success
                if result.success {
                    Log.debug("✅ OrchestratorPattern: Subtask completed by '\(selectedAgent.name)'")
                    
                    // Emit subtask completed event
                    if let tracker = progressTracker {
                        await tracker.emit(.subtaskCompleted(subtask: subtask, result: result))
                    }
                    
                    return result
                } else {
                    // Result indicates failure but no exception thrown
                    let errorMessage = result.error ?? "Unknown error"
                    Log.warn("⚠️ OrchestratorPattern: Subtask failed: \(errorMessage)")
                    
                    // Record retry attempt
                    let retryAttempt = RetryAttempt(
                        attemptNumber: attemptNumber,
                        timestamp: Date(),
                        error: errorMessage,
                        delayBeforeAttempt: attemptNumber > 0 ? retryPolicy.delay(for: attemptNumber - 1) : 0
                    )
                    retryAttempts.append(retryAttempt)
                    
                    // Check if we should retry
                    if retryPolicy.shouldRetry(attemptNumber: attemptNumber) {
                        attemptNumber += 1
                        continue
                    } else {
                        // Max retries reached
                        if let tracker = progressTracker {
                            await tracker.emit(.subtaskFailed(subtask: subtask, error: errorMessage))
                        }
                        return result
                    }
                }
            } catch {
                // Exception thrown during execution
                let errorMessage = error.localizedDescription
                Log.error("❌ OrchestratorPattern: Subtask execution threw error: \(errorMessage)")
                
                // Record retry attempt
                let retryAttempt = RetryAttempt(
                    attemptNumber: attemptNumber,
                    timestamp: Date(),
                    error: errorMessage,
                    delayBeforeAttempt: attemptNumber > 0 ? retryPolicy.delay(for: attemptNumber - 1) : 0
                )
                retryAttempts.append(retryAttempt)
                
                // Check if we should retry
                if retryPolicy.shouldRetry(attemptNumber: attemptNumber) {
                    attemptNumber += 1
                    continue
                } else {
                    // Max retries reached, rethrow the error
                    if let tracker = progressTracker {
                        await tracker.emit(.subtaskFailed(subtask: subtask, error: errorMessage))
                    }
                    throw error
                }
            }
        }
    }
    
    /// Find agent for a subtask
    private func findAgent(for subtask: DecomposedSubtask, in agents: [any Agent]) async -> (any Agent)? {
        // #region debug log
        let agentNames = agents.map { $0.name }
        let agentIds = agents.map { $0.id.uuidString }
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:findAgent",
            message: "findAgent() called",
            hypothesisId: "A,B,C",
            data: [
                "subtaskDescription": String(subtask.description.prefix(100)),
                "subtaskAgentName": subtask.agentName ?? "none",
                "requiredCapabilities": Array(subtask.requiredCapabilities).map { $0.rawValue },
                "availableAgentCount": agents.count,
                "availableAgentNames": agentNames,
                "availableAgentIds": agentIds
            ]
        )
        // #endregion
        // First try to match by name
        if let agentName = subtask.agentName {
            if let agent = agents.first(where: { $0.name == agentName }) {
                // #region debug log
                await DebugLogger.shared.log(
                    location: "OrchestratorPattern.swift:findAgent",
                    message: "Matched agent by name",
                    hypothesisId: "A",
                    data: [
                        "matchedAgentName": agent.name,
                        "matchedAgentId": agent.id.uuidString
                    ]
                )
                // #endregion
                return agent
            }
        }
        
        // Then try to match by capabilities
        if !subtask.requiredCapabilities.isEmpty {
            let matchingAgents = agents.filter { agent in
                !subtask.requiredCapabilities.isDisjoint(with: agent.capabilities)
            }
            
            // #region debug log
            let matchingNames = matchingAgents.map { $0.name }
            await DebugLogger.shared.log(
                location: "OrchestratorPattern.swift:findAgent",
                message: "Matching by capabilities",
                hypothesisId: "A,B",
                data: [
                    "matchingAgentCount": matchingAgents.count,
                    "matchingAgentNames": matchingNames,
                    "matchingAgentIds": matchingAgents.map { $0.id.uuidString }
                ]
            )
            // #endregion
            
            // Prefer agents that match all required capabilities
            if let perfectMatch = matchingAgents.first(where: { subtask.requiredCapabilities.isSubset(of: $0.capabilities) }) {
                // #region debug log
                await DebugLogger.shared.log(
                    location: "OrchestratorPattern.swift:findAgent",
                    message: "Found perfect match",
                    hypothesisId: "A",
                    data: [
                        "matchedAgentName": perfectMatch.name,
                        "matchedAgentId": perfectMatch.id.uuidString
                    ]
                )
                // #endregion
                return perfectMatch
            }
            
            // Otherwise return first match
            if let firstMatch = matchingAgents.first {
                // #region debug log
                await DebugLogger.shared.log(
                    location: "OrchestratorPattern.swift:findAgent",
                    message: "Returning first capability match",
                    hypothesisId: "A",
                    data: [
                        "matchedAgentName": firstMatch.name,
                        "matchedAgentId": firstMatch.id.uuidString
                    ]
                )
                // #endregion
                return firstMatch
            }
        }
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "OrchestratorPattern.swift:findAgent",
            message: "No agent found",
            hypothesisId: "A",
            data: [:]
        )
        // #endregion
        return nil
    }
    
    /// Validate if the synthesized answer addresses the user's question
    private func validateAnswer(_ answer: String, originalQuestion: String) async -> Bool {
        // Simple validation: check if answer mentions key terms from question
        // For section numbers like "1.4.4", check if answer contains that section
        // For specific topics, check if answer addresses that topic
        
        let questionLower = originalQuestion.lowercased()
        let answerLower = answer.lowercased()
        
        // Extract section numbers from question (e.g., "1.4.4")
        let sectionPattern = #"\d+\.\d+\.\d+"#
        if let sectionMatch = questionLower.range(of: sectionPattern, options: .regularExpression) {
            let sectionNumber = String(questionLower[sectionMatch])
            // Answer should mention this section number
            return answerLower.contains(sectionNumber)
        }
        
        // For other questions, check if key terms appear in answer
        // This is a simple heuristic - can be enhanced later
        let keyTerms = questionLower.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 && !["what", "is", "about", "the", "attached", "pdf", "document", "file"].contains($0) }
        
        // If we have key terms, check if at least some appear in the answer
        guard !keyTerms.isEmpty else {
            // No key terms to check, assume valid
            return true
        }
        
        // At least half of the key terms should appear in the answer
        let matchingTerms = keyTerms.filter { answerLower.contains($0) }
        return matchingTerms.count >= (keyTerms.count + 1) / 2
    }
    
    /// Create and execute a refinement subtask when answer doesn't address the question
    private func refineAnswer(
        originalQuestion: String,
        previousAnswer: String,
        context: AgentContext,
        agents: [any Agent]
    ) async throws -> String {
        // Create a specific refinement task
        let refinementTask = AgentTask(
            description: """
            The previous answer did not specifically address the user's question: "\(originalQuestion)"
            
            Previous answer: \(previousAnswer.prefix(500))
            
            Please provide a specific answer to the user's question. If the question asks about a specific section (e.g., "1.4.4"), find and explain that section. If it asks about a specific topic, focus on that topic.
            """,
            requiredCapabilities: [.fileReading, .generalReasoning]
        )
        
        // Find appropriate agent (prefer File Reader for file questions)
        let agent = agents.first { $0.capabilities.contains(.fileReading) } ?? agents.first { $0.capabilities.contains(.generalReasoning) }
        
        guard let selectedAgent = agent else {
            return previousAnswer // Fallback to previous answer
        }
        
        // Execute refinement
        let refinementResult = try await selectedAgent.process(task: refinementTask, context: context)
        return refinementResult.content
    }
    
    /// Synthesize results using coordinator
    private func synthesizeResults(_ results: [AgentResult], context: AgentContext, originalTask: AgentTask, agents: [any Agent]) async throws -> String {
        guard !results.isEmpty else {
            return "No results from agents."
        }
        
        if results.count == 1 {
            return results[0].content
        }
        
        // Format results for user-facing synthesis (no agent references)
        let summarizedResults = try await resultSummarizer.formatResultsForSynthesis(results, level: .medium)
        
        let searchEvidence = results.compactMap { $0.data["rawSearchResults"] }.joined(separator: "\n\n")
        let searchEvidenceBlock = searchEvidence.isEmpty ? "" : """
            Search Results (verbatim):
            \(searchEvidence)
            
            """
        
        // Create synthesis task with user-focused prompt
        let synthesisTask = AgentTask(
            description: """
            Please provide a clear and comprehensive answer to the following question.
            
            Question: \(originalTask.description)
            
            Information gathered:
            \(summarizedResults)
            
            \(searchEvidenceBlock)Instructions:
            - Answer the question directly and naturally
            - Present the information as if you gathered it yourself
            - Do not mention agents, results, synthesis, or the process of gathering information
            - Focus entirely on providing a helpful, well-organized answer to the user
            - If Search Results are provided, use ONLY those results for factual claims
            - If the Search Results do not contain the answer, say so and ask for clarification
            - When Search Results are provided, include a short sources list with URLs
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
        let synthesizedAnswer = synthesisResult.content
        
        // Validate if the answer addresses the original question
        let originalQuestion = originalTask.description
        let isValid = await validateAnswer(synthesizedAnswer, originalQuestion: originalQuestion)
        
        if !isValid {
            Log.warn("⚠️ OrchestratorPattern: Synthesized answer does not address the question, refining...")
            // Refine the answer
            let refinedAnswer = try await refineAnswer(
                originalQuestion: originalQuestion,
                previousAnswer: synthesizedAnswer,
                context: context,
                agents: agents
            )
            return refinedAnswer
        }
        
        return synthesizedAnswer
    }
    
    /// Fallback execution when parsing fails
    private func fallbackExecution(
        task: AgentTask,
        agents: [any Agent],
        context: AgentContext
    ) async throws -> AgentResult {
        Log.warn("⚠️ OrchestratorPattern: Using fallback capability-based matching")
        
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
        
        // Check if task description already contains RAG chunks (from analysis prompt)
        let taskDescriptionHasRAG = task.description.contains("Relevant Document Content") || task.description.contains("from attached files")
        
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
        
        // If task description already has RAG chunks, don't add conversation history or more RAG
        // This is the analysis prompt case - it's already complete
        if taskDescriptionHasRAG {
            // For analysis prompts, the task description IS the prompt (it already includes everything)
            // Just ensure it fits within token limits
            // Check if this is a synthesis prompt - use stricter limits
            let isSynthesis = task.description.contains("Synthesize") || task.description.contains("synthesis")
            let maxTokensForPrompt = isSynthesis ? 3000 : availableForContent // Stricter limit for synthesis
            
            if taskTokens > maxTokensForPrompt {
                let maxChars = maxTokensForPrompt * 4
                taskDescription = String(taskDescription.prefix(maxChars)) + "\n\n[Prompt truncated due to length]"
                Log.warn("⚠️ OrchestratorPattern: Truncated \(isSynthesis ? "synthesis" : "analysis") prompt from \(taskTokens) to ~\(maxTokensForPrompt) tokens")
            }
            
            // Final safety check - ensure it doesn't exceed 4096 tokens
            let finalTokens = await tokenCounter.countTokens(taskDescription)
            if finalTokens > 4096 {
                let maxChars = 3500 * 4 // Reserve aggressively
                taskDescription = String(taskDescription.prefix(maxChars)) + "\n\n[Prompt truncated due to context window limits]"
                Log.warn("⚠️ OrchestratorPattern: Final truncation - reduced to ~3500 tokens to fit 4096 limit")
            }
            
            return taskDescription
        }
        
        // For regular prompts (not analysis), add conversation history and RAG chunks
        let availableForTask = max(100, availableForContent - historyTokens)
        
        if taskTokens > availableForTask {
            // Truncate task description
            let maxChars = availableForTask * 4 // Rough char-to-token conversion
            let truncated = String(taskDescription.prefix(maxChars))
            taskDescription = truncated + "\n\n[Message truncated due to length. Full content available in conversation history.]"
            Log.warn("⚠️ OrchestratorPattern: Truncated task description from \(taskTokens) to ~\(availableForTask) tokens")
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
        
        // Include RAG chunks if available, with token-aware truncation
        if !context.ragChunks.isEmpty {
            // Calculate remaining tokens after task description and conversation history
            let currentPromptTokens = await tokenCounter.countTokens(prompt)
            let remainingTokens = max(0, availableForContent - currentPromptTokens)
            
            if remainingTokens > 200 { // Only add RAG chunks if we have meaningful space
                let ragHeader = "Relevant Document Content (from attached files):\n"
                let ragHeaderTokens = await tokenCounter.countTokens(ragHeader)
                let availableForRAG = max(0, remainingTokens - ragHeaderTokens - 50) // Reserve 50 for footer
                
                var ragContent = ""
                var ragTokensUsed = 0
                
                for (index, chunk) in context.ragChunks.prefix(3).enumerated() {
                    let chunkText = ragContent.isEmpty ? "\n[Chunk \(index + 1)]\n\(chunk.content)\n" : "\n[Chunk \(index + 1)]\n\(chunk.content)\n"
                    let chunkTokens = await tokenCounter.countTokens(chunkText)
                    
                    if ragTokensUsed + chunkTokens <= availableForRAG {
                        ragContent += chunkText
                        ragTokensUsed += chunkTokens
                    } else {
                        // Truncate this chunk to fit remaining budget
                        let remainingRAGTokens = max(0, availableForRAG - ragTokensUsed)
                        if remainingRAGTokens > 50 {
                            let maxChars = remainingRAGTokens * 4
                            let truncatedChunk = String(chunk.content.prefix(maxChars))
                            ragContent += "\n[Chunk \(index + 1)]\n\(truncatedChunk)\n[Truncated...]\n"
                        }
                        break
                    }
                }
                
                if !ragContent.isEmpty {
                    prompt += ragHeader + ragContent + "\n"
                    
                    // #region debug log
                    await DebugLogger.shared.log(
                        location: "OrchestratorPattern.swift:buildPrompt",
                        message: "Added RAG chunks to prompt",
                        hypothesisId: "B",
                        data: [
                            "chunksAdded": ragContent.components(separatedBy: "[Chunk").count - 1,
                            "ragTokensUsed": ragTokensUsed,
                            "availableForRAG": availableForRAG,
                            "chunkPreviews": context.ragChunks.prefix(3).map { String($0.content.prefix(200)) }
                        ]
                    )
                    // #endregion
                } else {
                    // #region debug log
                    await DebugLogger.shared.log(
                        location: "OrchestratorPattern.swift:buildPrompt",
                        message: "RAG chunks skipped due to token limits",
                        hypothesisId: "B",
                        data: [
                            "ragChunksCount": context.ragChunks.count,
                            "availableForRAG": availableForRAG,
                            "remainingTokens": remainingTokens
                        ]
                    )
                    // #endregion
                }
            } else {
                // #region debug log
                await DebugLogger.shared.log(
                    location: "OrchestratorPattern.swift:buildPrompt",
                    message: "RAG chunks skipped - insufficient token budget",
                    hypothesisId: "B",
                    data: [
                        "ragChunksCount": context.ragChunks.count,
                        "remainingTokens": remainingTokens,
                        "currentPromptTokens": currentPromptTokens
                    ]
                )
                // #endregion
            }
        } else {
            // #region debug log
            await DebugLogger.shared.log(
                location: "OrchestratorPattern.swift:buildPrompt",
                message: "No RAG chunks to add to prompt",
                hypothesisId: "B",
                data: [
                    "ragChunksCount": context.ragChunks.count,
                    "fileReferencesCount": context.fileReferences.count
                ]
            )
            // #endregion
        }
        
        // Final token check - truncate entire prompt if still too long
        let finalPromptTokens = await tokenCounter.countTokens(prompt)
        if finalPromptTokens > availableForContent {
            Log.warn("⚠️ OrchestratorPattern: Prompt still exceeds budget (\(finalPromptTokens) > \(availableForContent)), truncating...")
            let maxChars = availableForContent * 4
            prompt = String(prompt.prefix(maxChars)) + "\n\n[Prompt truncated due to length]"
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
        
        // Calculate file content tokens
        // If we have file content savings metadata, use original file content tokens.
        // Otherwise, estimate based on file references.
        //
        // IMPORTANT: Images are not "file content tokens" in the same way as text/PDFs.
        // Counting 100k tokens per image massively inflates the baseline and produces misleading savings.
        let fileContentTokens: Int
        if let originalFileTokensStr = context.metadata["tokens_file_content_original"],
           let originalFileTokens = Int(originalFileTokensStr) {
            fileContentTokens = originalFileTokens
        } else {
            let supportedImageExtensions: Set<String> = [
                "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"
            ]
            let (imageCount, nonImageCount) = context.fileReferences.reduce(into: (0, 0)) { acc, path in
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                if supportedImageExtensions.contains(ext) {
                    acc.0 += 1
                } else {
                    acc.1 += 1
                }
            }
            
            // Non-image files (especially PDFs) can be very large in tokens.
            // Images are represented via features/signals, not full tokenized file content.
            fileContentTokens = (nonImageCount * 100_000) + (imageCount * 5_000)
        }
        
        let fileRefTokens = context.fileReferences.joined(separator: ", ").count / 4 // Just file paths
        let baseInputTokens = taskTokens + contextTokens + fileRefTokens + fileContentTokens
        
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
        
        Log.debug("📊 OrchestratorPattern: Single-agent estimate - Input: \(baseInputTokens), Response: \(estimatedResponseTokens), Tools: \(toolCallTokens), Overhead: \(complexityOverhead), Total: \(totalEstimate)")
        
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
    private func shouldDelegateWithReason(task: AgentTask, context: AgentContext, agents: [any Agent]) async throws -> (Bool, String?) {
        let result = try await shouldDelegateInternal(task: task, context: context, agents: agents)
        return (result.shouldDelegate, result.reason)
    }
    
    /// Determine if the task should be delegated to specialized agents or handled directly
    /// - Parameters:
    ///   - task: The task to evaluate
    ///   - context: The current context
    /// - Returns: true if task should be delegated, false if coordinator should respond directly
    private func shouldDelegate(task: AgentTask, context: AgentContext, agents: [any Agent]) async throws -> Bool {
        let result = try await shouldDelegateInternal(task: task, context: context, agents: agents)
        return result.shouldDelegate
    }
    
    /// Internal method that returns both decision and reason
    private func shouldDelegateInternal(task: AgentTask, context: AgentContext, agents: [any Agent]) async throws -> (shouldDelegate: Bool, reason: String?) {
        Log.debug("🤔 OrchestratorPattern: Evaluating delegation decision for task '\(task.description.prefix(50))...'")

        let availableCapabilities = Set(agents.flatMap { $0.capabilities })
        let hasWebSearch = availableCapabilities.contains(.webSearch)
        let hasFileReader = availableCapabilities.contains(.fileReading)
        let hasCodeAnalysis = availableCapabilities.contains(.codeAnalysis)
        let hasDataAnalysis = availableCapabilities.contains(.dataAnalysis)

        let hasCurrentFiles = (context.metadata["currentFileReferences"]?.isEmpty == false)
        let hasFiles = hasCurrentFiles || !context.fileReferences.isEmpty
        if let forcedDecision = DelegationDecider().forcedDecision(
            taskDescription: task.description,
            hasFiles: hasFiles,
            availableCapabilities: availableCapabilities
        ) {
            return (forcedDecision.shouldDelegate, forcedDecision.reason)
        }

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
            if hasFileReader {
                decisionPrompt += "\n- Files require specialized file reading capabilities"
            }
        }
        
        var delegateRule = "DELEGATE if: complex multi-step task, requires specialized capabilities"
        var specializedTools: [String] = []
        if hasFileReader { specializedTools.append("file") }
        if hasWebSearch { specializedTools.append("web") }
        if hasCodeAnalysis { specializedTools.append("code") }
        if hasDataAnalysis { specializedTools.append("data") }
        
        if !specializedTools.isEmpty {
            delegateRule = "DELEGATE if: needs \(specializedTools.joined(separator: "/")) tools, \(delegateRule.replacingOccurrences(of: "DELEGATE if: ", with: ""))"
        }
        
        if !context.fileReferences.isEmpty {
            delegateRule += ", files are attached"
        }

        decisionPrompt += "\n\nRules:\n"
        decisionPrompt += "- DIRECT if: greeting, simple question, basic conversation, simple follow-up\n"
        decisionPrompt += "- " + delegateRule + "\n\n"
        decisionPrompt += "Respond with ONLY: \"DIRECT\" or \"DELEGATE\"\n"
        decisionPrompt += "If DIRECT, provide your response. If DELEGATE, explain why."
        
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
        
        Log.debug("🤔 OrchestratorPattern: Decision result - \(shouldDelegate ? "DELEGATE" : "DIRECT")")
        if shouldDelegate {
            Log.debug("   Reason: \(decisionResult.content)")
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
        Log.debug("💬 OrchestratorPattern: Coordinator responding directly to task")
        
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
        
        // Estimate single-agent tokens (assumes full conversation history and full file content)
        let singleAgentEstimate = await estimateSingleAgentTokens(task: task, context: context)
        
        // Add file content savings to the tracker if available
        if let fileSavingsStr = context.metadata["tokens_file_content_saved"],
           let fileSavings = Int(fileSavingsStr),
           fileSavings > 0 {
            // Track file content savings at coordinator level
            await tokenTracker.trackSVDBSavings(
                agentId: coordinator.id,
                originalTokens: singleAgentEstimate,
                optimizedTokens: singleAgentEstimate - fileSavings
            )
        }
        
        // Calculate savings (now includes SVDB savings and file content savings)
        let savingsPercentage = await tokenTracker.calculateSavings(singleAgentEstimate: singleAgentEstimate)
        
        // Get total SVDB savings for logging (includes file content savings)
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
            Log.debug("📊 OrchestratorPattern: Direct response - Total: \(totalTokens), SVDB Savings: \(totalSVDBSavings), Net Total: \(totalTokens - totalSVDBSavings), Overall Savings: \(String(format: "%.1f", savingsPercentage))%")
        } else {
            Log.debug("📊 OrchestratorPattern: Direct response - Total: \(totalTokens), Savings: \(String(format: "%.1f", savingsPercentage))%")
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
    
    /// Create and save a checkpoint
    /// - Parameters:
    ///   - phase: Current orchestration phase
    ///   - orchestrationState: Current orchestration state
    ///   - task: Current task
    ///   - context: Current context
    ///   - agents: Available agents
    ///   - callback: Callback to save the checkpoint
    private func createCheckpoint(
        phase: OrchestrationPhase,
        orchestrationState: OrchestrationState,
        task: AgentTask,
        context: AgentContext,
        agents: [any Agent],
        callback: @Sendable (WorkflowCheckpoint) async throws -> Void
    ) async {
        // Get conversationId and messageId from context metadata
        guard let conversationIdStr = context.metadata["conversationId"],
              let conversationId = UUID(uuidString: conversationIdStr),
              let messageIdStr = context.metadata["messageId"],
              let messageId = UUID(uuidString: messageIdStr) else {
            Log.warn("⚠️ OrchestratorPattern: Cannot create checkpoint - missing conversationId or messageId in context")
            return
        }
        
        do {
            let checkpoint = try WorkflowCheckpoint.create(
                conversationId: conversationId,
                messageId: messageId,
                phase: phase,
                orchestrationState: orchestrationState,
                task: task,
                context: context,
                availableAgents: agents,
                description: "Checkpoint at \(phase.rawValue) phase"
            )
            
            try await callback(checkpoint)
            Log.debug("✅ OrchestratorPattern: Checkpoint created at \(phase.rawValue) phase")
        } catch {
            Log.warn("⚠️ OrchestratorPattern: Failed to create or save checkpoint: \(error)")
        }
    }
    
    /// Evaluate conditional branches and return new subtasks to execute
    /// - Parameters:
    ///   - decomposition: Current task decomposition
    ///   - results: Current subtask results
    ///   - agents: Available agents
    /// - Returns: New subtasks to add based on branch evaluation
    private func evaluateConditionalBranches(
        decomposition: TaskDecomposition,
        results: [UUID: AgentResult],
        agents: [any Agent]
    ) async throws -> [DecomposedSubtask] {
        var newSubtasks: [DecomposedSubtask] = []
        
        for branch in decomposition.conditionalBranches {
            // Check if this branch's dependency has completed
            if let dependsOnId = branch.dependsOnSubtaskId,
               results[dependsOnId] != nil {
                // Evaluate the branch
                let evaluation = try await branchEvaluator.evaluate(
                    branch: branch,
                    results: results,
                    coordinator: coordinator
                )
                
                Log.debug("🔀 OrchestratorPattern: Branch evaluation - Condition met: \(evaluation.conditionMet), Confidence: \(evaluation.confidence)")
                
                if !evaluation.subtasksToExecute.isEmpty {
                    newSubtasks.append(contentsOf: evaluation.subtasksToExecute)
                }
            }
        }
        
        return newSubtasks
    }
    
    private func firstImagePath(in fileReferences: [String]) -> String? {
        let supportedExtensions: Set<String> = [
            "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"
        ]
        
        for path in fileReferences {
            let url = URL(fileURLWithPath: path)
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                return path
            }
        }
        
        return nil
    }

    private func currentAttachmentPaths(from context: AgentContext) -> [String] {
        guard let raw = context.metadata["currentFileReferences"], !raw.isEmpty else {
            return []
        }
        return raw.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }
    
}
