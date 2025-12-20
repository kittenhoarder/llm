//
//  ContextOptimizerTests.swift
//  FoundationChatCoreTests
//
//  Tests for ContextOptimizer service
//

import XCTest
@testable import FoundationChatCore
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
final class ContextOptimizerTests: XCTestCase {
    var optimizer: ContextOptimizer!
    
    override func setUp() async throws {
        optimizer = ContextOptimizer()
    }
    
    func testOptimizeContextWithSmallMessageSet() async throws {
        let messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there")
        ]
        
        let optimized = try await optimizer.optimizeContext(
            messages: messages,
            systemPrompt: nil,
            tools: []
        )
        
        XCTAssertEqual(optimized.messages.count, messages.count)
        XCTAssertEqual(optimized.messagesTruncated, 0)
    }
    
    func testOptimizeContextRespectsTokenLimit() async throws {
        // Create many long messages
        var messages: [Message] = []
        for i in 0..<30 {
            messages.append(Message(
                role: i % 2 == 0 ? .user : .assistant,
                content: "Message \(i): " + String(repeating: "This is a long message with lots of content. ", count: 20)
            ))
        }
        
        let optimized = try await optimizer.optimizeContext(
            messages: messages,
            systemPrompt: nil,
            tools: []
        )
        
        // Should have compacted messages
        XCTAssertLessThan(optimized.messages.count, messages.count)
        XCTAssertGreaterThan(optimized.messagesTruncated, 0)
        
        // Token usage should be within limits
        XCTAssertLessThanOrEqual(optimized.tokenUsage.totalTokens, 4096)
    }
    
    func testOptimizeContextWithTools() async throws {
        let messages = [
            Message(role: .user, content: "Test message")
        ]
        
        let tool = DuckDuckGoFoundationTool()
        let optimized = try await optimizer.optimizeContext(
            messages: messages,
            systemPrompt: nil,
            tools: [tool]
        )
        
        // Should account for tool tokens
        XCTAssertGreaterThan(optimized.tokenUsage.toolTokens, 0)
    }
}



