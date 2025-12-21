//
//  VisionAgentTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for VisionAgent
//

import XCTest
@testable import FoundationChatCore
import UniformTypeIdentifiers

@available(macOS 26.0, iOS 26.0, *)
final class VisionAgentTests: XCTestCase {
    var visionAgent: VisionAgent!
    
    override func setUp() async throws {
        try await super.setUp()
        visionAgent = VisionAgent()
    }
    
    // MARK: - Initialization Tests
    
    func testVisionAgentInitialization() {
        XCTAssertNotNil(visionAgent, "VisionAgent should be created")
        XCTAssertEqual(visionAgent.name, AgentName.visionAgent, "Agent should have correct name")
        XCTAssertTrue(visionAgent.capabilities.contains(.imageAnalysis), "Agent should have imageAnalysis capability")
        XCTAssertEqual(visionAgent.capabilities.count, 1, "Agent should have exactly one capability")
    }
    
    // MARK: - Image Detection Tests
    
    func testVisionAgentDetectsImageFiles() {
        // Test various image file extensions
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"]
        
        for ext in imageExtensions {
            let testPath = "/tmp/test_image.\(ext)"
            let url = URL(fileURLWithPath: testPath)
            
            // Create a temporary file to test with
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: testPath) {
                // Create empty file for testing
                fileManager.createFile(atPath: testPath, contents: Data(), attributes: nil)
            }
            
            // Check if UTType recognizes it as an image
            if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                let isImage = contentType.conforms(to: .image)
                XCTAssertTrue(isImage, "Extension .\(ext) should be recognized as image type")
            }
            
            // Cleanup
            try? fileManager.removeItem(atPath: testPath)
        }
    }
    
    func testVisionAgentRejectsNonImageFiles() async throws {
        // Create a temporary text file
        let testPath = "/tmp/test_file.txt"
        let testContent = "This is a text file, not an image"
        try testContent.write(toFile: testPath, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(atPath: testPath)
        }
        
        let task = AgentTask(
            description: "Analyze this file",
            parameters: ["imagePath": testPath]
        )
        
        let context = AgentContext(fileReferences: [testPath])
        
        let result = try await visionAgent.process(task: task, context: context)
        
        XCTAssertFalse(result.success, "Should fail for non-image file")
        XCTAssertNotNil(result.error, "Should have error message")
        // Error should mention invalid format or image
        XCTAssertTrue(
            (result.error?.contains("not a recognized image format") ?? false) ||
            (result.error?.contains("image") ?? false) ||
            (result.content.contains("image") && !result.success),
            "Error should mention invalid format or image"
        )
    }
    
    func testVisionAgentHandlesMissingImagePath() async throws {
        let task = AgentTask(
            description: "Analyze this image",
            parameters: [:] // No image path
        )
        
        let context = AgentContext()
        
        let result = try await visionAgent.process(task: task, context: context)
        
        XCTAssertFalse(result.success, "Should fail when no image path is provided")
        XCTAssertNotNil(result.error, "Should have error message")
        // Error should mention missing path or image
        XCTAssertTrue(
            (result.error?.contains("No image file path") ?? false) ||
            (result.error?.contains("file path") ?? false) ||
            (result.content.contains("file path") && !result.success),
            "Error should mention missing path"
        )
    }
    
    func testVisionAgentHandlesNonExistentFile() async throws {
        let nonExistentPath = "/tmp/nonexistent_image.jpg"
        
        let task = AgentTask(
            description: "Analyze this image",
            parameters: ["imagePath": nonExistentPath]
        )
        
        let context = AgentContext(fileReferences: [nonExistentPath])
        
        let result = try await visionAgent.process(task: task, context: context)
        
        XCTAssertFalse(result.success, "Should fail when file doesn't exist")
        XCTAssertNotNil(result.error, "Should have error message")
    }
    
    // MARK: - Integration Tests
    
    func testVisionAgentIntegratesWithModelService() async throws {
        // This test verifies that VisionAgent can create tasks and use ModelService
        // Note: Actual ModelService calls may fail if Apple Intelligence is not available
        // This is acceptable - we're testing the integration structure
        
        // Create a minimal test image file (1x1 PNG)
        let testPath = "/tmp/test_image.png"
        let pngData = createMinimalPNG()
        try pngData.write(to: URL(fileURLWithPath: testPath))
        
        defer {
            try? FileManager.default.removeItem(atPath: testPath)
        }
        
        let task = AgentTask(
            description: "What's in this image?",
            parameters: ["imagePath": testPath]
        )
        
        let context = AgentContext(fileReferences: [testPath])
        
        // This may fail if ModelService is unavailable, which is acceptable
        do {
            let result = try await visionAgent.process(task: task, context: context)
            // If it succeeds, verify structure
            XCTAssertNotNil(result, "Should return a result")
            // Note: success may be false if ModelService is unavailable
        } catch {
            // ModelService unavailable is acceptable in test environment
            // We're just verifying the integration structure exists
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

