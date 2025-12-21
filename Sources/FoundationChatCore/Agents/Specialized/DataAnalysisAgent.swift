//
//  DataAnalysisAgent.swift
//  FoundationChatCore
//
//  Agent specialized in data analysis and processing
//

import Foundation

/// Agent that performs data analysis and calculations
///
/// **Status**: ⚠️ Partially Functional
/// - Requires data to be provided in task parameters or file references
/// - Can analyze CSV and JSON files if file paths are provided in context
/// - Performs statistical calculations, data summarization, and pattern identification
/// - Limited functionality - needs data in parameters or file references
///
/// **Tool Wiring**: ⚠️ No tools wired - relies on data in task parameters or file references
/// - TODO: Integrate with FileReaderAgent for automatic file reading
/// - TODO: Add data processing tools (CSV parser, JSON parser, calculator, etc.)
@available(macOS 26.0, iOS 26.0, *)
public class DataAnalysisAgent: BaseAgent, @unchecked Sendable {
    public init() {
        super.init(
            name: AgentName.dataAnalysis,
            description: "Performs data analysis, calculations, and statistical operations on data structures like CSV, JSON, and numerical data.",
            capabilities: [.dataAnalysis],
            tools: []
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Get data from context or task parameters
        let dataContent: String
        
        if let data = task.parameters["data"] {
            dataContent = data
        } else if let csvPath = context.fileReferences.first(where: { $0.hasSuffix(".csv") }) {
            // CSV file referenced
            dataContent = "CSV file: \(csvPath)"
        } else if let jsonPath = context.fileReferences.first(where: { $0.hasSuffix(".json") }) {
            // JSON file referenced
            dataContent = "JSON file: \(jsonPath)"
        } else {
            // Try to extract data from task description
            dataContent = task.description
        }
        
        // Build analysis prompt
        let analysisPrompt = """
        Analyze the following data:
        
        \(dataContent)
        
        User request: \(task.description)
        
        Perform the requested analysis, which may include:
        - Statistical calculations
        - Data summarization
        - Pattern identification
        - Trend analysis
        - Data validation
        - Any other data processing operations
        
        Provide clear, structured results.
        """
        
        // Get response from model
        let service = await modelService
        let response = try await service.respond(to: analysisPrompt)
        
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


