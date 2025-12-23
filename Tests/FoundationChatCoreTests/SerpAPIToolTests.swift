//
//  SerpAPIToolTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for SerpAPITool formatting logic
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class SerpAPIToolTests: XCTestCase {
    
    func testSerpAPIToolFormattingWithOrganicResults() async throws {
        let response = SerpAPIResponse(
            organicResults: [
                OrganicResult(
                    position: 1,
                    title: "Test Title",
                    link: "https://example.com",
                    displayedLink: "example.com",
                    snippet: "This is a test snippet",
                    date: nil,
                    source: "Example Source"
                )
            ],
            answerBox: nil,
            knowledgeGraph: nil,
            relatedQuestions: nil,
            searchMetadata: nil
        )
        
        // Create a mock client (we won't actually use it for formatting tests)
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client)
        
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Test Title"))
        XCTAssertTrue(formatted.contains("https://example.com"))
        XCTAssertTrue(formatted.contains("This is a test snippet"))
        XCTAssertTrue(formatted.contains("Search Results"))
    }
    
    func testSerpAPIToolFormattingWithAnswerBox() async throws {
        let response = SerpAPIResponse(
            organicResults: nil,
            answerBox: AnswerBox(
                answer: "42",
                title: "Answer Title",
                link: "https://example.com/answer",
                snippet: "The answer is 42"
            ),
            knowledgeGraph: nil,
            relatedQuestions: nil,
            searchMetadata: nil
        )
        
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client)
        
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Answer: 42"))
        XCTAssertTrue(formatted.contains("Answer Title"))
    }
    
    func testSerpAPIToolFormattingWithKnowledgeGraph() async throws {
        let response = SerpAPIResponse(
            organicResults: nil,
            answerBox: nil,
            knowledgeGraph: KnowledgeGraph(
                title: "Test Topic",
                type: "Person",
                description: "This is a test description",
                source: Source(name: "Wikipedia", link: "https://wikipedia.org")
            ),
            relatedQuestions: nil,
            searchMetadata: nil
        )
        
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client)
        
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Test Topic"))
        XCTAssertTrue(formatted.contains("This is a test description"))
        XCTAssertTrue(formatted.contains("Wikipedia"))
    }
    
    func testSerpAPIToolFormattingTruncatesLongSnippets() async throws {
        let longSnippet = String(repeating: "A", count: 1000)
        let response = SerpAPIResponse(
            organicResults: [
                OrganicResult(
                    position: 1,
                    title: "Test",
                    link: "https://example.com",
                    displayedLink: nil,
                    snippet: longSnippet,
                    date: nil,
                    source: nil
                )
            ],
            answerBox: nil,
            knowledgeGraph: nil,
            relatedQuestions: nil,
            searchMetadata: nil
        )
        
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client, maxSnippetLength: 500)
        
        let formatted = tool.formatResponse(response)
        
        // Should contain truncated snippet with "..."
        XCTAssertTrue(formatted.contains("..."))
        // Should not contain the full 1000 character snippet
        XCTAssertFalse(formatted.contains(String(repeating: "A", count: 1000)))
    }
    
    func testSerpAPIToolFormattingEmptyResponse() async throws {
        let response = SerpAPIResponse(
            organicResults: nil,
            answerBox: nil,
            knowledgeGraph: nil,
            relatedQuestions: nil,
            searchMetadata: nil
        )
        
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client)
        
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("No search results available"))
    }
    
    func testSerpAPIToolLimitsResults() async throws {
        let manyResults = (1...10).map { index in
            OrganicResult(
                position: index,
                title: "Result \(index)",
                link: "https://example.com/\(index)",
                displayedLink: nil,
                snippet: "Snippet \(index)",
                date: nil,
                source: nil
            )
        }
        
        let response = SerpAPIResponse(
            organicResults: manyResults,
            answerBox: nil,
            knowledgeGraph: nil,
            relatedQuestions: nil,
            searchMetadata: nil
        )
        
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client, maxResults: 5)
        
        let formatted = tool.formatResponse(response)
        
        // Should contain first 5 results
        XCTAssertTrue(formatted.contains("Result 1"))
        XCTAssertTrue(formatted.contains("Result 5"))
        // Should mention there are more
        XCTAssertTrue(formatted.contains("and 5 more"))
        // Should not contain result 6
        XCTAssertFalse(formatted.contains("Result 6"))
    }
    
    func testSerpAPIToolFormattingWithRelatedQuestions() async throws {
        let response = SerpAPIResponse(
            organicResults: nil,
            answerBox: nil,
            knowledgeGraph: nil,
            relatedQuestions: [
                RelatedQuestion(
                    question: "What is Swift?",
                    snippet: "Swift is a programming language",
                    title: nil,
                    link: nil
                )
            ],
            searchMetadata: nil
        )
        
        let client = SerpAPIClient(apiKey: "test-key")
        let tool = SerpAPITool(client: client)
        
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Related Questions"))
        XCTAssertTrue(formatted.contains("What is Swift?"))
        XCTAssertTrue(formatted.contains("Swift is a programming language"))
    }
}


