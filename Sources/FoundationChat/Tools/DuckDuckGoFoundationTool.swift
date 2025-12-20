//
//  DuckDuckGoFoundationTool.swift
//  FoundationChat
//
//  DuckDuckGo tool adapter for Apple Foundation Models
//

import Foundation
import FoundationModels

/// DuckDuckGo search tool for Apple Foundation Models
@available(macOS 26.0, iOS 26.0, *)
public struct DuckDuckGoFoundationTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "duckduckgo_search"
    public let description = "Search DuckDuckGo Instant Answers API for quick facts, definitions, calculations, and topic summaries. Returns concise, formatted answers suitable for LLM context."
    
    public init() {}
    
    @Generable
    public struct Arguments {
        public let query: String
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let tool = DuckDuckGoTool()
        do {
            return try await tool.search(query: arguments.query)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

