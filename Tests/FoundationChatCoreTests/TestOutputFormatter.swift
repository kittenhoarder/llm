//
//  TestOutputFormatter.swift
//  FoundationChatCoreTests
//
//  Formatter for creating structured test reports
//

import Foundation
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
struct TestScenarioReport: Codable {
    let scenarioName: String
    let timestamp: Date
    let agents: [String]
    let toolsUsed: [ToolUsage]
    let conversationFlow: [MessageSummary]
    let contextSharing: ContextSharingMetrics
    let qualityMetrics: QualityMetrics
    let verificationResults: [String: VerificationResultSummary]
    
    struct ToolUsage: Codable {
        let toolName: String
        let callCount: Int
        let sessions: [String]
    }
    
    struct MessageSummary: Codable {
        let role: String
        let contentPreview: String
        let contentLength: Int
        let timestamp: Date?
    }
    
    struct ContextSharingMetrics: Codable {
        let totalMessages: Int
        let contextReferences: Int
        let sharedToolResults: Int
        let contextContinuity: Bool
    }
    
    struct QualityMetrics: Codable {
        let averageResponseLength: Int
        let minResponseLength: Int
        let maxResponseLength: Int
        let totalToolCalls: Int
        let uniqueToolsUsed: Int
    }
    
    struct VerificationResultSummary: Codable {
        let passed: Bool
        let message: String
        let details: [String: String]
    }
}

@available(macOS 26.0, iOS 26.0, *)
enum TestOutputFormatter {
    
    /// Create a test scenario report from test execution data
    /// - Parameters:
    ///   - scenarioName: Name of the test scenario
    ///   - agents: Array of agent names involved
    ///   - results: Array of agent results
    ///   - conversation: The conversation
    ///   - verificationResults: Dictionary of verification results
    /// - Returns: Test scenario report
    static func createReport(
        scenarioName: String,
        agents: [String],
        results: [AgentResult],
        conversation: Conversation,
        verificationResults: [String: VerificationResult]
    ) -> TestScenarioReport {
        // Extract tool usage
        let allToolCalls = results.flatMap { $0.toolCalls }
        let toolUsageDict = Dictionary(grouping: allToolCalls) { $0.toolName }
        let toolsUsed = toolUsageDict.map { key, calls in
            TestScenarioReport.ToolUsage(
                toolName: key,
                callCount: calls.count,
                sessions: [] // Could track sessions if available
            )
        }
        
        // Create message summaries (handle empty arrays gracefully)
        let conversationFlow = conversation.messages.isEmpty ? [] : conversation.messages.map { message in
            TestScenarioReport.MessageSummary(
                role: message.role.rawValue,
                contentPreview: String(message.content.prefix(200)),
                contentLength: message.content.count,
                timestamp: message.timestamp
            )
        }
        
        // Calculate context sharing metrics (handle empty arrays gracefully)
        var contextReferences = 0
        if conversation.messages.count > 1 {
            for i in 1..<conversation.messages.count {
                let current = conversation.messages[i].content.lowercased()
                let previous = conversation.messages[i-1].content.lowercased()
                // Simple check: if current message contains words from previous
                let previousWords = Set(previous.components(separatedBy: .whitespaces).filter { $0.count > 4 })
                let currentWords = Set(current.components(separatedBy: .whitespaces))
                contextReferences += previousWords.intersection(currentWords).count
            }
        }
        
        let contextSharing = TestScenarioReport.ContextSharingMetrics(
            totalMessages: conversation.messages.count,
            contextReferences: contextReferences,
            sharedToolResults: results.flatMap { $0.toolCalls }.count,
            contextContinuity: contextReferences > 0
        )
        
        // Calculate quality metrics
        let responseLengths = results.map { $0.content.count }
        let qualityMetrics = TestScenarioReport.QualityMetrics(
            averageResponseLength: responseLengths.isEmpty ? 0 : responseLengths.reduce(0, +) / responseLengths.count,
            minResponseLength: responseLengths.min() ?? 0,
            maxResponseLength: responseLengths.max() ?? 0,
            totalToolCalls: allToolCalls.count,
            uniqueToolsUsed: Set(allToolCalls.map { $0.toolName }).count
        )
        
        // Convert verification results
        let verificationSummaries = verificationResults.mapValues { result in
            TestScenarioReport.VerificationResultSummary(
                passed: result.passed,
                message: result.message,
                details: result.details.mapValues { String(describing: $0) }
            )
        }
        
        return TestScenarioReport(
            scenarioName: scenarioName,
            timestamp: Date(),
            agents: agents,
            toolsUsed: toolsUsed,
            conversationFlow: conversationFlow,
            contextSharing: contextSharing,
            qualityMetrics: qualityMetrics,
            verificationResults: verificationSummaries
        )
    }
    
