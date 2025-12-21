//
//  AgentCapability.swift
//  FoundationChatCore
//
//  Enum defining agent capabilities
//

import Foundation

/// Capabilities that agents can have
@available(macOS 26.0, iOS 26.0, *)
public enum AgentCapability: String, Codable, Sendable, Hashable {
    /// Can read and process files
    case fileReading
    
    /// Can perform web searches
    case webSearch
    
    /// Can analyze code files
    case codeAnalysis
    
    /// Can perform data analysis and calculations
    case dataAnalysis
    
    /// General reasoning and task coordination
    case generalReasoning
    
    /// Can analyze images using vision models
    case imageAnalysis
}





