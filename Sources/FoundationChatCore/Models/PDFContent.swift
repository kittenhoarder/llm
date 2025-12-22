//
//  PDFContent.swift
//  FoundationChatCore
//
//  Model representing extracted PDF content and metadata
//

import Foundation

/// Metadata extracted from a PDF document
@available(macOS 26.0, iOS 26.0, *)
public struct PDFMetadata: Sendable {
    /// PDF title
    public let title: String?
    
    /// PDF author
    public let author: String?
    
    /// PDF subject
    public let subject: String?
    
    /// Number of pages in the PDF
    public let pageCount: Int
    
    /// Creation date if available
    public let creationDate: Date?
    
    /// Modification date if available
    public let modificationDate: Date?
    
    public init(
        title: String? = nil,
        author: String? = nil,
        subject: String? = nil,
        pageCount: Int = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.title = title
        self.author = author
        self.subject = subject
        self.pageCount = pageCount
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
    
    /// Format metadata as a readable string
    public func formatted() -> String {
        var lines: [String] = []
        
        if let title = title, !title.isEmpty {
            lines.append("Title: \(title)")
        }
        if let author = author, !author.isEmpty {
            lines.append("Author: \(author)")
        }
        if let subject = subject, !subject.isEmpty {
            lines.append("Subject: \(subject)")
        }
        if pageCount > 0 {
            lines.append("Pages: \(pageCount)")
        }
        if let creationDate = creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            lines.append("Created: \(formatter.string(from: creationDate))")
        }
        
        return lines.joined(separator: "\n")
    }
}

/// Content extracted from a PDF document
@available(macOS 26.0, iOS 26.0, *)
public struct PDFContent: Sendable {
    /// Full extracted text from all pages
    public let text: String
    
    /// PDF metadata
    public let metadata: PDFMetadata
    
    public init(text: String, metadata: PDFMetadata) {
        self.text = text
        self.metadata = metadata
    }
    
    /// Format content with metadata header
    public func formatted() -> String {
        let metadataStr = metadata.formatted()
        if metadataStr.isEmpty {
            return text
        }
        return "\(metadataStr)\n\n\(text)"
    }
}

