//
//  TokenCounterTests.swift
//  FoundationChatCoreTests
//
//  Tests for TokenCounter service
//

import XCTest
@testable import FoundationChatCore
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
final class TokenCounterTests: XCTestCase {
    var tokenCounter: TokenCounter!
    
    override func setUp() async throws {
        tokenCounter = TokenCounter()
    }
    
    func testCountTokensForSimpleText() async {
        let text = "Hello world"
        let count = await tokenCounter.countTokens(text)
        // "Hello world" = 11 chars, should be ~3 tokens (11/4 = 2.75, rounded up)
        XCTAssertGreaterThanOrEqual(count, 2)
        XCTAssertLessThanOrEqual(count, 4)
    }
    
    func testCountTokensForLongText() async {
        let text = String(repeating: "Hello world ", count: 100) // ~1200 chars
        let count = await tokenCounter.countTokens(text)
        // Should be approximately 1200/4 = 300 tokens
        XCTAssertGreaterThanOrEqual(count, 250)
        XCTAssertLessThanOrEqual(count, 350)
    }
    
    func testCountTokensForMessage() async {
        let message = Message(
            role: .user,
            content: "This is a test message"
        )
        let count = await tokenCounter.countTokens(message)
        XCTAssertGreaterThan(count, 0)
    }
    
    func testCountTokensForMultipleMessages() async {
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there"),
            Message(role: .user, content: "How are you?")
        ]
        let count = await tokenCounter.countTokens(messages)
        XCTAssertGreaterThan(count, 0)
    }
    
    func testTokenCountCaching() async {
        let text = "Test text for caching"
        let count1 = await tokenCounter.countTokens(text)
        let count2 = await tokenCounter.countTokens(text)
        XCTAssertEqual(count1, count2)
    }
}