    /// Format report as markdown
    /// - Parameter report: The test scenario report
    /// - Returns: Markdown formatted string
    static func formatAsMarkdown(_ report: TestScenarioReport) -> String {
        var markdown = """
        # Test Scenario Report: \(report.scenarioName)
        
        **Timestamp:** \(formatDate(report.timestamp))
        
        ## Agents Involved
        \(report.agents.map { "- \($0)" }.joined(separator: "\n"))
        
        ## Tools Used
        \(report.toolsUsed.isEmpty ? "*No tools used*" : report.toolsUsed.map { "- **\($0.toolName)**: \($0.callCount) call(s)" }.joined(separator: "\n"))
        
        ## Conversation Flow
        """
        
        for (index, message) in report.conversationFlow.enumerated() {
            markdown += """
            
            ### Message \(index + 1) - \(message.role.capitalized)
            **Length:** \(message.contentLength) characters
            
            \(message.contentPreview)\(message.contentLength > 200 ? "..." : "")
            """
        }
        
        markdown += """
        
        ## Context Sharing Metrics
        - **Total Messages:** \(report.contextSharing.totalMessages)
        - **Context References:** \(report.contextSharing.contextReferences)
        - **Shared Tool Results:** \(report.contextSharing.sharedToolResults)
        - **Context Continuity:** \(report.contextSharing.contextContinuity ? "✓ Yes" : "✗ No")
        
        ## Quality Metrics
        - **Average Response Length:** \(report.qualityMetrics.averageResponseLength) characters
        - **Min Response Length:** \(report.qualityMetrics.minResponseLength) characters
        - **Max Response Length:** \(report.qualityMetrics.maxResponseLength) characters
        - **Total Tool Calls:** \(report.qualityMetrics.totalToolCalls)
        - **Unique Tools Used:** \(report.qualityMetrics.uniqueToolsUsed)
        
        ## Verification Results
        """
        
        for (key, result) in report.verificationResults {
            let status = result.passed ? "✓ PASS" : "✗ FAIL"
            markdown += """
            
            ### \(key)
            **Status:** \(status)
            **Message:** \(result.message)
            """
            if !result.details.isEmpty {
                markdown += "\n**Details:**\n"
                for (detailKey, detailValue) in result.details {
                    markdown += "- \(detailKey): \(detailValue)\n"
                }
            }
        }
        
        return markdown
    }
    
    /// Format report as JSON
    /// - Parameter report: The test scenario report
    /// - Returns: JSON formatted string
    static func formatAsJSON(_ report: TestScenarioReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    /// Save report to file
    /// - Parameters:
    ///   - report: The test scenario report
    ///   - directory: Directory to save to
    ///   - formats: Formats to save (markdown, json, or both)
    /// - Returns: Array of file paths created
    static func saveReport(
        _ report: TestScenarioReport,
        to directory: String,
        formats: Set<String> = ["markdown", "json"]
    ) throws -> [String] {
        let fileManager = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)
        
        // Create directory if it doesn't exist
        try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        
        let timestamp = Int(report.timestamp.timeIntervalSince1970)
        let sanitizedName = report.scenarioName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
        
        var createdFiles: [String] = []
        
        if formats.contains("markdown") {
            let markdown = formatAsMarkdown(report)
            let markdownPath = dirURL.appendingPathComponent("\(sanitizedName)_\(timestamp).md")
            try markdown.write(to: markdownPath, atomically: true, encoding: .utf8)
            createdFiles.append(markdownPath.path)
        }
        
        if formats.contains("json") {
            let json = try formatAsJSON(report)
            let jsonPath = dirURL.appendingPathComponent("\(sanitizedName)_\(timestamp).json")
            try json.write(to: jsonPath, atomically: true, encoding: .utf8)
            createdFiles.append(jsonPath.path)
        }
        
        return createdFiles
    }
    
    /// Format date for display
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

