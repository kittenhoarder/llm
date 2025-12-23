//
//  MockLLMService.swift
//  FoundationChatTests
//
//  Mock services for testing LLM integration
//

import Foundation
@testable import FoundationChat

/// Mock DuckDuckGo client for testing
public actor MockDuckDuckGoClient {
    private let responses: [String: DuckDuckGoResponse]
    private let errors: [String: Error]
    private let delay: TimeInterval
    
    public init(
        responses: [String: DuckDuckGoResponse] = [:],
        errors: [String: Error] = [:],
        delay: TimeInterval = 0.1
    ) {
        self.responses = responses
        self.errors = errors
        self.delay = delay
    }
    
    public func search(query: String) async throws -> DuckDuckGoResponse {
        // Simulate network delay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        // Check for error
        if let error = errors[query] {
            throw error
        }
        
        // Return response if available
        if let response = responses[query] {
            return response
        }
        
        // Default response
        return DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: "Mock abstract for: \(query)",
            abstractText: nil,
            abstractURL: nil,
            abstractSource: "Mock Source",
            image: nil,
            heading: "Mock Heading",
            relatedTopics: nil,
            results: nil,
            definition: nil,
            definitionURL: nil,
            definitionSource: nil,
            entity: nil,
            meta: nil
        )
    }
}

/// Mock tool logger that captures logs
public class MockToolLogger: ToolLogger {
    public var logs: [(level: LogLevel, message: String, metadata: [String: Any]?)] = []
    
    public init() {}
    
    public func log(level: LogLevel, message: String, metadata: [String: Any]?) {
        logs.append((level: level, message: message, metadata: metadata))
    }
    
    public func clear() {
        logs.removeAll()
    }
    
    public func hasLog(level: LogLevel, containing: String) -> Bool {
        return logs.contains { $0.level == level && $0.message.contains(containing) }
    }
}

/// Helper to create mock DuckDuckGo responses
public struct MockResponseFactory {
    public static func createCalculationResponse(query: String, answer: String) -> DuckDuckGoResponse {
        return DuckDuckGoResponse(
            answer: answer,
            answerType: "calc",
            abstract: nil,
            abstractText: nil,
            abstractURL: nil,
            abstractSource: nil,
            image: nil,
            heading: nil,
            relatedTopics: nil,
            results: nil,
            definition: nil,
            definitionURL: nil,
            definitionSource: nil,
            entity: nil,
            meta: nil
        )
    }
    
    public static func createDefinitionResponse(term: String, definition: String) -> DuckDuckGoResponse {
        return DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: nil,
            abstractText: nil,
            abstractURL: nil,
            abstractSource: nil,
            image: nil,
            heading: term,
            relatedTopics: nil,
            results: nil,
            definition: definition,
            definitionURL: "https://example.com/definition",
            definitionSource: "Dictionary",
            entity: nil,
            meta: nil
        )
    }
    
    public static func createAbstractResponse(topic: String, abstract: String) -> DuckDuckGoResponse {
        return DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: abstract,
            abstractText: nil,
            abstractURL: "https://example.com/topic",
            abstractSource: "Wikipedia",
            image: nil,
            heading: topic,
            relatedTopics: nil,
            results: nil,
            definition: nil,
            definitionURL: nil,
            definitionSource: nil,
            entity: nil,
            meta: nil
        )
    }
    
    public static func createEmptyResponse() -> DuckDuckGoResponse {
        return DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: nil,
            abstractText: nil,
            abstractURL: nil,
            abstractSource: nil,
            image: nil,
            heading: nil,
            relatedTopics: nil,
            results: nil,
            definition: nil,
            definitionURL: nil,
            definitionSource: nil,
            entity: nil,
            meta: nil
        )
    }
}










