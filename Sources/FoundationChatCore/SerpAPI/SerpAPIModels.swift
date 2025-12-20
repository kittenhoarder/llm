//
//  SerpAPIModels.swift
//  FoundationChatCore
//
//  Models for SerpAPI responses
//

import Foundation

/// Main response structure from SerpAPI
public struct SerpAPIResponse: Codable, Sendable {
    /// Organic search results
    public let organicResults: [OrganicResult]?
    
    /// Answer box (direct answers)
    public let answerBox: AnswerBox?
    
    /// Knowledge graph data
    public let knowledgeGraph: KnowledgeGraph?
    
    /// Related questions
    public let relatedQuestions: [RelatedQuestion]?
    
    /// Search metadata
    public let searchMetadata: SearchMetadata?
    
    enum CodingKeys: String, CodingKey {
        case organicResults = "organic_results"
        case answerBox = "answer_box"
        case knowledgeGraph = "knowledge_graph"
        case relatedQuestions = "related_questions"
        case searchMetadata = "search_metadata"
    }
    
    /// Check if response has any useful content
    public var hasContent: Bool {
        return (organicResults != nil && !organicResults!.isEmpty)
            || answerBox != nil
            || knowledgeGraph != nil
            || (relatedQuestions != nil && !relatedQuestions!.isEmpty)
    }
}

/// Organic search result
public struct OrganicResult: Codable, Sendable {
    /// Position in search results
    public let position: Int?
    
    /// Title of the result
    public let title: String?
    
    /// Link URL
    public let link: String?
    
    /// Displayed link
    public let displayedLink: String?
    
    /// Snippet/description
    public let snippet: String?
    
    /// Date of the result
    public let date: String?
    
    /// Source of the result
    public let source: String?
    
    enum CodingKeys: String, CodingKey {
        case position
        case title
        case link
        case displayedLink = "displayed_link"
        case snippet
        case date
        case source
    }
}

/// Answer box (direct answer)
public struct AnswerBox: Codable, Sendable {
    /// Answer text
    public let answer: String?
    
    /// Title
    public let title: String?
    
    /// Link
    public let link: String?
    
    /// Snippet
    public let snippet: String?
    
    enum CodingKeys: String, CodingKey {
        case answer
        case title
        case link
        case snippet
    }
}

/// Knowledge graph data
public struct KnowledgeGraph: Codable, Sendable {
    /// Title
    public let title: String?
    
    /// Type
    public let type: String?
    
    /// Description
    public let description: String?
    
    /// Source
    public let source: Source?
    
    enum CodingKeys: String, CodingKey {
        case title
        case type
        case description
        case source
    }
}

/// Source information
public struct Source: Codable, Sendable {
    /// Name
    public let name: String?
    
    /// Link
    public let link: String?
}

/// Related question
public struct RelatedQuestion: Codable, Sendable {
    /// Question text
    public let question: String?
    
    /// Snippet/answer
    public let snippet: String?
    
    /// Title
    public let title: String?
    
    /// Link
    public let link: String?
    
    enum CodingKeys: String, CodingKey {
        case question
        case snippet
        case title
        case link
    }
}

/// Search metadata
public struct SearchMetadata: Codable, Sendable {
    /// Request ID
    public let requestId: String?
    
    /// Status
    public let status: String?
    
    enum CodingKeys: String, CodingKey {
        case requestId = "id"
        case status
    }
}

