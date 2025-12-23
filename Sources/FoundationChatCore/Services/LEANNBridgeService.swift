//
//  LEANNBridgeService.swift
//  FoundationChatCore
//
//  Bridge to LEANN Python vector database for code analysis
//

import Foundation

/// Service for interfacing with LEANN vector database via Python
@available(macOS 26.0, iOS 26.0, *)
public actor LEANNBridgeService {
    /// Shared singleton instance
    public static let shared = LEANNBridgeService()
    
    /// Path to Python venv
    private var pythonPath: URL?
    
    /// Path to LEANN bridge script
    private var bridgeScriptPath: URL?
    
    /// Path to LEANN root directory
    private var leannRootPath: URL?
    
    /// Current codebase URL (security-scoped)
    private var currentIndexURL: URL?
    
    /// Current vector index path
    private var currentIndexPath: URL?
    
    /// Indexing state
    public enum IndexingState: Sendable, Equatable {
        case notIndexed
        case indexing(progress: String)
        case indexed(fileCount: Int, path: String)
        case error(String)
    }
    
    /// Current indexing state
    public private(set) var indexingState: IndexingState = .notIndexed
    
    /// UserDefaults keys
    private enum Keys {
        static let indexedCodebasePath = "leannIndexedCodebasePath"
        static let indexPath = "leannIndexPath"
        static let indexedFileCount = "leannIndexedFileCount"
        static let securityBookmark = "leannSecurityBookmark"
    }
    
    private init() {
        let resolved = Self.resolveConfiguration()
        self.pythonPath = resolved.pythonPath
        self.bridgeScriptPath = resolved.bridgeScriptPath
        self.leannRootPath = resolved.leannRootPath
        
        Self.logConfigurationStatus(
            pythonPath: self.pythonPath,
            bridgeScriptPath: self.bridgeScriptPath,
            overridePath: UserDefaults.standard.string(forKey: UserDefaultsKey.leannRootPath)
        )
        
        // Load saved index state
        if let savedPath = UserDefaults.standard.string(forKey: Keys.indexedCodebasePath),
           let indexPath = UserDefaults.standard.string(forKey: Keys.indexPath) {
            let fileCount = UserDefaults.standard.integer(forKey: Keys.indexedFileCount)
            self.currentIndexPath = URL(fileURLWithPath: indexPath)
            
            // Try to resolve bookmark if it exists
            if let bookmarkData = UserDefaults.standard.data(forKey: Keys.securityBookmark) {
                var isStale = false
                if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    // Start accessing if we can
                    _ = resolvedURL.startAccessingSecurityScopedResource()
                    self.currentIndexURL = resolvedURL
                    self.indexingState = .indexed(fileCount: fileCount, path: resolvedURL.path)
                    Log.info("✅ LEANNBridgeService: Resolved and accessing bookmark for \(resolvedURL.path)")
                } else {
                    self.indexingState = .indexed(fileCount: fileCount, path: savedPath)
                }
            } else {
                self.indexingState = .indexed(fileCount: fileCount, path: savedPath)
            }
        }
    }

    public func reloadConfiguration() {
        let resolved = Self.resolveConfiguration()
        self.pythonPath = resolved.pythonPath
        self.bridgeScriptPath = resolved.bridgeScriptPath
        self.leannRootPath = resolved.leannRootPath
        Self.logConfigurationStatus(
            pythonPath: resolved.pythonPath,
            bridgeScriptPath: resolved.bridgeScriptPath,
            overridePath: UserDefaults.standard.string(forKey: UserDefaultsKey.leannRootPath)
        )
    }

    public func getResolvedLeannRootPath() -> String? {
        return leannRootPath?.path
    }
    
    /// Index a codebase directory
    /// - Parameter url: URL to the codebase root directory
    /// - Returns: Result with file count or error
    public func indexCodebase(url: URL) async throws -> Int {
        indexingState = .indexing(progress: "Starting indexing...")
        
        // Create bookmark for security-scoped access
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: Keys.securityBookmark)
        } catch {
            Log.warn("⚠️ Warning: Failed to create bookmark for \(url.path): \(error)")
        }
        
        // Ensure we can access it
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        
        let path = url.path
        
        guard let leannRootPath else {
            indexingState = .error("LEANN bridge not configured.")
            throw LEANNError.missingConfiguration("LEANN bridge not configured. Set LEANN_ROOT or LEANN_PYTHON_PATH/LEANN_BRIDGE_PATH.")
        }
        
        guard pythonPath != nil, bridgeScriptPath != nil else {
            indexingState = .error("LEANN bridge not configured.")
            throw LEANNError.missingConfiguration("LEANN bridge not configured. Set LEANN_ROOT or LEANN_PYTHON_PATH/LEANN_BRIDGE_PATH.")
        }
        
        // Create index path in the leann root directory
        let indexPath = leannRootPath.appendingPathComponent("code_index")
        
        // Run Python indexing
        let result = try await runPythonCommand(
            command: "index",
            arguments: [path, "--extensions", ".swift", ".py", ".js", ".ts", ".md", ".json", "--index-path", indexPath.path]
        )
        
        // Parse result
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            indexingState = .error("Failed to parse indexing result")
            throw LEANNError.parsingFailed("Invalid JSON response")
        }
        
        if let error = json["error"] as? String {
            indexingState = .error(error)
            throw LEANNError.indexingFailed(error)
        }
        
        guard let success = json["success"] as? Bool, success,
              let fileCount = json["indexed_files"] as? Int else {
            indexingState = .error("Indexing failed")
            throw LEANNError.indexingFailed("Unknown error")
        }
        
        // Save state
        self.currentIndexPath = indexPath
        self.currentIndexURL = url
        UserDefaults.standard.set(path, forKey: Keys.indexedCodebasePath)
        UserDefaults.standard.set(indexPath.path, forKey: Keys.indexPath)
        UserDefaults.standard.set(fileCount, forKey: Keys.indexedFileCount)
        
        indexingState = .indexed(fileCount: fileCount, path: path)
        
        Log.info("✅ LEANNBridgeService: Indexed \(fileCount) files from \(path)")
        return fileCount
    }
    
    /// Search the indexed codebase using semantic search
    /// - Parameters:
    ///   - query: Search query
    ///   - topK: Number of results to return
    /// - Returns: Array of search results
    public func search(query: String, topK: Int = 5) async throws -> [CodeSearchResult] {
        guard let indexPath = currentIndexPath else {
            throw LEANNError.notIndexed
        }
        
        let result = try await runPythonCommand(
            command: "search",
            arguments: [query, "--top-k", String(topK), "--index-path", indexPath.path]
        )
        
        return try parseSearchResults(result)
    }

    /// Search the indexed codebase using exact text matching (grep)
    /// - Parameters:
    ///   - pattern: Grep pattern or regex
    ///   - topK: Number of results
    /// - Returns: Array of search results
    public func grepSearch(pattern: String, topK: Int = 10) async throws -> [CodeSearchResult] {
        guard let indexPath = currentIndexPath else {
            throw LEANNError.notIndexed
        }
        
        let result = try await runPythonCommand(
            command: "search",
            arguments: [pattern, "--top-k", String(topK), "--index-path", indexPath.path, "--grep"]
        )
        
        return try parseSearchResults(result)
    }
    
    private func parseSearchResults(_ result: String) throws -> [CodeSearchResult] {
        // Parse results
        guard let data = result.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw LEANNError.parsingFailed("Invalid JSON response")
        }
        
        // Check for error in first result
        if let firstResult = jsonArray.first,
           let error = firstResult["error"] as? String {
            throw LEANNError.searchFailed(error)
        }
        
        var results: [CodeSearchResult] = []
        for item in jsonArray {
            guard let content = item["content"] as? String,
                  let score = item["score"] as? Double,
                  let metadata = item["metadata"] as? [String: Any] else {
                continue
            }
            
            let filePath = metadata["file_path"] as? String ?? "unknown"
            let fileName = metadata["file_name"] as? String ?? "unknown"
            let fileExtension = metadata["file_extension"] as? String ?? ""
            
            results.append(CodeSearchResult(
                content: content,
                filePath: filePath,
                fileName: fileName,
                fileExtension: fileExtension,
                score: score
            ))
        }
        
        return results
    }
    /// Current codebase URL (security-scoped)
    private var indexedURL: URL? {
        if let current = currentIndexURL {
            return current
        }
        if case .indexed(_, let path) = indexingState {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    
    /// Get the current indexed codebase path
    public func getIndexedPath() -> String? {
        return indexedURL?.path
    }
    
    /// Get the current indexed codebase URL
    public func getIndexedURL() -> URL? {
        return indexedURL
    }
    
    /// Clear the index and delete the physical files
    public func clearIndex() {
        // Determine path to delete
        var pathToDelete: String? = currentIndexPath?.path
        
        if pathToDelete == nil {
            pathToDelete = UserDefaults.standard.string(forKey: Keys.indexPath)
        }
        
        if let path = pathToDelete {
            do {
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(atPath: path)
                    Log.info("🗑️ LEANNBridgeService: Deleted index at \(path)")
                }
            } catch {
                Log.error("❌ LEANNBridgeService: Failed to delete index at \(path): \(error.localizedDescription)")
            }
        }
        
        currentIndexPath = nil
        indexingState = .notIndexed
        UserDefaults.standard.removeObject(forKey: Keys.indexedCodebasePath)
        UserDefaults.standard.removeObject(forKey: Keys.indexPath)
        UserDefaults.standard.removeObject(forKey: Keys.indexedFileCount)
        UserDefaults.standard.removeObject(forKey: Keys.securityBookmark)
    }
    
    // MARK: - Private
    
    private func runPythonCommand(command: String, arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            guard let pythonPath, let bridgeScriptPath else {
                continuation.resume(throwing: LEANNError.missingConfiguration("LEANN bridge not configured. Set LEANN_ROOT or LEANN_PYTHON_PATH/LEANN_BRIDGE_PATH."))
                return
            }
            let process = Process()
            process.executableURL = pythonPath
            process.arguments = [bridgeScriptPath.path, command] + arguments
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            let collector = OutputCollector()
            
            outputHandle.readabilityHandler = { handle in
                collector.appendOutput(handle.availableData)
            }
            
            errorHandle.readabilityHandler = { handle in
                collector.appendError(handle.availableData)
            }
            
            process.terminationHandler = { _ in
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                collector.appendOutput(outputHandle.readDataToEndOfFile())
                collector.appendError(errorHandle.readDataToEndOfFile())
                
                let (outputData, errorData) = collector.snapshotAndFinalize()
                
                if process.terminationStatus != 0 {
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: LEANNError.processError(errorOutput))
                    return
                }
                
                let fullOutput = String(data: outputData, encoding: .utf8) ?? ""
                
                // Extract JSON between markers
                let startMarker = "---JSON_START---"
                let endMarker = "---JSON_END---"
                
                if let startRange = fullOutput.range(of: startMarker),
                   let endRange = fullOutput.range(of: endMarker),
                   startRange.upperBound < endRange.lowerBound {
                    let jsonString = String(fullOutput[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: jsonString)
                } else {
                    // Fallback to full output if markers not found (for backward compatibility or unexpected output)
                    if fullOutput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") ||
                        fullOutput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                        continuation.resume(returning: fullOutput)
                    } else {
                        continuation.resume(throwing: LEANNError.parsingFailed("Could not find JSON markers in output: \(fullOutput)"))
                    }
                }
            }
            
            do {
                try process.run()
            } catch {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                continuation.resume(throwing: LEANNError.processError(error.localizedDescription))
            }
        }
    }

    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var outputData = Data()
        private var errorData = Data()
        private var finalized = false
        
        func appendOutput(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            if !finalized {
                outputData.append(data)
            }
            lock.unlock()
        }
        
        func appendError(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            if !finalized {
                errorData.append(data)
            }
            lock.unlock()
        }
        
        func snapshotAndFinalize() -> (Data, Data) {
            lock.lock()
            if finalized {
                let snapshot = (outputData, errorData)
                lock.unlock()
                return snapshot
            }
            finalized = true
            let snapshot = (outputData, errorData)
            lock.unlock()
            return snapshot
        }
    }

    private static func resolveConfiguration() -> (pythonPath: URL?, bridgeScriptPath: URL?, leannRootPath: URL?) {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        
        if let overrideRoot = UserDefaults.standard.string(forKey: UserDefaultsKey.leannRootPath),
           !overrideRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let resolvedRoot = resolveLeannRoot(from: overrideRoot, fileManager: fileManager) {
            return resolvePaths(from: resolvedRoot, fileManager: fileManager)
        }
        
        if let pythonEnv = environment["LEANN_PYTHON_PATH"],
           let bridgeEnv = environment["LEANN_BRIDGE_PATH"] {
            let pythonURL = URL(fileURLWithPath: pythonEnv)
            let bridgeURL = URL(fileURLWithPath: bridgeEnv)
            let pythonPath = fileManager.fileExists(atPath: pythonURL.path) ? pythonURL : nil
            let bridgeScriptPath = fileManager.fileExists(atPath: bridgeURL.path) ? bridgeURL : nil
            let root = bridgeScriptPath?.deletingLastPathComponent()
            return (pythonPath, bridgeScriptPath, root)
        }
        
        if let configuredRoot = environment["LEANN_ROOT"],
           let resolvedRoot = resolveLeannRoot(from: configuredRoot, fileManager: fileManager) {
            return resolvePaths(from: resolvedRoot, fileManager: fileManager)
        }
        
        if let resolvedRoot = resolveLeannRootFromSearch(fileManager: fileManager) {
            return resolvePaths(from: resolvedRoot, fileManager: fileManager)
        }
        
        return (nil, nil, nil)
    }
    
    private static func resolvePaths(from root: URL, fileManager: FileManager) -> (pythonPath: URL?, bridgeScriptPath: URL?, leannRootPath: URL?) {
        let pythonURL = root
            .appendingPathComponent("venv")
            .appendingPathComponent("bin")
            .appendingPathComponent("python")
        let bridgeURL = root.appendingPathComponent("leann_bridge.py")
        
        let pythonPath = fileManager.fileExists(atPath: pythonURL.path) ? pythonURL : nil
        let bridgeScriptPath = fileManager.fileExists(atPath: bridgeURL.path) ? bridgeURL : nil
        
        return (pythonPath, bridgeScriptPath, root)
    }
    
    private static func resolveLeannRoot(from path: String, fileManager: FileManager) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        
        let configuredURL = URL(fileURLWithPath: trimmed)
        if configuredURL.lastPathComponent == "leann_poc",
           fileManager.fileExists(atPath: configuredURL.path) {
            return configuredURL
        }
        
        let candidate = configuredURL.appendingPathComponent("leann_poc")
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        
        return nil
    }
    
    private static func resolveLeannRootFromSearch(fileManager: FileManager) -> URL? {
        var bases: [URL] = []
        bases.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        
        if let executablePath = ProcessInfo.processInfo.arguments.first {
            bases.append(URL(fileURLWithPath: executablePath).deletingLastPathComponent())
        }
        
        if let bundleResourceURL = Bundle.main.resourceURL {
            bases.append(bundleResourceURL)
        }
        
        for base in bases {
            if let resolved = findLeannRoot(startingAt: base, fileManager: fileManager) {
                return resolved
            }
        }
        
        return nil
    }
    
    private static func findLeannRoot(startingAt base: URL, fileManager: FileManager) -> URL? {
        var current = base
        
        for _ in 0..<6 {
            let candidate = current.appendingPathComponent("leann_poc")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        
        return nil
    }

    private static func logConfigurationStatus(
        pythonPath: URL?,
        bridgeScriptPath: URL?,
        overridePath: String?
    ) {
        if let pythonPath, let bridgeScriptPath {
            Log.info("🐍 LEANN Python path: \(pythonPath.path)")
            Log.info("📜 LEANN Bridge script: \(bridgeScriptPath.path)")
        } else {
            let override = overridePath ?? ""
            let overrideStatus = override.isEmpty ? "not set" : "set to \(override)"
            Log.warn("⚠️ LEANNBridgeService: LEANN paths not configured. Override \(overrideStatus).")
        }
    }
}

/// Result from code search
@available(macOS 26.0, iOS 26.0, *)
public struct CodeSearchResult: Sendable {
    public let content: String
    public let filePath: String
    public let fileName: String
    public let fileExtension: String
    public let score: Double
}

/// Errors for LEANN operations
@available(macOS 26.0, iOS 26.0, *)
public enum LEANNError: Error, LocalizedError, Sendable {
    case notIndexed
    case indexingFailed(String)
    case searchFailed(String)
    case parsingFailed(String)
    case processError(String)
    case missingConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .notIndexed:
            return "No codebase has been indexed. Please select a codebase directory in Settings."
        case .indexingFailed(let reason):
            return "Indexing failed: \(reason)"
        case .searchFailed(let reason):
            return "Search failed: \(reason)"
        case .parsingFailed(let reason):
            return "Failed to parse response: \(reason)"
        case .processError(let reason):
            return "Process error: \(reason)"
        case .missingConfiguration(let reason):
            return reason
        }
    }
}
