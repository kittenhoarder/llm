//
//  OutputVerificationHelpers.swift
//  FoundationChatCoreTests
//
//  Helper functions for automated verification of agent outputs
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
struct VerificationResult {
    let passed: Bool
    let message: String
    let details: [String: Any]
}

@available(macOS 26.0, iOS 26.0, *)
enum OutputVerificationHelpers {
    
    /// Verify that expected tools were called in the result
    /// - Parameters:
    ///   - result: The agent result to verify
    ///   - expectedTools: Array of tool names that should have been called
    ///   - allowPartial: If true, passes if at least one expected tool was called
    /// - Returns: Verification result
    static func verifyToolUsage(
        result: AgentResult,
        expectedTools: [String],
        allowPartial: Bool = false
    ) -> VerificationResult {
        let toolNames = result.toolCalls.map { $0.toolName }
        let foundTools = expectedTools.filter { toolNames.contains($0) }
        
        let passed: Bool
        let message: String
        
        if allowPartial {
            passed = !foundTools.isEmpty
            message = passed 
                ? "At least one expected tool was used: \(foundTools.joined(separator: ", "))"
                : "None of the expected tools were used. Expected: \(expectedTools.joined(separator: ", ")), Found: \(toolNames.joined(separator: ", "))"
        } else {
            passed = foundTools.count == expectedTools.count
            message = passed
                ? "All expected tools were used: \(foundTools.joined(separator: ", "))"
                : "Not all expected tools were used. Expected: \(expectedTools.joined(separator: ", ")), Found: \(toolNames.joined(separator: ", "))"
        }
        
        return VerificationResult(
            passed: passed,
            message: message,
            details: [
                "expectedTools": expectedTools,
                "foundTools": foundTools,
                "allToolCalls": toolNames,
                "toolCallCount": toolNames.count
            ]
        )
    }
    
    /// Verify that context was shared between messages in a conversation
    /// - Parameters:
    ///   - conversation: The conversation to check
    ///   - messageIndex: Index of the message to check (should reference earlier messages)
    ///   - minContextReferences: Minimum number of references to earlier context
    /// - Returns: Verification result
    static func verifyContextSharing(
        conversation: Conversation,
        messageIndex: Int,
        minContextReferences: Int = 1
    ) -> VerificationResult {
        // Early return for empty message arrays
        guard !conversation.messages.isEmpty else {
            return VerificationResult(
                passed: false,
                message: "Conversation has no messages",
                details: [
                    "messageIndex": messageIndex,
                    "messageCount": 0
                ]
            )
        }
        
        guard messageIndex < conversation.messages.count && messageIndex > 0 && conversation.messages.count > 1 else {
            return VerificationResult(
                passed: false,
                message: "Invalid message index or insufficient messages",
                details: [
                    "messageIndex": messageIndex,
                    "messageCount": conversation.messages.count
                ]
            )
        }
        
        let currentMessage = conversation.messages[messageIndex]
        let previousMessages = Array(conversation.messages.prefix(messageIndex))
        
        // Extract keywords from previous messages
        let previousKeywords = previousMessages.flatMap { message in
            message.content.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 4 } // Only meaningful words
        }
        
        // Check if current message references previous content
        let currentContent = currentMessage.content.lowercased()
        let references = previousKeywords.filter { keyword in
            currentContent.contains(keyword)
        }
        
        let passed = references.count >= minContextReferences
        let message = passed
            ? "Context sharing verified: \(references.count) references to previous messages found"
            : "Insufficient context sharing: only \(references.count) references found (minimum: \(minContextReferences))"
        
