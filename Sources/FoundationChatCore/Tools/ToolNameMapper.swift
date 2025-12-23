//
//  ToolNameMapper.swift
//  FoundationChatCore
//
//  Maps internal tool names to user-friendly display names
//

import Foundation

/// Maps tool names to user-friendly display names
@available(macOS 26.0, iOS 26.0, *)
public struct ToolNameMapper {
    /// Mapping from internal tool names to friendly names
    private static let nameMap: [String: String] = [
        "duckduckgo_search": "DuckDuckGo Search",
        // Add more mappings as tools are added
    ]
    
    /// Get user-friendly name for a tool
    /// - Parameter toolName: Internal tool name
    /// - Returns: User-friendly name, or the original name if no mapping exists
    public static func friendlyName(for toolName: String) -> String {
        return nameMap[toolName] ?? toolName
    }
    
    /// Get user-friendly names for multiple tools
    /// - Parameter toolNames: Array of internal tool names
    /// - Returns: Array of user-friendly names
    public static func friendlyNames(for toolNames: [String]) -> [String] {
        return toolNames.map { friendlyName(for: $0) }
    }
    
    /// Format tool names as a comma-separated string
    /// - Parameter toolNames: Array of internal tool names
    /// - Returns: Formatted string like "DuckDuckGo Search, File Search"
    public static func formatToolList(_ toolNames: [String]) -> String {
        let friendly = friendlyNames(for: toolNames)
        return friendly.joined(separator: ", ")
    }
}








