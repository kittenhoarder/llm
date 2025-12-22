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
    public static let ragChunkSize = "ragChunkSize"
    public static let ragTopK = "ragTopK"
    public static let enabledAgentIds = "enabledAgentIds"
    public static let useCoordinator = "useCoordinator"
    public static let useSVDBForContextOptimization = "useSVDBForContextOptimization"
    public static let svdbContextTopK = "svdbContextTopK"
    public static let svdbContextRecentMessages = "svdbContextRecentMessages"
}

