//
//  WebSearchAgent.swift
//  FoundationChatCore
//
//  Agent specialized in web search using SerpAPI
//

import Foundation

/// Agent that performs web searches using SerpAPI
///
/// **Status**: ✅ Fully Functional
/// - Has SerpAPI tool properly wired up
/// - Ready for production use
/// - Requires SerpAPI API key to be configured in settings
@available(macOS 26.0, iOS 26.0, *)
public class WebSearchAgent: BaseAgent, @unchecked Sendable {
    public init() {
        super.init(
            name: AgentName.webSearch,
            description: "Performs web searches using SerpAPI (Google search) to find current information, facts, and real-time data.",
            capabilities: [.webSearch],
            tools: [SerpAPIFoundationTool()]
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Debug logging
        await DebugLogger.shared.log(
            location: "WebSearchAgent.swift:process",
            message: "WebSearchAgent.process() called",
            hypothesisId: "E",
            data: [
                "agentId": id.uuidString,
                "agentName": name,
                "taskDescription": task.description,
                "taskParameters": task.parameters
            ]
        )
        
        // Extract search query from task
        let searchQuery = task.parameters["query"] ?? task.description
        
        // Build prompt for model with search capability
        let prompt = """
        The user wants to search for: \(searchQuery)
        
        Use the serpapi_search tool to find current information about this topic.
        After getting search results, synthesize them into a comprehensive answer.
        """
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "WebSearchAgent.swift:process",
            message: "About to get modelService and call respond()",
            hypothesisId: "B",
            data: [
                "searchQuery": searchQuery,
                "prompt": prompt,
                "expectedTool": "serpapi_search"
            ]
        )
        
        // Get response from model (which will use the SerpAPI tool)
        let service = await modelService
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "WebSearchAgent.swift:process",
            message: "ModelService obtained, calling respond()",
            hypothesisId: "B",
            data: [
                "modelServiceObtained": true
            ]
        )
        
        let response = try await service.respond(to: prompt)
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "WebSearchAgent.swift:process",
            message: "ModelService.respond() completed",
            hypothesisId: "B",
            data: [
                "responseContentLength": response.content.count,
                "responseContentPreview": String(response.content.prefix(AppConstants.toolResultTruncationLength)),
                "toolCallsCount": response.toolCalls.count,
                "toolCalls": response.toolCalls.map { ["toolName": $0.toolName, "arguments": $0.arguments] }
            ]
        )
        
        // Update context with search results
        var updatedContext = context
        updatedContext.toolResults["search:\(searchQuery)"] = response.content
        
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


