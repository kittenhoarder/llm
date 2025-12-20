//
//  DuckDuckGoTests.swift
//  FoundationChatTests
//
//  Unit tests for DuckDuckGo Instant Answers integration
//

import XCTest
@testable import FoundationChat

final class DuckDuckGoTests: XCTestCase {
    
    // MARK: - Model Tests
    
    func testDuckDuckGoResponseDecoding() throws {
        let json = """
        {
            "Answer": "42",
            "AnswerType": "calc",
            "Abstract": "Test abstract",
            "AbstractText": "Full abstract text",
            "AbstractURL": "https://example.com",
            "AbstractSource": "Wikipedia",
            "Heading": "Test Topic"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(DuckDuckGoResponse.self, from: data)
        
        XCTAssertEqual(response.answer, "42")
        XCTAssertEqual(response.answerType, "calc")
        XCTAssertEqual(response.abstract, "Test abstract")
        XCTAssertEqual(response.abstractText, "Full abstract text")
        XCTAssertEqual(response.abstractURL, "https://example.com")
        XCTAssertEqual(response.abstractSource, "Wikipedia")
        XCTAssertEqual(response.heading, "Test Topic")
        XCTAssertTrue(response.hasContent)
    }
    
    func testDuckDuckGoResponseWithRelatedTopics() throws {
        let json = """
        {
            "RelatedTopics": [
                {
                    "FirstURL": "https://example.com/topic1",
                    "Text": "Topic 1",
                    "Result": "Topic 1 result"
                },
                {
                    "FirstURL": "https://example.com/topic2",
                    "Text": "Topic 2"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(DuckDuckGoResponse.self, from: data)
        
        XCTAssertNotNil(response.relatedTopics)
        XCTAssertEqual(response.relatedTopics?.count, 2)
        XCTAssertEqual(response.relatedTopics?.first?.firstURL, "https://example.com/topic1")
        XCTAssertEqual(response.relatedTopics?.first?.text, "Topic 1")
        XCTAssertTrue(response.hasContent)
    }
    
    func testDuckDuckGoResponseEmpty() throws {
        let json = "{}"
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(DuckDuckGoResponse.self, from: data)
        
        XCTAssertNil(response.answer)
        XCTAssertNil(response.abstract)
        XCTAssertFalse(response.hasContent)
    }
    
    func testDuckDuckGoResponseWithDefinition() throws {
        let json = """
        {
            "Definition": "A programming language",
            "DefinitionURL": "https://example.com/definition",
            "DefinitionSource": "Dictionary"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(DuckDuckGoResponse.self, from: data)
        
        XCTAssertEqual(response.definition, "A programming language")
        XCTAssertEqual(response.definitionURL, "https://example.com/definition")
        XCTAssertEqual(response.definitionSource, "Dictionary")
        XCTAssertTrue(response.hasContent)
    }
    
    // MARK: - Error Tests
    
    func testDuckDuckGoErrorDescriptions() {
        let networkError = DuckDuckGoError.networkError(NSError(domain: "test", code: 1))
        XCTAssertNotNil(networkError.errorDescription)
        XCTAssertNotNil(networkError.failureReason)
        
        let noResults = DuckDuckGoError.noResults
        XCTAssertNotNil(noResults.errorDescription)
        XCTAssertNotNil(noResults.failureReason)
        
        let invalidQuery = DuckDuckGoError.invalidQuery("")
        XCTAssertNotNil(invalidQuery.errorDescription)
        XCTAssertNotNil(invalidQuery.failureReason)
    }
    
    // MARK: - Tool Formatting Tests
    
    func testDuckDuckGoToolFormattingWithAnswer() async throws {
        let response = DuckDuckGoResponse(
            answer: "42",
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
        
        let tool = DuckDuckGoTool()
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Answer: 42"))
        XCTAssertTrue(formatted.contains("Type: calc"))
    }
    
    func testDuckDuckGoToolFormattingWithAbstract() async throws {
        let response = DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: "This is a test abstract that contains information about the topic.",
            abstractText: nil,
            abstractURL: "https://example.com",
            abstractSource: "Wikipedia",
            image: nil,
            heading: "Test Topic",
            relatedTopics: nil,
            results: nil,
            definition: nil,
            definitionURL: nil,
            definitionSource: nil,
            entity: nil,
            meta: nil
        )
        
        let tool = DuckDuckGoTool()
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Summary:"))
        XCTAssertTrue(formatted.contains("Test Topic"))
        XCTAssertTrue(formatted.contains("Source: Wikipedia"))
        XCTAssertTrue(formatted.contains("https://example.com"))
    }
    
    func testDuckDuckGoToolFormattingWithRelatedTopics() async throws {
        let relatedTopics = [
            RelatedTopic(
                firstURL: "https://example.com/topic1",
                icon: nil,
                result: nil,
                text: "Topic 1"
            ),
            RelatedTopic(
                firstURL: "https://example.com/topic2",
                icon: nil,
                result: nil,
                text: "Topic 2"
            ),
            RelatedTopic(
                firstURL: "https://example.com/topic3",
                icon: nil,
                result: nil,
                text: "Topic 3"
            ),
            RelatedTopic(
                firstURL: "https://example.com/topic4",
                icon: nil,
                result: nil,
                text: "Topic 4"
            )
        ]
        
        let response = DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: nil,
            abstractText: nil,
            abstractURL: nil,
            abstractSource: nil,
            image: nil,
            heading: nil,
            relatedTopics: relatedTopics,
            results: nil,
            definition: nil,
            definitionURL: nil,
            definitionSource: nil,
            entity: nil,
            meta: nil
        )
        
        let tool = DuckDuckGoTool()
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("Related Topics"))
        XCTAssertTrue(formatted.contains("Topic 1"))
        XCTAssertTrue(formatted.contains("Topic 2"))
        XCTAssertTrue(formatted.contains("Topic 3"))
        XCTAssertTrue(formatted.contains("and 1 more"))
    }
    
    func testDuckDuckGoToolFormattingEmpty() async throws {
        let response = DuckDuckGoResponse(
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
        
        let tool = DuckDuckGoTool()
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("No instant answer available"))
    }
    
    func testDuckDuckGoToolFormattingTruncatesLongAbstract() async throws {
        let longAbstract = String(repeating: "A", count: 1000)
        let response = DuckDuckGoResponse(
            answer: nil,
            answerType: nil,
            abstract: longAbstract,
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
        
        let tool = DuckDuckGoTool(maxAbstractLength: 500)
        let formatted = tool.formatResponse(response)
        
        XCTAssertTrue(formatted.contains("..."))
        // Check that it's truncated (should be around 500 + "...")
        let summaryLine = formatted.components(separatedBy: "\n").first { $0.contains("Summary:") } ?? ""
        XCTAssertLessThanOrEqual(summaryLine.count, 520) // 500 + "Summary: " + "..."
    }
    
    // MARK: - Integration Tests
    
    // NOTE: These tests referenced ToolIntegration which no longer exists
    // See DuckDuckGoToolIntegrationTests.swift for comprehensive integration tests
}



