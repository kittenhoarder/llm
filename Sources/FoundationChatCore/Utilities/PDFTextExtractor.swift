//
//  PDFTextExtractor.swift
//  FoundationChatCore
//
//  Utility for extracting text and metadata from PDF documents using PDFKit
//

import Foundation
import PDFKit

/// Utility for extracting text and metadata from PDF documents
@available(macOS 26.0, iOS 26.0, *)
public struct PDFTextExtractor {
    /// Extract text and metadata from a PDF file
    /// - Parameter url: URL to the PDF file
    /// - Returns: PDFContent with extracted text and metadata
    /// - Throws: Error if extraction fails
    public static func extractText(from url: URL) async throws -> PDFContent {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PDFExtractionError.fileNotFound(url.path)
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFExtractionError.invalidPDF("Could not create PDFDocument from file")
        }
        
        return try extractContent(from: pdfDocument)
    }
    
    /// Extract text and metadata from PDF data
    /// - Parameter data: PDF file data
    /// - Returns: PDFContent with extracted text and metadata
    /// - Throws: Error if extraction fails
    public static func extractText(from data: Data) async throws -> PDFContent {
        guard let pdfDocument = PDFDocument(data: data) else {
            throw PDFExtractionError.invalidPDF("Could not create PDFDocument from data")
        }
        
        return try extractContent(from: pdfDocument)
    }
    
    /// Extract content from a PDFDocument
    /// - Parameter document: The PDFDocument to extract from
    /// - Returns: PDFContent with extracted text and metadata
    /// - Throws: Error if extraction fails
    private static func extractContent(from document: PDFDocument) throws -> PDFContent {
        // Check if document is locked (password-protected)
        if document.isLocked {
            throw PDFExtractionError.passwordProtected("PDF is password-protected")
        }
        
        let pageCount = document.pageCount
        
        // Extract text from all pages
        var extractedText = ""
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            
            if let pageText = page.string, !pageText.isEmpty {
                if pageIndex > 0 {
                    extractedText += "\n\n"
                }
                extractedText += "--- Page \(pageIndex + 1) ---\n"
                extractedText += pageText
            }
        }
        
        // Extract metadata
        let attributes = document.documentAttributes ?? [:]
        let title = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String
        let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String
        let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
        let modificationDate = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date
        
        let metadata = PDFMetadata(
            title: title,
            author: author,
            subject: subject,
            pageCount: pageCount,
            creationDate: creationDate,
            modificationDate: modificationDate
        )
        
        return PDFContent(text: extractedText, metadata: metadata)
    }
}

/// Errors that can occur during PDF extraction
@available(macOS 26.0, iOS 26.0, *)
public enum PDFExtractionError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case invalidPDF(String)
    case passwordProtected(String)
    case extractionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "PDF file not found: \(path)"
        case .invalidPDF(let reason):
            return "Invalid PDF: \(reason)"
        case .passwordProtected(let reason):
            return "Password-protected PDF: \(reason)"
        case .extractionFailed(let reason):
            return "PDF extraction failed: \(reason)"
        }
    }
}

