//
//  CodeAnalysisAgent.swift
//  FoundationChatCore
//
//  Agent specialized in analyzing code files
//

import Foundation

/// Agent that analyzes code files and provides insights
///
/// **Status**: ⚠️ Partially Functional
/// - Requires code content to be provided in task parameters
/// - Does not automatically read code files (needs code passed directly)
/// - Provides syntax analysis, structure insights, and pattern identification
/// - Limited functionality - needs code content in parameters
///
/// **Tool Wiring**: ⚠️ No tools wired - relies on code in task parameters
/// - TODO: Integrate with FileReaderAgent or add file reading capability
/// - TODO: Add code analysis tools (AST parsing, syntax highlighting, etc.)
@available(macOS 26.0, iOS 26.0, *)
public class CodeAnalysisAgent: BaseAgent, @unchecked Sendable {
    public init() {
        super.init(
            name: AgentName.codeAnalysis,
            description: "Analyzes code files to provide syntax analysis, structure insights, and identify patterns or potential issues.",
            capabilities: [.codeAnalysis],
            tools: []
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Get code content from context or task parameters
        let codeContent: String
        
        if let code = task.parameters["code"] {
            codeContent = code
        } else if context.fileReferences.contains(where: { $0.hasSuffix(".swift") || $0.hasSuffix(".js") || $0.hasSuffix(".ts") || $0.hasSuffix(".py") }) {
            // Try to read code from file
            // For now, we'll ask the user to provide the code
            codeContent = ""
        } else {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "No code content provided. Please provide code in the task parameters or reference a code file.",
                success: false,
                error: "Missing code content"
            )
        }
        
        guard !codeContent.isEmpty else {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "Code content is empty. Please provide code to analyze.",
                success: false,
                error: "Empty code content"
            )
        }
        
        // Build analysis prompt
        let analysisPrompt = """
        Analyze the following code:
        
        \(codeContent)
        
        User request: \(task.description)
        
        Provide:
        1. Code structure and organization
        2. Syntax analysis
        3. Potential issues or improvements
        4. Patterns identified
        5. Any other relevant insights
        """
        
        // Get response from model
        let service = await modelService
        let response = try await service.respond(to: analysisPrompt)
        
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


