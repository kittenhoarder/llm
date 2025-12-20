//
//  MessageCompactorTests.swift
//  FoundationChatCoreTests
//
//  Tests for MessageCompactor service
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class MessageCompactorTests: XCTestCase {
    var compactor: MessageCompactor!
    
    override func setUp() async throws {
        compactor = MessageCompactor(recentMessagesCount: 5)
    }
    
    func testCompactWithSmallMessageSet() async throws {
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi")
        ]
        
        // Should return as-is if under limit
        let compacted = try await compactor.compact(messages: messages, maxTokens: 1000)
        XCTAssertEqual(compacted.count, messages.count)
    }
    
    func testCompactKeepsRecentMessages() async throws {
        // Create many messages
        var messages: [Message] = []
        for i in 0..<20 {
            messages.append(Message(
                role: i % 2 == 0 ? .user : .assistant,
                content: "Message \(i): " + String(repeating: "text ", count: 50)
            ))
        }
        
        // Compact with small token budget
        let compacted = try await compactor.compact(messages: messages, maxTokens: 500)
        
        // Should have summary + recent messages
        XCTAssertLessThan(compacted.count, messages.count)
        XCTAssertGreaterThan(compacted.count, 0)
    }
    
    func testSlidingWindowCompaction() async throws {
        var messages: [Message] = []
        for i in 0..<15 {
            messages.append(Message(
                role: .user,
                content: "Message \(i): " + String(repeating: "content ", count: 30)
            ))
        }
        
        let compacted = try await compactor.compactSlidingWindow(messages: messages, maxTokens: 300)
        XCTAssertLessThanOrEqual(compacted.count, messages.count)
        XCTAssertGreaterThan(compacted.count, 0)
    }
}



