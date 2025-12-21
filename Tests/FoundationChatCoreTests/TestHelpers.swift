//
//  TestHelpers.swift
//  FoundationChatCoreTests
//
//  Common test utilities and helpers
//

import Foundation
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
enum TestHelpers {
    /// Create a test conversation
    /// - Parameters:
    ///   - title: Conversation title
    ///   - conversationService: Conversation service instance
    /// - Returns: Created conversation
    /// - Throws: Error if creation fails
    static func createTestConversation(
        title: String = "Test Conversation",
        conversationService: ConversationService
    ) throws -> Conversation {
        return try conversationService.createConversation(title: title)
    }
    
    /// Create a test file attachment
    /// - Parameters:
    ///   - originalName: Original filename
    ///   - sandboxPath: Path in sandbox
    ///   - content: File content
    /// - Returns: FileAttachment
    static func createTestFileAttachment(
        originalName: String,
        sandboxPath: String,
        content: String
    ) -> FileAttachment {
        let data = content.data(using: .utf8) ?? Data()
        return FileAttachment(
            originalName: originalName,
            sandboxPath: sandboxPath,
            fileSize: Int64(data.count),
            mimeType: "text/plain"
        )
    }
    
    /// Create a test image file
    /// - Parameter path: File path
    /// - Returns: Data for the image file
    /// - Throws: Error if file creation fails
    static func createTestImageFile(at path: String) throws -> Data {
        // Minimal 1x1 PNG data
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, // IHDR chunk length
            0x49, 0x48, 0x44, 0x52, // IHDR
            0x00, 0x00, 0x00, 0x01, // Width: 1
            0x00, 0x00, 0x00, 0x01, // Height: 1
            0x08, 0x02, 0x00, 0x00, 0x00, // Bit depth, color type, etc.
            0x90, 0x77, 0x53, 0xDE, // CRC
            0x00, 0x00, 0x00, 0x0A, // IDAT chunk length
            0x49, 0x44, 0x41, 0x54, // IDAT
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // Compressed data
            0x0D, 0x0A, 0x2D, 0xB4, // CRC
            0x00, 0x00, 0x00, 0x00, // IEND chunk length
            0x49, 0x45, 0x4E, 0x44, // IEND
            0xAE, 0x42, 0x60, 0x82  // CRC
        ]
        let data = Data(pngHeader)
        try data.write(to: URL(fileURLWithPath: path))
        return data
    }
    
    /// Cleanup test files
    /// - Parameter paths: Array of file paths to delete
    static func cleanupTestFiles(_ paths: [String]) {
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
    
    /// Create a minimal PNG data for testing
    /// - Returns: PNG data
    static func createMinimalPNG() -> Data {
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
            0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54,
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01,
            0x0D, 0x0A, 0x2D, 0xB4,
            0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
            0xAE, 0x42, 0x60, 0x82
        ]
        return Data(pngHeader)
    }
    
    /// Ensure all default agents are initialized in the registry
    /// - Parameter agentService: The AgentService instance to use
    /// - Throws: Error if initialization fails after retries
    static func ensureAgentsInitialized(agentService: AgentService) async throws {
        let expectedAgentNames: Set<String> = [
            AgentName.fileReader,
            AgentName.webSearch,
            AgentName.codeAnalysis,
            AgentName.dataAnalysis,
            AgentName.visionAgent,
            AgentName.coordinator
        ]
        
        // Trigger initialization by calling getAvailableAgents
        let agents = await agentService.getAvailableAgents()
        let agentNames = Set(agents.map { $0.name })
        
        // Verify all expected agents are present
        let missing = expectedAgentNames.subtracting(agentNames)
        if !missing.isEmpty {
            throw TestHelperError.missingAgents(missing: Array(missing))
        }
    }
}

/// Errors for test helpers
enum TestHelperError: Error, LocalizedError {
    case missingAgents(missing: [String])
    
    var errorDescription: String? {
        switch self {
        case .missingAgents(let missing):
            return "Missing expected agents: \(missing.joined(separator: ", "))"
        }
    }
}

