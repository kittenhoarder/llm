//
//  FileManagerService.swift
//  FoundationChatCore
//
//  Service for managing file operations in the app sandbox
//

import Foundation
import UniformTypeIdentifiers

/// Service for managing file operations in the app sandbox
@available(macOS 26.0, iOS 26.0, *)
public actor FileManagerService {
    /// Shared singleton instance
    public static let shared = FileManagerService()
    
    /// File manager instance
    private let fileManager: FileManager
    
    /// Base directory for file storage
    private let baseDirectory: URL
    
    /// Initialize the file manager service
    public init() {
        self.fileManager = FileManager.default
        
        // Get Application Support directory
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        // Create FoundationChat/Files subdirectory
        self.baseDirectory = appSupport.appendingPathComponent("FoundationChat", isDirectory: true)
            .appendingPathComponent("Files", isDirectory: true)
        
        // Create base directory if it doesn't exist
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    
    /// Get the sandbox directory for file storage
    /// - Returns: Base directory URL
    public func getSandboxDirectory() -> URL {
        return baseDirectory
    }
    
    /// Copy a file to the sandbox
    /// - Parameters:
    ///   - fileURL: Source file URL
    ///   - conversationId: Conversation ID to organize files
    /// - Returns: FileAttachment with sandbox path
    /// - Throws: Error if copy fails
    public func copyToSandbox(fileURL: URL, conversationId: UUID) async throws -> FileAttachment {
        // Get file attributes
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Get original filename
        let originalName = fileURL.lastPathComponent
        
        // Get MIME type if available
        let mimeType = getMimeType(for: fileURL)
        
        // Create conversation directory
        let conversationDir = baseDirectory.appendingPathComponent(conversationId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: conversationDir, withIntermediateDirectories: true)
        
        // Generate unique file ID
        let fileId = UUID()
        
        // Create file directory
        let fileDir = conversationDir.appendingPathComponent(fileId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: fileDir, withIntermediateDirectories: true)
        
        // Destination file path
        let destinationURL = fileDir.appendingPathComponent(originalName)
        
        // Copy file
        try fileManager.copyItem(at: fileURL, to: destinationURL)
        
        // Create attachment
        let attachment = FileAttachment(
            id: fileId,
            originalName: originalName,
            sandboxPath: destinationURL.path,
            fileSize: fileSize,
            mimeType: mimeType
        )
        
        // Trigger RAG indexing in background (don't block file copy if indexing fails)
        Task {
            do {
                let ragService = RAGService.shared
                try await ragService.indexFile(attachment: attachment, conversationId: conversationId)
                print("✅ RAGService: Successfully indexed file \(originalName)")
            } catch {
                // Log error but don't fail file copy
                print("⚠️ RAGService: Failed to index file \(originalName): \(error.localizedDescription)")
            }
        }
        
        // Return attachment
        return attachment
    }
    
    /// Delete a single file from sandbox
    /// - Parameter attachment: File attachment to delete
    /// - Throws: Error if deletion fails
    public func deleteFile(attachment: FileAttachment) async throws {
        let fileURL = URL(fileURLWithPath: attachment.sandboxPath)
        
        // Delete the file
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        
        // Try to delete parent directory if empty
        let parentDir = fileURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: parentDir)
    }
    
    /// Delete all files for a conversation
    /// - Parameter conversationId: Conversation ID
    /// - Throws: Error if deletion fails
    public func deleteFilesForConversation(conversationId: UUID) async throws {
        let conversationDir = baseDirectory.appendingPathComponent(conversationId.uuidString, isDirectory: true)
        
        // Check if directory exists
        guard fileManager.fileExists(atPath: conversationDir.path) else {
            return // Nothing to delete
        }
        
        // Delete RAG indexes for this conversation
        do {
            let ragService = RAGService.shared
            try await ragService.deleteConversationIndexes(conversationId: conversationId)
        } catch {
            // Log error but continue with file deletion
            print("⚠️ FileManagerService: Failed to delete RAG indexes for conversation \(conversationId): \(error.localizedDescription)")
        }
        
        // Delete entire conversation directory
        try fileManager.removeItem(at: conversationDir)
    }
    
    /// Read file data from sandbox
    /// - Parameter attachment: File attachment to read
    /// - Returns: File data
    /// - Throws: Error if read fails
    public func readFile(attachment: FileAttachment) async throws -> Data {
        let fileURL = URL(fileURLWithPath: attachment.sandboxPath)
        return try Data(contentsOf: fileURL)
    }
    
    /// Get MIME type for a file URL
    /// - Parameter url: File URL
    /// - Returns: MIME type string if available
    private func getMimeType(for url: URL) -> String? {
        if let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey]),
           let typeIdentifier = resourceValues.typeIdentifier,
           let mimeType = UTType(typeIdentifier)?.preferredMIMEType {
            return mimeType
        }
        
        // Fallback: use file extension
        let pathExtension = url.pathExtension
        if !pathExtension.isEmpty,
           let type = UTType(filenameExtension: pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        
        return nil
    }
}

