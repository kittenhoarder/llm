//
//  AppConstants.swift
//  FoundationChatCore
//
//  Centralized constants for the application
//

import Foundation

/// Agent name constants used throughout the application
@available(macOS 26.0, iOS 26.0, *)
public enum AgentName {
    public static let fileReader = "File Reader"
    public static let webSearch = "Web Search"
    public static let codeAnalysis = "Code Analysis"
    public static let dataAnalysis = "Data Analysis"
    public static let visionAgent = "Vision Agent"
    public static let coordinator = "Coordinator"
}

/// Stable agent IDs for persistence across restarts
@available(macOS 26.0, iOS 26.0, *)
public enum AgentId {
    public static let fileReader = UUID(uuidString: "0D4A1C6B-2D7E-4C6A-9C2A-7D9D0B8E1C10")!
    public static let webSearch = UUID(uuidString: "A25C8B32-9F4E-4B5D-9F7E-6A7C2E1B3D48")!
    public static let codeAnalysis = UUID(uuidString: "6B7F2E1D-2C3A-4C1F-9E4B-5A6C7D8E9F10")!
    public static let dataAnalysis = UUID(uuidString: "9C0D1E2F-3A4B-5C6D-7E8F-9012A3B4C5D6")!
    public static let visionAgent = UUID(uuidString: "1A2B3C4D-5E6F-7081-92A3-B4C5D6E7F809")!
    public static let coordinator = UUID(uuidString: "F1E2D3C4-B5A6-7988-97A6-5B4C3D2E1F0A")!
}

/// Application-wide constants
@available(macOS 26.0, iOS 26.0, *)
public enum AppConstants {
    // Message history
    public static let recentMessagesCount = 10
    public static let optimizedMessagesCount = 10
    
    // File handling
    public static let maxFileSizeBytes: Int64 = 10 * 1024 * 1024 // 10MB
    
    // Token management
    public static let toolResultTruncationLength = 200
    public static let tokenReserveOverhead = 50
    public static let minimumTokensForSummary = 100
    
    // SVDB context optimization defaults
    public static let defaultSVDBContextTopK = 10
    public static let defaultSVDBContextRecentMessages = 3
    
    // Text processing
    public static let minimumSubtaskDescriptionLength = 10
}

/// UserDefaults key constants
@available(macOS 26.0, iOS 26.0, *)
public enum UserDefaultsKey {
    public static let fontSizeAdjustment = "fontSizeAdjustment"
    public static let preferredColorScheme = "preferredColorScheme"
    public static let useContextualConversations = "useContextualConversations"
    public static let serpapiApiKey = "serpapiApiKey"
    public static let enabledAgentNames = "enabledAgentNames"
    public static let ragChunkSize = "ragChunkSize"
    public static let ragTopK = "ragTopK"
    public static let enabledAgentIds = "enabledAgentIds"
    public static let useCoordinator = "useCoordinator"
    public static let smartDelegation = "smartDelegation"
    public static let useRAG = "useRAG"
    public static let useSVDBForContextOptimization = "useSVDBForContextOptimization"
    public static let svdbContextTopK = "svdbContextTopK"
    public static let svdbContextRecentMessages = "svdbContextRecentMessages"
    public static let leannRootPath = "leannRootPath"
}