        return VerificationResult(
            passed: passed,
            message: message,
            details: [
                "messageIndex": messageIndex,
                "previousMessageCount": previousMessages.count,
                "referencesFound": references.count,
                "sampleReferences": Array(references.prefix(5))
            ]
        )
    }
    
    /// Verify response quality
    /// - Parameters:
    ///   - result: The agent result to verify
    ///   - minLength: Minimum expected response length
    ///   - requiredKeywords: Optional keywords that should appear in the response
    ///   - maxLength: Optional maximum expected response length
    /// - Returns: Verification result
    static func verifyResponseQuality(
        result: AgentResult,
        minLength: Int = 10,
        requiredKeywords: [String]? = nil,
        maxLength: Int? = nil
    ) -> VerificationResult {
        let content = result.content
        let length = content.count
        
        var issues: [String] = []
        var details: [String: Any] = [
            "responseLength": length,
            "minLength": minLength
        ]
        
        // Check minimum length
        if length < minLength {
            issues.append("Response too short: \(length) characters (minimum: \(minLength))")
        }
        
        // Check maximum length if specified
        if let maxLength = maxLength, length > maxLength {
            issues.append("Response too long: \(length) characters (maximum: \(maxLength))")
        }
        
        // Check required keywords
        if let keywords = requiredKeywords {
            let contentLower = content.lowercased()
            let foundKeywords = keywords.filter { contentLower.contains($0.lowercased()) }
            details["requiredKeywords"] = keywords
            details["foundKeywords"] = foundKeywords
            
            if foundKeywords.count < keywords.count {
                issues.append("Missing keywords: \(keywords.filter { !foundKeywords.contains($0) }.joined(separator: ", "))")
            }
        }
        
        // Check if response is empty or just whitespace
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Response is empty or only whitespace")
        }
        
        let passed = issues.isEmpty
        let message = passed
            ? "Response quality verified: \(length) characters, all checks passed"
            : "Response quality issues: \(issues.joined(separator: "; "))"
        
        return VerificationResult(
            passed: passed,
            message: message,
            details: details
        )
    }
    
    /// Verify that multiple agents contributed meaningfully to results
    /// - Parameters:
    ///   - results: Array of agent results
    ///   - minAgents: Minimum number of agents that should have contributed
    /// - Returns: Verification result
    static func verifyMultiAgentCollaboration(
        results: [AgentResult],
        minAgents: Int = 2
    ) -> VerificationResult {
        let uniqueAgents = Set(results.map { $0.agentId })
        let agentCount = uniqueAgents.count
        
        let passed = agentCount >= minAgents
        let message = passed
            ? "Multi-agent collaboration verified: \(agentCount) agents contributed"
            : "Insufficient agent collaboration: only \(agentCount) agents contributed (minimum: \(minAgents))"
        
        var details: [String: Any] = [
            "uniqueAgentCount": agentCount,
            "totalResults": results.count,
            "agentIds": Array(uniqueAgents)
        ]
        
        // Check if agents used different tools
        let allToolCalls = results.flatMap { $0.toolCalls }
        let uniqueTools = Set(allToolCalls.map { $0.toolName })
        details["uniqueTools"] = Array(uniqueTools)
        details["totalToolCalls"] = allToolCalls.count
        
        // Check response diversity
        let responseLengths = results.map { $0.content.count }
        let avgLength = responseLengths.reduce(0, +) / max(responseLengths.count, 1)
        details["averageResponseLength"] = avgLength
        details["responseLengths"] = responseLengths
        
        return VerificationResult(
            passed: passed,
            message: message,
            details: details
        )
    }
    
    /// Verify that tool results are present in context
    /// - Parameters:
    ///   - context: The agent context to check
    ///   - expectedToolResults: Array of tool result keys that should be present
    /// - Returns: Verification result
    static func verifyToolResultsInContext(
        context: AgentContext,
        expectedToolResults: [String]
    ) -> VerificationResult {
        let toolResultKeys = Array(context.toolResults.keys)
        let foundKeys = expectedToolResults.filter { toolResultKeys.contains($0) }
        
        let passed = foundKeys.count == expectedToolResults.count
        let message = passed
            ? "All expected tool results found in context: \(foundKeys.joined(separator: ", "))"
            : "Missing tool results in context. Expected: \(expectedToolResults.joined(separator: ", ")), Found: \(toolResultKeys.joined(separator: ", "))"
        
        return VerificationResult(
            passed: passed,
            message: message,
            details: [
                "expectedKeys": expectedToolResults,
                "foundKeys": foundKeys,
                "allKeys": toolResultKeys
            ]
        )
    }
    
    /// Verify that conversation history is being maintained
    /// - Parameters:
    ///   - conversation: The conversation to check
    ///   - expectedMessageCount: Expected minimum number of messages
    /// - Returns: Verification result
    static func verifyConversationHistory(
        conversation: Conversation,
        expectedMessageCount: Int = 2
    ) -> VerificationResult {
        let messageCount = conversation.messages.count
        let passed = messageCount >= expectedMessageCount
        
        let message = passed
            ? "Conversation history maintained: \(messageCount) messages"
            : "Insufficient conversation history: \(messageCount) messages (expected: \(expectedMessageCount))"
        
        // Check message roles are alternating
        var roleIssues: [String] = []
        for (index, msg) in conversation.messages.enumerated() {
            if index > 0 {
                let prevRole = conversation.messages[index - 1].role
                // Should alternate between user and assistant
                if msg.role == prevRole {
                    roleIssues.append("Messages \(index-1) and \(index) have same role: \(msg.role)")
                }
            }
        }
        
        var details: [String: Any] = [
            "messageCount": messageCount,
            "expectedCount": expectedMessageCount
        ]
        
        if !roleIssues.isEmpty {
            details["roleIssues"] = roleIssues
        }
        
        return VerificationResult(
            passed: passed && roleIssues.isEmpty,
            message: roleIssues.isEmpty ? message : "\(message). Issues: \(roleIssues.joined(separator: "; "))",
            details: details
        )
    }
    
    /// Comprehensive verification of a multi-agent scenario
    /// - Parameters:
    ///   - results: Array of agent results
    ///   - conversation: The conversation
    ///   - expectedTools: Expected tools that should have been used
    ///   - minResponseLength: Minimum response length
    /// - Returns: Dictionary of all verification results
    static func verifyMultiAgentScenario(
        results: [AgentResult],
        conversation: Conversation,
        expectedTools: [String] = [],
        minResponseLength: Int = 10
    ) -> [String: VerificationResult] {
        var allResults: [String: VerificationResult] = [:]
        
        // Verify each result's quality
        for (index, result) in results.enumerated() {
            allResults["result_\(index)_quality"] = verifyResponseQuality(
                result: result,
                minLength: minResponseLength
            )
        }
        
        // Verify tool usage across all results
        if !expectedTools.isEmpty {
            let allToolCalls = results.flatMap { $0.toolCalls }
            let toolNames = allToolCalls.map { $0.toolName }
            let foundTools = expectedTools.filter { toolNames.contains($0) }
            allResults["tool_usage"] = VerificationResult(
                passed: !foundTools.isEmpty,
                message: foundTools.isEmpty 
                    ? "No expected tools were used"
                    : "Tools used: \(foundTools.joined(separator: ", "))",
                details: [
                    "expected": expectedTools,
                    "found": foundTools,
                    "all": toolNames
                ]
            )
        }
        
        // Verify multi-agent collaboration
        allResults["collaboration"] = verifyMultiAgentCollaboration(results: results)
        
        // Verify conversation history
        allResults["conversation_history"] = verifyConversationHistory(conversation: conversation)
        
        return allResults
    }
}

