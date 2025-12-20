//
//  WebSearchAgent.swift
//  FoundationChatCore
//
//  Agent specialized in web search using SerpAPI
//

import Foundation

/// Helper function to append log entry to debug.log file
private func appendToDebugLog(_ jsonString: String) {
    let logPath = "/Users/owenperry/dev/llm/.cursor/debug.log"
    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
        fileHandle.seekToEndOfFile()
        if let data = (jsonString + "\n").data(using: .utf8) {
            fileHandle.write(data)
        }
        fileHandle.closeFile()
    } else {
        // File doesn't exist, create it
        try? (jsonString + "\n").write(toFile: logPath, atomically: false, encoding: .utf8)
    }
}

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
            name: "Web Search",
            description: "Performs web searches using SerpAPI (Google search) to find current information, facts, and real-time data.",
            capabilities: [.webSearch],
            tools: [SerpAPIFoundationTool()]
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // #region debug log
        let logDataEntry: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "E",
            "location": "WebSearchAgent.swift:process",
            "message": "WebSearchAgent.process() called",
            "data": [
                "agentId": id.uuidString,
                "agentName": name,
                "taskDescription": task.description,
                "taskParameters": task.parameters
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logDataEntry),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
        // Extract search query from task
        let searchQuery = task.parameters["query"] ?? task.description
        
        // Build prompt for model with search capability
        let prompt = """
        The user wants to search for: \(searchQuery)
        
        Use the serpapi_search tool to find current information about this topic.
        After getting search results, synthesize them into a comprehensive answer.
        """
        
        // #region debug log
        let logDataBeforeModel: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
            "location": "WebSearchAgent.swift:process",
            "message": "About to get modelService and call respond()",
            "data": [
                "searchQuery": searchQuery,
                "prompt": prompt,
                "expectedTool": "serpapi_search"
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logDataBeforeModel),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
        // Get response from model (which will use the SerpAPI tool)
        let service = await modelService
        
        // #region debug log
        let logDataAfterModel: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
            "location": "WebSearchAgent.swift:process",
            "message": "ModelService obtained, calling respond()",
            "data": [
                "modelServiceObtained": true
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logDataAfterModel),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
        let response = try await service.respond(to: prompt)
        
        // #region debug log
        let logDataAfterResponse: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
            "location": "WebSearchAgent.swift:process",
            "message": "ModelService.respond() completed",
            "data": [
                "responseContentLength": response.content.count,
                "responseContentPreview": String(response.content.prefix(200)),
                "toolCallsCount": response.toolCalls.count,
                "toolCalls": response.toolCalls.map { ["toolName": $0.toolName, "arguments": $0.arguments] }
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logDataAfterResponse),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            appendToDebugLog(jsonString)
        }
        // #endregion
        
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


