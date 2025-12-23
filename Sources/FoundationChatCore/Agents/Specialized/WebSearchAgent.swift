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
            id: AgentId.webSearch,
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
        
        let tool = SerpAPIFoundationTool()
        let searchResults = try await tool.call(arguments: .init(query: searchQuery))
        
        let errorPrefixes = [
            "SerpAPI key not configured",
            "SerpAPI authentication failed",
            "SerpAPI rate limit exceeded",
            "Network error while searching",
            "SerpAPI returned an error",
            "SerpAPI returned an invalid response"
        ]
        
        if errorPrefixes.contains(where: { searchResults.hasPrefix($0) }) {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: searchResults,
                success: false,
                error: "Search failed"
            )
        }
        
        let summaryPrompt = """
        You are a web search assistant. Use the search results to answer the user's question.
        
        Question: \(task.description)
        
        Search Results:
        \(searchResults)
        
        Provide a concise, direct answer. If possible, include a short sources list with URLs.
        """
        
        let service = await modelService
        let response = try await service.respond(to: summaryPrompt)
        
        // Update context with search results
        var updatedContext = context
        updatedContext.toolResults["search:\(searchQuery)"] = searchResults
        
        var data = [String: String]()
        data["rawSearchResults"] = searchResults
        data["searchQuery"] = searchQuery
        
        let toolCalls = response.toolCalls.isEmpty
            ? [ToolCall(toolName: "serpapi_search", arguments: searchQuery)]
            : response.toolCalls
        
        return AgentResult(
            agentId: id,
            taskId: task.id,
            content: response.content,
            success: true,
            data: data,
            toolCalls: toolCalls,
            updatedContext: updatedContext
        )
    }
}
