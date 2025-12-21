//
//  FileManagerServiceTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for FileManagerService
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class FileManagerServiceTests: XCTestCase {
    var fileManagerService: FileManagerService!
    var conversationId: UUID!
    var testFileURL: URL!
    var testFilePath: String!
    
    override func setUp() async throws {
        try await super.setUp()
        fileManagerService = FileManagerService.shared
        conversationId = UUID()
        
        // Create a test file
        testFilePath = "/tmp/test_file_manager.txt"
        let testContent = "This is a test file for FileManagerService"
        try testContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
        testFileURL = URL(fileURLWithPath: testFilePath)
    }
    
    override func tearDown() async throws {
        // Cleanup test file
        try? FileManager.default.removeItem(atPath: testFilePath)
        
        // Cleanup sandbox files
        try? await fileManagerService.deleteFilesForConversation(conversationId: conversationId)
        
        try await super.tearDown()
    }
    
    // MARK: - File Copying Tests
    
    func testFileManagerServiceCopiesFileToSandbox() async throws {
        let attachment = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        XCTAssertNotNil(attachment, "Should return file attachment")
        XCTAssertEqual(attachment.originalName, testFileURL.lastPathComponent, "Should preserve original filename")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.sandboxPath), "File should exist in sandbox")
        XCTAssertEqual(attachment.fileSize, Int64(testContent.utf8.count), "Should preserve file size")
    }
    
    func testFileManagerServiceOrganizesByConversation() async throws {
        let attachment1 = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        let conversationId2 = UUID()
        let attachment2 = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId2
        )
        
        // Files should be in different conversation directories
        XCTAssertNotEqual(attachment1.sandboxPath, attachment2.sandboxPath, "Files should be in different directories")
        XCTAssertTrue(attachment1.sandboxPath.contains(conversationId.uuidString), "First file should be in conversation 1 directory")
        XCTAssertTrue(attachment2.sandboxPath.contains(conversationId2.uuidString), "Second file should be in conversation 2 directory")
        
        // Cleanup
        try? await fileManagerService.deleteFilesForConversation(conversationId: conversationId2)
    }
    
    func testFileManagerServiceGeneratesUniqueFileIds() async throws {
        let attachment1 = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        let attachment2 = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        // Each file should have a unique ID
        XCTAssertNotEqual(attachment1.id, attachment2.id, "Each file should have unique ID")
    }
    
    // MARK: - File Reading Tests
    
    func testFileManagerServiceReadsFile() async throws {
        let attachment = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        let data = try await fileManagerService.readFile(attachment: attachment)
        let content = String(data: data, encoding: .utf8)
        
        XCTAssertNotNil(content, "Should read file content")
        XCTAssertEqual(content, testContent, "Should read correct content")
    }
    
    func testFileManagerServiceHandlesMissingFiles() async throws {
        let nonExistentAttachment = FileAttachment(
            originalName: "nonexistent.txt",
            sandboxPath: "/tmp/nonexistent_file.txt",
            fileSize: 0,
            mimeType: "text/plain"
        )
        
        do {
            _ = try await fileManagerService.readFile(attachment: nonExistentAttachment)
            XCTFail("Should throw error for missing file")
        } catch {
            // Expected to throw error (standard Cocoa error for file not found)
            XCTAssertNotNil(error, "Should throw error for missing file")
        }
    }
    
    // MARK: - File Deletion Tests
    
    func testFileManagerServiceDeletesFile() async throws {
        let attachment = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.sandboxPath), "File should exist before deletion")
        
        // Delete file
        try await fileManagerService.deleteFile(attachment: attachment)
        
        // Verify file is deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.sandboxPath), "File should not exist after deletion")
    }
    
    func testFileManagerServiceDeletesConversationFiles() async throws {
        // Copy multiple files
        let attachment1 = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        
        // Create second test file
        let testFile2Path = "/tmp/test_file2.txt"
        try "Test content 2".write(toFile: testFile2Path, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(atPath: testFile2Path)
        }
        
        let attachment2 = try await fileManagerService.copyToSandbox(
            fileURL: URL(fileURLWithPath: testFile2Path),
            conversationId: conversationId
        )
        
        // Verify files exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment1.sandboxPath), "File 1 should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment2.sandboxPath), "File 2 should exist")
        
        // Delete all conversation files
        try await fileManagerService.deleteFilesForConversation(conversationId: conversationId)
        
        // Verify files are deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment1.sandboxPath), "File 1 should be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment2.sandboxPath), "File 2 should be deleted")
    }
    
    func testFileManagerServiceHandlesNonExistentConversation() async throws {
        let nonExistentConversationId = UUID()
        
        // Should not throw error for non-existent conversation
        try await fileManagerService.deleteFilesForConversation(conversationId: nonExistentConversationId)
        // Should complete without error
    }
    
    // MARK: - MIME Type Tests
    
    func testFileManagerServiceDetectsMimeTypes() async throws {
        // Test text file
        let textAttachment = try await fileManagerService.copyToSandbox(
            fileURL: testFileURL,
            conversationId: conversationId
        )
        XCTAssertNotNil(textAttachment.mimeType, "Should detect MIME type for text file")
        
        // Test image file (if we can create one)
        let imagePath = "/tmp/test_image.png"
        let pngData = createMinimalPNG()
        try pngData.write(to: URL(fileURLWithPath: imagePath))
        defer {
            try? FileManager.default.removeItem(atPath: imagePath)
        }
        
        let imageAttachment = try await fileManagerService.copyToSandbox(
            fileURL: URL(fileURLWithPath: imagePath),
            conversationId: conversationId
        )
        XCTAssertNotNil(imageAttachment.mimeType, "Should detect MIME type for image file")
        XCTAssertTrue(imageAttachment.mimeType?.contains("image") ?? false, "MIME type should indicate image")
    }
    
    // MARK: - Helper Methods
    
    private var testContent: String {
        return "This is a test file for FileManagerService"
    }
    
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

