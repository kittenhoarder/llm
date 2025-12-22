//
//  EmbeddingService.swift
//  FoundationChatCore
//
//  Service for generating text embeddings using NaturalLanguage framework
//

import Foundation
import NaturalLanguage

/// Service for generating text embeddings using NaturalLanguage framework
@available(macOS 26.0, iOS 26.0, *)
public actor EmbeddingService {
    /// Shared singleton instance
    public static let shared = EmbeddingService()
    
    /// NaturalLanguage embedding model
    private var embedding: NLEmbedding?
    
    /// Cache for embeddings to avoid recomputation
    private var embeddingCache: [String: [Float]] = [:]
    
    /// Maximum cache size
    private let maxCacheSize = 1000
    
    /// Initialize the embedding service
    private init() {
        // Try to load the multilingual embedding model
        // This provides better support for various languages
        self.embedding = NLEmbedding.wordEmbedding(for: .english)
        
        // If English model fails, try multilingual
        if self.embedding == nil {
            // Note: NLEmbedding.sentenceEmbedding is available on newer iOS/macOS versions
            // For now, we'll use word embeddings which are more widely available
            print("⚠️ EmbeddingService: Could not load English embedding model")
        }
    }
    
    /// Generate embedding for a single text
    /// - Parameter text: The text to embed
    /// - Returns: Vector embedding as Float array
    /// - Throws: EmbeddingError if embedding generation fails
    public func embed(text: String) async throws -> [Float] {
        // Check cache first
        if let cached = embeddingCache[text] {
            return cached
        }
        
        guard let embedding = embedding else {
            throw EmbeddingError.modelNotAvailable
        }
        
        // For word embeddings, we need to process the text differently
        // NLEmbedding.wordEmbedding works on individual words, not sentences
        // We'll use a sentence-level approach by averaging word embeddings
        
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "EmbeddingService.swift:embed",
            message: "Processing text for embedding",
            hypothesisId: "A,B,C",
            data: [
                "textLength": text.count,
                "textPreview": String(text.prefix(100)),
                "wordCount": words.count,
                "wordsPreview": Array(words.prefix(10))
            ]
        )
        // #endregion
        
        guard !words.isEmpty else {
            // #region debug log
            await DebugLogger.shared.log(
                location: "EmbeddingService.swift:embed",
                message: "Empty words array, returning zero vector",
                hypothesisId: "B",
                data: [
                    "textLength": text.count,
                    "textPreview": String(text.prefix(100))
                ]
            )
            // #endregion
            // Return zero vector for empty text
            return Array(repeating: 0.0, count: 300) // Default dimension
        }
        
        var embeddingVectors: [[Double]] = []
        var wordsWithEmbeddings: [String] = []
        var wordsWithoutEmbeddings: [String] = []
        
        for word in words {
            // Get embedding for each word
            if let vector = embedding.vector(for: word.lowercased()) {
                embeddingVectors.append(vector)
                wordsWithEmbeddings.append(word)
            } else {
                wordsWithoutEmbeddings.append(word)
            }
        }
        
        // #region debug log
        await DebugLogger.shared.log(
            location: "EmbeddingService.swift:embed",
            message: "Word embedding results",
            hypothesisId: "A,B,C",
            data: [
                "totalWords": words.count,
                "wordsWithEmbeddings": wordsWithEmbeddings.count,
                "wordsWithoutEmbeddings": wordsWithoutEmbeddings.count,
                "wordsWithoutEmbeddingsPreview": Array(wordsWithoutEmbeddings.prefix(20)),
                "embeddingVectorsCount": embeddingVectors.count
            ]
        )
        // #endregion
        
        guard !embeddingVectors.isEmpty else {
            // #region debug log
            await DebugLogger.shared.log(
                location: "EmbeddingService.swift:embed",
                message: "No embeddings generated - throwing error",
                hypothesisId: "A,B,C",
                data: [
                    "textLength": text.count,
                    "textPreview": String(text.prefix(200)),
                    "wordCount": words.count,
                    "wordsWithoutEmbeddings": Array(wordsWithoutEmbeddings.prefix(50))
                ]
            )
            // #endregion
            throw EmbeddingError.embeddingGenerationFailed("No embeddings generated for text")
        }
        
        // Average the word embeddings to get a sentence-level embedding
        let dimension = embeddingVectors[0].count
        var averagedVector = [Double](repeating: 0.0, count: dimension)
        
        for vector in embeddingVectors {
            for (index, value) in vector.enumerated() {
                averagedVector[index] += value
            }
        }
        
        // Divide by count to get average
        let count = Double(embeddingVectors.count)
        for index in 0..<averagedVector.count {
            averagedVector[index] /= count
        }
        
        // Convert to Float array
        let floatVector = averagedVector.map { Float($0) }
        
        // Cache the result
        cacheEmbedding(text: text, embedding: floatVector)
        
        return floatVector
    }
    
    /// Generate embeddings for multiple texts in batch
    /// - Parameter texts: Array of texts to embed
    /// - Returns: Array of embeddings
    /// - Throws: EmbeddingError if embedding generation fails
    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        
        for text in texts {
            let embedding = try await embed(text: text)
            results.append(embedding)
        }
        
        return results
    }
    
    /// Cache an embedding result
    /// - Parameters:
    ///   - text: The original text
    ///   - embedding: The generated embedding
    private func cacheEmbedding(text: String, embedding: [Float]) {
        // If cache is full, remove oldest entries (simple FIFO)
        if embeddingCache.count >= maxCacheSize {
            // Remove first 10% of cache
            let keysToRemove = Array(embeddingCache.keys.prefix(maxCacheSize / 10))
            for key in keysToRemove {
                embeddingCache.removeValue(forKey: key)
            }
        }
        
        embeddingCache[text] = embedding
    }
    
    /// Clear the embedding cache
    public func clearCache() {
        embeddingCache.removeAll()
    }
    
    /// Get the dimension of embeddings
    /// - Returns: Embedding dimension (default: 300 for word embeddings)
    public func embeddingDimension() -> Int {
        // NaturalLanguage word embeddings typically have 300 dimensions
        // This may vary by model, but 300 is a safe default
        return 300
    }
}

/// Errors for embedding operations
@available(macOS 26.0, iOS 26.0, *)
public enum EmbeddingError: Error, LocalizedError, Sendable {
    case modelNotAvailable
    case embeddingGenerationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "NaturalLanguage embedding model is not available"
        case .embeddingGenerationFailed(let reason):
            return "Failed to generate embedding: \(reason)"
        }
    }
}

