//
//  CodeAnalysisAgent.swift
//  FoundationChatCore
//
//  Agent specialized in analyzing code files using LEANN vector search
//

import Foundation

/// Agent that analyzes code files using LEANN-indexed codebase
///
/// **Status**: ✅ Functional with LEANN integration
/// - Searches indexed codebase using LEANN semantic search
/// - Provides code analysis based on relevant files
/// - Requires user to index a codebase in Settings first
@available(macOS 26.0, iOS 26.0, *)
public class CodeAnalysisAgent: BaseAgent, @unchecked Sendable {
    public init() {
        super.init(
            id: AgentId.codeAnalysis,
            name: AgentName.codeAnalysis,
            description: "Analyses code files using semantic search, grep, and file exploration over an indexed codebase.",
            capabilities: [.codeAnalysis],
            tools: [
                CodebaseSearchTool(),
                CodebaseGrepTool(),
                CodebaseReadFileTool(),
                CodebaseListFilesTool()
            ]
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Build the core system prompt for code analysis
        // Build the core system prompt for code analysis
        var systemPrompt = PromptTemplates.codeAnalysisSystemPrompt
        systemPrompt += "\n\nCurrent Task: \(task.description)"
        
        // Get response from model
        let service = await modelService
        let response = try await service.respond(to: systemPrompt)
        
        // Update context
        var updatedContext = context
        updatedContext.toolResults["codeAnalysis"] = response.content
        
        return AgentResult(
            agentId: id,
            taskId: task.id,
            content: response.content,
            success: true,
            toolCalls: response.toolCalls,
            updatedContext: updatedContext
        )
    }
}
