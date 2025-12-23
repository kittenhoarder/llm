//
//  DataAnalysisAgent.swift
//  FoundationChatCore
//
//  Agent specialized in data analysis and processing
//

import Foundation

@available(macOS 26.0, iOS 26.0, *)
public class DataAnalysisAgent: BaseAgent, @unchecked Sendable {
    public init() {
        super.init(
            id: AgentId.dataAnalysis,
            name: AgentName.dataAnalysis,
            description: "Performs data analysis, calculations, and statistical operations on data structures like CSV, JSON, and numerical data found in the codebase.",
            capabilities: [.dataAnalysis],
            tools: [
                CodebaseSearchTool(),
                CodebaseGrepTool(),
                CodebaseReadFileTool(),
                CodebaseListFilesTool()
            ]
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Build analysis prompt
        let systemPrompt = """
        You are an expert Data Analysis Agent. Your goal is to help the user analyze data and understand patterns.
        
        You have access to any provided data files, and also to the indexed codebase via the following tools:
        1. `codebase_semantic_search`: Use this for finding relevant data structures, constants, or data handling logic in the code.
        2. `codebase_grep_search`: Use this to find specific data-related strings or patterns in the codebase.
        3. `codebase_read_file`: Use this to see the full content of relevant code or data files.
        4. `codebase_list_files`: Use this to explore directories for relevant data files.
        
        Guidelines:
        - ALWAYS prioritize using codebase tools to gather context about how data is structured or processed in this project.
        - Focus on data analysis, visualization suggestions, and pattern identification.
        - Provide high-quality insights based on the actual project implementation and data.
        - If you need to understand the data schema, search the codebase for relevant model or struct definitions.
        
        Current Task: \(task.description)
        """
        
        // Get response from model
        let service = await modelService
        let response = try await service.respond(to: systemPrompt)
        
        // Update context
        var updatedContext = context
        updatedContext.toolResults["dataAnalysis"] = response.content
        
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

