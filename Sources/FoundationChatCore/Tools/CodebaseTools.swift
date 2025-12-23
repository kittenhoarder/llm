//
//  CodebaseTools.swift
//  FoundationChatCore
//

import Foundation
import FoundationModels

// MARK: - Semantic Search Tool

@available(macOS 26.0, iOS 26.0, *)
public struct CodebaseSearchTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "codebase_semantic_search"
    public let description = "Performs a semantic search over the indexed codebase to find relevant code snippets, functions, or concepts. Use this when the user asks conceptual questions like 'How does authentication work?'."
    
    public init() {}
    
    @Generable
    public struct Arguments {
        public let query: String
        public let limit: Int?
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let service = LEANNBridgeService.shared
        // Default to a smaller limit to save context window
        let limit = arguments.limit ?? 3
        let results: [CodeSearchResult]
        do {
            results = try await service.search(query: arguments.query, topK: limit)
        } catch let error as LEANNError {
            switch error {
            case .notIndexed:
                return "Error: No codebase is currently indexed. Please index a codebase in Settings."
            case .missingConfiguration(let reason):
                return "Error: \(reason)"
            default:
                throw error
            }
        }
        
        if results.isEmpty {
            return "No relevant code found for query: '\(arguments.query)'"
        }
        
        var output = "Semantic search results for '\(arguments.query)':\n\n"
        for (index, result) in results.enumerated() {
            output += "### Result \(index + 1): \(result.filePath)\n"
            output += "```\(result.fileExtension.replacingOccurrences(of: ".", with: ""))\n"
            
            // Truncate individual result content if it's too long
            let maxChunkChars = 1500
            let truncatedContent = result.content.count > maxChunkChars 
                ? String(result.content.prefix(maxChunkChars)) + "\n... (truncated)"
                : result.content
            
            output += truncatedContent + "\n"
            output += "```\n\n"
        }
        
        // Final safety check on total output size
        if output.count > 8000 {
            output = String(output.prefix(8000)) + "\n... (Total output truncated to stay within context window)"
        }
        
        return output
    }
}

// MARK: - Grep Search Tool

@available(macOS 26.0, iOS 26.0, *)
public struct CodebaseGrepTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "codebase_grep_search"
    public let description = "Performs an exact text or regex search across the indexed codebase. Use this to find specific function names, variable definitions, or error strings. Example: 'find where LEANNBridgeService is initialized'."
    
    public init() {}
    
    @Generable
    public struct Arguments {
        public let pattern: String
        public let limit: Int?
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let service = LEANNBridgeService.shared
        let limit = arguments.limit ?? 5
        let results: [CodeSearchResult]
        do {
            results = try await service.grepSearch(pattern: arguments.pattern, topK: limit)
        } catch let error as LEANNError {
            switch error {
            case .notIndexed:
                return "Error: No codebase is currently indexed. Please index a codebase in Settings."
            case .missingConfiguration(let reason):
                return "Error: \(reason)"
            default:
                throw error
            }
        }
        
        if results.isEmpty {
            return "No exact matches found for pattern: '\(arguments.pattern)'"
        }
        
        var output = "Exact matches for '\(arguments.pattern)':\n\n"
        for result in results {
            output += "- \(result.filePath): `\(result.content.trimmingCharacters(in: .whitespacesAndNewlines))`\n"
        }
        
        return output
    }
}

// MARK: - Read File Tool

@available(macOS 26.0, iOS 26.0, *)
public struct CodebaseReadFileTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "codebase_read_file"
    public let description = "Reads the full content of a specific file from the indexed codebase. Use this when you have identified a file via search and need to see the full context of a class or function."
    
    public init() {}
    
    @Generable
    public struct Arguments {
        public let filePath: String
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let service = LEANNBridgeService.shared
        guard let rootURL = await service.getIndexedURL() else {
            return "Error: No codebase is currently indexed."
        }
        
        // Start accessing security-scoped resource
        let accessing = rootURL.startAccessingSecurityScopedResource()
        defer { if accessing { rootURL.stopAccessingSecurityScopedResource() } }
        
        let fullPath: URL
        if arguments.filePath.hasPrefix("/") {
            fullPath = URL(fileURLWithPath: arguments.filePath)
        } else {
            fullPath = rootURL.appendingPathComponent(arguments.filePath)
        }
        
        do {
            let content = try String(contentsOf: fullPath, encoding: .utf8)
            let maxChars = 6000
            let finalContent = content.count > maxChars 
                ? String(content.prefix(maxChars)) + "\n... (File truncated due to length. Use more specific search if needed.)"
                : content
            return "Content of \(arguments.filePath):\n\n```\n\(finalContent)\n```"
        } catch {
            return "Error reading file \(arguments.filePath): \(error.localizedDescription)"
        }
    }
}

// MARK: - List Files Tool

@available(macOS 26.0, iOS 26.0, *)
public struct CodebaseListFilesTool: Tool, Sendable {
    public typealias Output = String
    
    public let name = "codebase_list_files"
    public let description = "Lists all files in a specific directory within the indexed codebase. Use this to explore the project structure."
    
    public init() {}
    
    @Generable
    public struct Arguments {
        public let subDirectory: String?
    }
    
    public func call(arguments: Arguments) async throws -> Output {
        let service = LEANNBridgeService.shared
        guard let rootURL = await service.getIndexedURL() else {
            return "Error: No codebase is currently indexed."
        }
        
        // Start accessing security-scoped resource
        let accessing = rootURL.startAccessingSecurityScopedResource()
        defer { if accessing { rootURL.stopAccessingSecurityScopedResource() } }
        
        var targetPath = rootURL
        if let subDir = arguments.subDirectory, !subDir.isEmpty {
            targetPath = targetPath.appendingPathComponent(subDir)
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: targetPath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            
            var output = "Files in \(arguments.subDirectory ?? "root"):\n"
            for item in contents.prefix(100) { // Limit to 100 for brevity
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                output += "- \(item.lastPathComponent)\(isDir ? "/" : "")\n"
            }
            
            if contents.count > 100 {
                output += "\n... and \(contents.count - 100) more files."
            }
            
            return output
        } catch {
            return "Error listing directory '\(arguments.subDirectory ?? "root")': \(error.localizedDescription)"
        }
    }
}
