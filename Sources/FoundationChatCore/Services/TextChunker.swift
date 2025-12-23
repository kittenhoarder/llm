//
//  TextChunker.swift
//  FoundationChatCore
//
//  Service for intelligent text chunking with overlap
//

import Foundation

/// Service for splitting text into chunks with intelligent boundary detection
@available(macOS 26.0, iOS 26.0, *)
public struct TextChunker {
    /// Default chunk size in characters
    public static let defaultChunkSize: Int = 1000
    
    /// Default overlap in characters (20% of chunk size)
    public static let defaultOverlap: Int = 200
    
    /// Chunk text into smaller pieces with overlap
    /// - Parameters:
    ///   - text: The text to chunk
    ///   - chunkSize: Maximum characters per chunk (default: 1000)
    ///   - overlap: Number of characters to overlap between chunks (default: 200)
    /// - Returns: Array of text chunks
    public static func chunk(
        text: String,
        chunkSize: Int = defaultChunkSize,
        overlap: Int = defaultOverlap
    ) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > chunkSize else { return [text] }
        
        var chunks: [String] = []
        var startIndex = text.startIndex
        var chunkIndex = 0
        
        while startIndex < text.endIndex {
            // Calculate end position for this chunk
            let endPosition = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            
            // Try to find a good breaking point (sentence or paragraph boundary)
            let chunkEnd = findBestBreakPoint(
                text: text,
                start: startIndex,
                preferredEnd: endPosition,
                maxEnd: min(text.index(endPosition, offsetBy: overlap, limitedBy: text.endIndex) ?? text.endIndex, text.endIndex)
            )
            
            // Extract chunk
            let chunk = String(text[startIndex..<chunkEnd])
            chunks.append(chunk)
            
            // Move start position for next chunk (with overlap)
            if chunkEnd < text.endIndex {
                let overlapStart = text.index(chunkEnd, offsetBy: -overlap, limitedBy: startIndex) ?? startIndex
                startIndex = max(overlapStart, text.index(startIndex, offsetBy: chunkSize - overlap, limitedBy: text.endIndex) ?? text.endIndex)
            } else {
                break
            }
            
            chunkIndex += 1
        }
        
        return chunks
    }
    
    /// Find the best break point for chunking (prefer sentence/paragraph boundaries)
    /// - Parameters:
    ///   - text: The full text
    ///   - start: Start index of current chunk
    ///   - preferredEnd: Preferred end position (chunk size)
    ///   - maxEnd: Maximum end position (chunk size + overlap)
    /// - Returns: Best break point index
    private static func findBestBreakPoint(
        text: String,
        start: String.Index,
        preferredEnd: String.Index,
        maxEnd: String.Index
    ) -> String.Index {
        // If we're at the end, return it
        guard preferredEnd < text.endIndex else {
            return text.endIndex
        }
        
        // Look for paragraph break (double newline) first
        if let paragraphBreak = findLastOccurrence(
            of: "\n\n",
            in: text,
            range: start..<maxEnd
        ) {
            return text.index(paragraphBreak, offsetBy: 2)
        }
        
        // Look for sentence endings (., !, ?) followed by space or newline
        let sentenceEndings = [". ", "! ", "? ", ".\n", "!\n", "?\n"]
        for ending in sentenceEndings {
            if let sentenceBreak = findLastOccurrence(
                of: ending,
                in: text,
                range: start..<maxEnd
            ) {
                return text.index(sentenceBreak, offsetBy: ending.count)
            }
        }
        
        // Look for single newline
        if let newlineBreak = findLastOccurrence(
            of: "\n",
            in: text,
            range: start..<maxEnd
        ) {
            return text.index(newlineBreak, offsetBy: 1)
        }
        
        // Look for space
        if let spaceBreak = findLastOccurrence(
            of: " ",
            in: text,
            range: start..<maxEnd
        ) {
            return text.index(spaceBreak, offsetBy: 1)
        }
        
        // Fallback: use preferred end or max end
        return min(preferredEnd, maxEnd)
    }
    
    /// Find the last occurrence of a substring in a range
    /// - Parameters:
    ///   - substring: Substring to find
    ///   - text: Text to search in
    ///   - range: Range to search within
    /// - Returns: Index of last occurrence, or nil if not found
    private static func findLastOccurrence(
        of substring: String,
        in text: String,
        range: Range<String.Index>
    ) -> String.Index? {
        var searchRange = range
        var lastFound: String.Index?
        
        while searchRange.lowerBound < searchRange.upperBound {
            if let found = text.range(of: substring, range: searchRange)?.lowerBound {
                lastFound = found
                // Continue searching after this occurrence
                searchRange = text.index(found, offsetBy: substring.count)..<searchRange.upperBound
            } else {
                break
            }
        }
        
        return lastFound
    }
    
    /// Chunk code/text with special handling for code blocks
    /// - Parameters:
    ///   - text: The text to chunk
    ///   - chunkSize: Maximum characters per chunk
    ///   - overlap: Overlap between chunks
    ///   - isCode: Whether this is code (preserves structure better)
    /// - Returns: Array of text chunks
    public static func chunkCode(
        text: String,
        chunkSize: Int = defaultChunkSize,
        overlap: Int = defaultOverlap,
        isCode: Bool = false
    ) -> [String] {
        if isCode {
            // For code, prefer breaking at function/class boundaries
            // Look for common patterns: function definitions, class definitions, etc.
            let codePatterns = [
                "\nfunc ", "\nclass ", "\nstruct ", "\nenum ", "\nextension ",
                "\nprivate ", "\npublic ", "\ninternal ", "\nfileprivate ",
                "\n    func ", "\n    class ", "\n    struct "
            ]
            
            var chunks: [String] = []
            var startIndex = text.startIndex
            var chunkIndex = 0
            
            while startIndex < text.endIndex {
                let endPosition = text.index(startIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                let maxEnd = min(text.index(endPosition, offsetBy: overlap, limitedBy: text.endIndex) ?? text.endIndex, text.endIndex)
                
                // Look for code structure boundaries
                var bestBreak: String.Index? = nil
                for pattern in codePatterns {
                    if let breakPoint = findLastOccurrence(
                        of: pattern,
                        in: text,
                        range: startIndex..<maxEnd
                    ) {
                        if bestBreak == nil || breakPoint > (bestBreak ?? text.startIndex) {
                            bestBreak = breakPoint
                        }
                    }
                }
                
                let chunkEnd = bestBreak ?? min(endPosition, maxEnd)
                let chunk = String(text[startIndex..<chunkEnd])
                chunks.append(chunk)
                
                if chunkEnd < text.endIndex {
                    let overlapStart = text.index(chunkEnd, offsetBy: -overlap, limitedBy: startIndex) ?? startIndex
                    startIndex = max(overlapStart, text.index(startIndex, offsetBy: chunkSize - overlap, limitedBy: text.endIndex) ?? text.endIndex)
                } else {
                    break
                }
                
                chunkIndex += 1
            }
            
            return chunks
        } else {
            // Use regular chunking for non-code
            return chunk(text: text, chunkSize: chunkSize, overlap: overlap)
        }
    }
}


