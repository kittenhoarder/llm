//
//  FoundationChat.swift
//  FoundationChat
//
//  Entry point for the Foundation Chat CLI application
//

import Foundation
import ArgumentParser
import FoundationModels
import FoundationChatCore

@available(macOS 26.0, *)
@main
struct FoundationChat: AsyncParsableCommand {
    nonisolated(unsafe) static var configuration = CommandConfiguration(
        commandName: "foundation-chat",
        abstract: "A CLI application for interacting with LLMs using Foundation APIs",
        subcommands: [Chat.self, Search.self],
        defaultSubcommand: Chat.self
    )
}

/// Main chat command for interactive LLM conversations
@available(macOS 26.0, *)
struct Chat: AsyncParsableCommand {
    nonisolated(unsafe) static var configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive chat session with the LLM"
    )
    
    @Option(name: .shortAndLong, help: "The message to send to the LLM")
    var message: String?
    
    @Flag(name: .shortAndLong, inversion: .prefixedEnableDisable, help: "Disable SerpAPI search tool for the LLM")
    var disableSearch: Bool = false
    
    @Option(name: .long, help: "SerpAPI API key (can also be set via SERPAPI_API_KEY environment variable)")
    var serpapiKey: String?
    
    @Flag(name: .shortAndLong, help: "Enable verbose output showing tool usage")
    var verbose: Bool = false
    
    @available(macOS 26.0, *)
    func run() async throws {
        // Check if Foundation Models are available using ModelService
        let modelService = ModelService()
        let availability = await modelService.checkAvailability()
        guard case .available = availability else {
            print("Error: Foundation Models are not available.")
            print(ModelService.errorMessage(for: availability))
            throw ExitCode.failure
        }
        
        // Initialize tools
        var tools: [any Tool] = []
        if !disableSearch {
            // Get API key from command line, environment variable, or UserDefaults
            let apiKey = serpapiKey ?? ProcessInfo.processInfo.environment["SERPAPI_API_KEY"]
            let tool = FoundationChatCore.SerpAPIFoundationTool(apiKey: apiKey)
            tools.append(tool)
            
            // Check if API key is available
            let hasKey = apiKey != nil && !apiKey!.isEmpty
                || UserDefaults.standard.string(forKey: "serpapiApiKey") != nil
            
            if hasKey {
                print("✓ SerpAPI search tool enabled")
            } else {
                print("⚠ SerpAPI search tool enabled (no API key - set via --serpapi-key or SERPAPI_API_KEY)")
            }
        }
        
        // Update model service with tools
        await modelService.updateTools(tools)
        
        // Store conversation history for context
        var conversationHistory: [(role: String, content: String)] = []
        
        if let message = message {
            // Single message mode
            print("Processing: \(message)\n")
            do {
                // Enhance message if it explicitly asks for search
                let enhancedMessage = enhanceMessageForSearch(message)
                let response = try await modelService.respond(to: enhancedMessage)
                
                if verbose && !response.toolCalls.isEmpty {
                    print("[DEBUG] Tool calls made:")
                    for toolCall in response.toolCalls {
                        print("  - \(toolCall.toolName): \(toolCall.arguments)")
                    }
                    print()
                }
                
                print("Assistant: \(response.content)")
                
                // Append tool usage indicator if tools were used
                if !response.toolCalls.isEmpty {
                    let toolNames = response.toolCalls.map { ToolNameMapper.friendlyName(for: $0.toolName) }
                    print("Tools used: \(toolNames.joined(separator: ", "))")
                }
            } catch {
                print("Error: \(error.localizedDescription)")
            }
        } else {
            // Interactive mode
            print("Foundation Chat - Interactive Mode")
            print("Using Apple Foundation Models")
            if !disableSearch {
                print("SerpAPI search tool is available")
            }
            print("Type 'exit' or 'quit' to end the session gracefully")
            print("Press Ctrl+C to interrupt and exit immediately")
            print("Type 'help' for more information\n")
            
            while true {
                print("You: ", terminator: "")
                guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !input.isEmpty else {
                    continue
                }
                
                if input.lowercased() == "exit" || input.lowercased() == "quit" {
                    print("Goodbye!")
                    break
                }
                
                if input.lowercased() == "help" {
                    printHelp()
                    continue
                }
                
                // Send to LLM
                print("\nAssistant: ", terminator: "")
                do {
                    // Enhance message if it explicitly asks for search
                    let enhancedMessage = enhanceMessageForSearch(input)
                    
                    // Add to conversation history
                    conversationHistory.append((role: "user", content: input))
                    
                    let response = try await modelService.respond(to: enhancedMessage)
                    
                    // DEBUG: Show what we got back
                    print("\n[DEBUG CLI] Response received:")
                    print("  Content length: \(response.content.count)")
                    print("  Tool calls count: \(response.toolCalls.count)")
                    if !response.toolCalls.isEmpty {
                        print("  Tool calls: \(response.toolCalls.map { $0.toolName }.joined(separator: ", "))")
                    }
                    
                    // Add response to history
                    conversationHistory.append((role: "assistant", content: response.content))
                    
                    if verbose && !response.toolCalls.isEmpty {
                        print("\n[DEBUG] Tool calls made:")
                        for toolCall in response.toolCalls {
                            print("  - \(toolCall.toolName): \(toolCall.arguments)")
                            if let result = toolCall.result {
                                print("    Result: \(String(result.prefix(100)))...")
                            }
                        }
                        print()
                    }
                    
                    print(response.content)
                    
                    // Append tool usage indicator if tools were used
                    if !response.toolCalls.isEmpty {
                        let toolNames = response.toolCalls.map { ToolNameMapper.friendlyName(for: $0.toolName) }
                        print("Tools used: \(toolNames.joined(separator: ", "))")
                    } else {
                        print("[DEBUG CLI] No tool calls in response")
                    }
                } catch {
                    print("Error: \(error.localizedDescription)")
                }
                print()
            }
        }
    }
    
    private func printHelp() {
        print("""
        Available commands:
          help            - Show this help message
          exit/quit       - Exit the application gracefully
        
        The LLM can automatically use SerpAPI search when needed.
        Use --verbose to see when tools are being used.
        
        Note: You can also press Ctrl+C at any time to exit immediately.
        """)
    }
    
    /// Enhance message to encourage tool usage when explicitly requested
    private func enhanceMessageForSearch(_ message: String) -> String {
        let lowercased = message.lowercased()
        
        // Check for explicit search requests
        let searchKeywords = ["search", "look up", "find", "serpapi", "use the tool", "use serpapi"]
        let hasSearchRequest = searchKeywords.contains { lowercased.contains($0) }
        
        // Check for queries that likely need current information
        let currentInfoKeywords = ["current", "recent", "latest", "today", "now", "2024", "2025", "inflation", "weather"]
        let needsCurrentInfo = currentInfoKeywords.contains { lowercased.contains($0) }
        
        if hasSearchRequest || needsCurrentInfo {
            // Add a prefix that encourages tool usage
            return "Please use the serpapi_search tool to find current information. User query: \(message)"
        }
        
        return message
    }
}

/// Search command for direct SerpAPI searches
@available(macOS 26.0, *)
struct Search: AsyncParsableCommand {
    nonisolated(unsafe) static var configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search the web using SerpAPI"
    )
    
    @Argument(help: "The search query")
    var query: String
    
    @Option(name: .long, help: "SerpAPI API key (can also be set via SERPAPI_API_KEY environment variable)")
    var serpapiKey: String?
    
    func run() async throws {
        print("Searching SerpAPI for: \(query)\n")
        
        // Get API key from command line, environment variable, or UserDefaults
        let apiKey = serpapiKey ?? ProcessInfo.processInfo.environment["SERPAPI_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "serpapiApiKey")
        
        guard let key = apiKey, !key.isEmpty else {
            print("Error: SerpAPI key not configured. Set via --serpapi-key or SERPAPI_API_KEY environment variable.")
            throw ExitCode.failure
        }
        
        let client = FoundationChatCore.SerpAPIClient(apiKey: key)
        let tool = FoundationChatCore.SerpAPITool(client: client)
        do {
            let result = try await tool.search(query: query)
            print(result)
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
