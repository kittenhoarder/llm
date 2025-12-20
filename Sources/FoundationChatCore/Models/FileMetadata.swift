//
//  FileMetadata.swift
//  FoundationChatCore
//
//  Model representing metadata for ingested files
//

import Foundation

/// Supported file types for ingestion
@available(macOS 26.0, iOS 26.0, *)
public enum FileType: String, Codable, Sendable {
    case pdf
    case image
    case text
    case markdown
    case unknown
}

/// Metadata for an ingested file
@available(macOS 26.0, iOS 26.0, *)
public struct FileMetadata: Identifiable, Codable, Sendable {
    /// Unique identifier for the file
    public let id: UUID
    
    /// Original filename
    public let filename: String
    
    /// Path to the file in app sandbox
    public let filepath: String
    
    /// Type of file
    public let fileType: FileType
    
    /// When the file was indexed
    public let indexedAt: Date
    
    /// Number of embedding chunks created from this file
    public var embeddingCount: Int
    
    /// Whether this file has been indexed in the RAG system
    public var isIndexed: Bool
    
    /// File size in bytes
    public let fileSize: Int64
    
    public init(
        id: UUID = UUID(),
        filename: String,
        filepath: String,
        fileType: FileType,
        indexedAt: Date = Date(),
        embeddingCount: Int = 0,
        isIndexed: Bool = false,
        fileSize: Int64
    ) {
        self.id = id
        self.filename = filename
        self.filepath = filepath
        self.fileType = fileType
        self.indexedAt = indexedAt
        self.embeddingCount = embeddingCount
        self.isIndexed = isIndexed
        self.fileSize = fileSize
    }
    
    /// Determine file type from filename extension
    public static func fileType(from filename: String) -> FileType {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            return .pdf
        case "jpg", "jpeg", "png", "heic", "heif":
            return .image
        case "txt", "text":
            return .text
        case "md", "markdown":
            return .markdown
        default:
            return .unknown
        }
    }
}


