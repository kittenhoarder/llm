//
//  PromptTemplates.swift
//  FoundationChatCore
//
//  Centralized prompts optimized for small context/parameter models
//

import Foundation

/// Collection of optimized prompt templates
@available(macOS 26.0, iOS 26.0, *)
public struct PromptTemplates {
    
    // MARK: - Orchestrator
    
    /// Optimized analysis prompt for the Orchestrator
    /// Uses JSON output enforcement
    public static func orchestratorAnalysis(
        task: String,
        agents: [any Agent],
        fileReferences: [String],
        hasWebSearch: Bool,
        ragContent: String?
    ) -> String {
        let agentList = agents.map { "- \($0.name) (capabilities: \($0.capabilities.map { $0.rawValue }.joined(separator: ", ")))" }.joined(separator: "\n")
        
        var prompt = """
        You are the Orchestrator. breakdown the User Task into steps.
        
        # Available Agents
        \(agentList)
        
        # Rules
        1. Use "WebSearch" for external info.
        2. Use "FileReader" for local file content.
        3. Use "Vision" for images.
        4. "dependencies" is an array of subtask IDs (integers).
        
        # User Task
        \(task)
        
        """
        
        if !fileReferences.isEmpty {
            prompt += "\n# Attached Files\n\(fileReferences.joined(separator: "\n"))\n"
        }
        
        if let rag = ragContent, !rag.isEmpty {
            prompt += "\n# Document Content\n\(rag)\n"
        }
        
        prompt += """
        
        # Response Format
        You MUST respond with ONLY a valid JSON object. No markdown, no conversation.
        
        {
          "subtasks": [
            {
              "id": 1,
              "description": "Exact step description",
              "agent": "Name of agent",
              "dependencies": [] 
            }
          ]
        }
        """
        
        return prompt
    }
    
    // MARK: - Code Analysis
    
    /// Optimized system prompt for Code Analysis
    public static var codeAnalysisSystemPrompt: String {
        return """
        Role: Code Analysis Agent.
        Goal: Analyze codebase using tools.
        
        Tools:
        - `codebase_semantic_search`: Conceptual queries.
        - `codebase_grep_search`: Exact string/symbol matching.
        - `codebase_read_file`: Read content.
        - `codebase_list_files`: Explore structure.
        
        Protocol:
        1. Search first. Don't guess.
        2. Read files to confirm.
        3. Be telegraphic and concise.
        """
    }
}
