//
//  FileAttachment.swift
//  FoundationChatCore
//
//  Model representing a file attachment in a message
//

import Foundation

/// Represents a file attachment in a message
@available(macOS 26.0, iOS 26.0, *)
public struct FileAttachment: Identifiable, Codable, Sendable {
    /// Unique identifier for this attachment
    public let id: UUID
    
    /// Original filename from user's file system
    public let originalName: String
    
    /// Path to file in app's sandbox
    public let sandboxPath: String
    
    /// File size in bytes
    public let fileSize: Int64
    
    /// MIME type if available
    public let mimeType: String?
    
    /// When the file was attached
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        originalName: String,
        sandboxPath: String,
        fileSize: Int64,
        mimeType: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalName = originalName
        self.sandboxPath = sandboxPath
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.createdAt = createdAt
    }
}

