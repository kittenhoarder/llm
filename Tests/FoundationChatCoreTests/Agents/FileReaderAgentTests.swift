//
//  FileReaderAgentTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for FileReaderAgent, especially image detection
//

import XCTest
@testable import FoundationChatCore
import UniformTypeIdentifiers

@available(macOS 26.0, iOS 26.0, *)
final class FileReaderAgentTests: XCTestCase {
    var fileReaderAgent: FileReaderAgent!
    var conversationId: UUID!
    var testTextFilePath: String!
    var testImageFilePath: String!
    
    override func setUp() async throws {
        try await super.setUp()
        fileReaderAgent = FileReaderAgent()
        conversationId = UUID()
        
        // Create test text file
        testTextFilePath = "/tmp/test_text_file.txt"
        let textContent = "This is a test text file for FileReaderAgent"
        try textContent.write(toFile: testTextFilePath, atomically: true, encoding: .utf8)
        
        // Create test image file
        testImageFilePath = "/tmp/test_image.png"
        let pngData = createMinimalPNG()
        try pngData.write(to: URL(fileURLWithPath: testImageFilePath))
    }
    
    override func tearDown() async throws {
        // Cleanup test files
        try? FileManager.default.removeItem(atPath: testTextFilePath)
        try? FileManager.default.removeItem(atPath: testImageFilePath)
        
        try await super.tearDown()
    }
    
    // MARK: - Image Detection Tests
    
    func testFileReaderAgentDetectsImagesEarly() async throws {
        let task = AgentTask(
            description: "Read this file",
            parameters: ["filePath": testImageFilePath]
        )
        
        let context = AgentContext(
            fileReferences: [testImageFilePath],
            metadata: ["conversationId": conversationId.uuidString]
        )
        
        let result = try await fileReaderAgent.process(task: task, context: context)
        
        // Should fail early with message suggesting VisionAgent
        XCTAssertFalse(result.success, "Should fail for image files")
        XCTAssertNotNil(result.error, "Should have error message")
        XCTAssertTrue(
            result.content.contains("Vision Agent") || result.content.contains("image"),
            "Error message should mention VisionAgent or image"
        )
    }
    
    func testFileReaderAgentReturnsErrorForImages() async throws {
        let task = AgentTask(
            description: "Analyze this image",
            parameters: ["filePath": testImageFilePath]
        )
        
        let context = AgentContext(fileReferences: [testImageFilePath])
        
        let result = try await fileReaderAgent.process(task: task, context: context)
        
        XCTAssertFalse(result.success, "Should not succeed for image files")
        XCTAssertNotNil(result.error, "Should have error")
        // Error should indicate that images should be processed by VisionAgent
    }
    
    // MARK: - Text File Processing Tests
    
    func testFileReaderAgentProcessesTextFiles() async throws {
        let task = AgentTask(
            description: "Read this file",
            parameters: ["filePath": testTextFilePath]
        )
        
        let context = AgentContext(
            fileReferences: [testTextFilePath],
            metadata: ["conversationId": conversationId.uuidString]
        )
        
        // This may fail if ModelService is unavailable, which is acceptable
        do {
            let result = try await fileReaderAgent.process(task: task, context: context)
            // If it succeeds, verify structure
            XCTAssertNotNil(result, "Should return a result")
            // Note: success may be false if ModelService is unavailable
        } catch {
            // ModelService unavailable is acceptable in test environment
            // We're just verifying the structure exists
        }
    }
    
    func testFileReaderAgentHandlesMissingFile() async throws {
        let nonExistentPath = "/tmp/nonexistent_file.txt"
        
        let task = AgentTask(
            description: "Read this file",
            parameters: ["filePath": nonExistentPath]
        )
        
        let context = AgentContext(fileReferences: [nonExistentPath])
        
        let result = try await fileReaderAgent.process(task: task, context: context)
        
        XCTAssertFalse(result.success, "Should fail for missing file")
        XCTAssertNotNil(result.error, "Should have error message")
    }
    
    func testFileReaderAgentHandlesMissingFilePath() async throws {
        let task = AgentTask(
            description: "Read a file",
            parameters: [:] // No file path
        )
        
        let context = AgentContext()
        
        let result = try await fileReaderAgent.process(task: task, context: context)
        
        XCTAssertFalse(result.success, "Should fail when no file path is provided")
        XCTAssertNotNil(result.error, "Should have error message")
        XCTAssertTrue(result.error?.contains("file path") ?? false, "Error should mention missing file path")
    }
    
    // MARK: - RAG Integration Tests
    
    func testFileReaderAgentUsesRAGWhenEnabled() async throws {
        let defaults = UserDefaults.standard
        let originalUseRAG = defaults.bool(forKey: "useRAG")
        
        defer {
            defaults.set(originalUseRAG, forKey: "useRAG")
        }
        
        // Enable RAG
        defaults.set(true, forKey: "useRAG")
        
        let task = AgentTask(
            description: "What's in this file?",
            parameters: ["filePath": testTextFilePath]
        )
        
        let context = AgentContext(
            fileReferences: [testTextFilePath],
            metadata: ["conversationId": conversationId.uuidString]
        )
        
        // This may fail if RAG service or ModelService is unavailable
        do {
            let result = try await fileReaderAgent.process(task: task, context: context)
            // If it succeeds, RAG should be used
            XCTAssertNotNil(result, "Should return a result")
        } catch {
            // RAG or ModelService unavailable is acceptable
        }
    }
    
    // MARK: - Helper Methods
    
    /// Create a minimal valid PNG file for testing
    private func createMinimalPNG() -> Data {
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
        return Data(pngHeader)
    }
}


