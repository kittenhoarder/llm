//
//  TaskDecompositionParser.swift
//  FoundationChatCore
//
//  Parser for extracting task decomposition from coordinator's natural language analysis
//

import Foundation

/// Parser for extracting subtasks from coordinator's natural language analysis
@available(macOS 26.0, iOS 26.0, *)
public actor TaskDecompositionParser {
    private let registry: AgentRegistry
    private let tokenCounter: TokenCounter
    
    public init(registry: AgentRegistry = .shared, tokenCounter: TokenCounter = TokenCounter()) {
        self.registry = registry
        self.tokenCounter = tokenCounter
    }
    
    /// Parse coordinator's analysis output into structured task decomposition
    /// - Parameters:
    ///   - analysis: The coordinator's natural language analysis
    ///   - availableAgents: List of available agents for matching
    /// - Returns: Parsed task decomposition, or nil if parsing fails
    public func parse(_ analysis: String, availableAgents: [any Agent]) async -> TaskDecomposition? {
        print("🔍 TaskDecompositionParser: Parsing coordinator analysis...")
        
        // Try to extract subtasks using various patterns
        let subtasks = await extractSubtasks(from: analysis, availableAgents: availableAgents)
        
        guard !subtasks.isEmpty else {
            print("⚠️ TaskDecompositionParser: No subtasks extracted, parsing failed")
            return nil
        }
        
        print("✅ TaskDecompositionParser: Extracted \(subtasks.count) subtasks")
        
        // Estimate token costs
        let subtasksWithCosts = await estimateTokenCosts(subtasks)
        
        // Calculate execution order based on dependencies
        let executionOrder = calculateExecutionOrder(subtasks: subtasksWithCosts)
        
        return TaskDecomposition(
            subtasks: subtasksWithCosts,
            executionOrder: executionOrder
        )
    }
    
    /// Extract subtasks from natural language text
    private func extractSubtasks(from text: String, availableAgents: [any Agent]) async -> [DecomposedSubtask] {
        var subtasks: [DecomposedSubtask] = []
        var subtaskNumberToID: [Int: UUID] = [:] // Mapping for dependency resolution
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "TaskDecompositionParser.swift:extractSubtasks",
            message: "Starting extraction",
            hypothesisId: "D",
            data: [
                "textLength": text.count,
                "textPreview": String(text.prefix(300))
            ]
        )
        
        // Pattern 0: Markdown subtask headers (### or #### Subtask N: Description)
        // This pattern extracts structured subtasks with headers like "### Subtask 1: ..." or "#### Subtask 1: ..."
        // It extracts the full section including metadata for dependency parsing
        let markdownSubtaskHeaderPattern = #"(?m)^\s*#{3,4}\s+Subtask\s+(\d+)\s*:"#
        if let headerRegex = try? NSRegularExpression(pattern: markdownSubtaskHeaderPattern, options: []) {
            let headerMatches = headerRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            // Build mapping of subtask number to section text for dependency extraction
            var subtaskSections: [Int: String] = [:]
            var subtaskNumbers: [Int] = []
            
            // Extract each subtask section (from header to next header or end of text)
            for (index, match) in headerMatches.enumerated() {
                if match.numberOfRanges >= 2,
                   let numberRange = Range(match.range(at: 1), in: text),
                   let subtaskNumber = Int(String(text[numberRange])) {
                    
                    // Find the range from this header to the next header (or end of text)
                    let sectionStart = match.range.location
                    let sectionEnd: Int
                    if index < headerMatches.count - 1 {
                        sectionEnd = headerMatches[index + 1].range.location
                    } else {
                        sectionEnd = text.count
                    }
                    
                    let sectionRange = NSRange(location: sectionStart, length: sectionEnd - sectionStart)
                    if let sectionContent = Range(sectionRange, in: text) {
                        let sectionText = String(text[sectionContent])
                        subtaskSections[subtaskNumber] = sectionText
                        subtaskNumbers.append(subtaskNumber)
                    }
                }
            }
            
            // Sort by subtask number to maintain order
            subtaskNumbers.sort()
            
            // Debug logging
            await DebugLogger.shared.log(
                location: "TaskDecompositionParser.swift:extractSubtasks",
                message: "Markdown subtask pattern matches",
                hypothesisId: "D",
                data: [
                    "matchCount": headerMatches.count,
                    "subtaskNumbers": subtaskNumbers
                ]
            )
            
            // First pass: Parse all subtasks and build number-to-ID mapping
            var parsedSubtasks: [(Int, DecomposedSubtask)] = []
            for subtaskNumber in subtaskNumbers {
                guard let sectionText = subtaskSections[subtaskNumber] else { continue }
                
                // Extract description from header (first line after "Subtask N:")
                // Look for the actual task description, which might be on the next line after numbered items
                let headerPattern = #"Subtask\s+\d+\s*:\s*([^\n]+)"#
                var description = ""
                if let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: []),
                   let headerMatch = headerRegex.firstMatch(in: sectionText, range: NSRange(sectionText.startIndex..., in: sectionText)),
                   headerMatch.numberOfRanges >= 2,
                   let descRange = Range(headerMatch.range(at: 1), in: sectionText) {
                    let headerDesc = String(sectionText[descRange]).trimmingCharacters(in: .whitespaces)
                    
                    // Check if header description is just a title (like "Identify Relevant Sources")
                    // If so, look for "**Specific Task Description**: ..." in the section
                    if !isMetadataField(headerDesc) && headerDesc.count > 10 {
                        description = headerDesc
                    } else {
                        // Look for "**Specific Task Description**: ..." pattern
                        let taskDescPattern = #"\*\*Specific Task Description\*\*:\s*([^\n]+)"#
                        if let taskDescRegex = try? NSRegularExpression(pattern: taskDescPattern, options: [.caseInsensitive]),
                           let taskDescMatch = taskDescRegex.firstMatch(in: sectionText, range: NSRange(sectionText.startIndex..., in: sectionText)),
                           taskDescMatch.numberOfRanges >= 2,
                           let taskDescRange = Range(taskDescMatch.range(at: 1), in: sectionText) {
                            description = String(sectionText[taskDescRange]).trimmingCharacters(in: .whitespaces)
                        } else if !isMetadataField(headerDesc) {
                            // Fallback to header description if it's not metadata
                            description = headerDesc
                        }
                    }
                }
                
                if !description.isEmpty {
                    // Parse subtask without dependencies first (will add them in second pass)
                    if let subtask = parseSubtaskText(description, availableAgents: availableAgents) {
                        subtaskNumberToID[subtaskNumber] = subtask.id
                        parsedSubtasks.append((subtaskNumber, subtask))
                    } else {
                        print("🔍 TaskDecompositionParser: Rejected subtask from markdown header: \(description.prefix(80))")
                    }
                }
            }
            
            // Second pass: Extract dependencies and update subtasks
            for (subtaskNumber, subtask) in parsedSubtasks {
                var finalSubtask = subtask
                if let sectionText = subtaskSections[subtaskNumber] {
                    print("🔍 TaskDecompositionParser: Extracting dependencies for Subtask \(subtaskNumber)")
                    print("🔍 TaskDecompositionParser: Section text: \(String(sectionText.prefix(200)))")
                    let dependencies = extractDependencies(
                        from: sectionText,
                        subtaskNumber: subtaskNumber,
                        subtaskNumberToID: subtaskNumberToID
                    )
                    print("🔍 TaskDecompositionParser: Found \(dependencies.count) dependencies for Subtask \(subtaskNumber)")
                    if !dependencies.isEmpty {
                        // Create new subtask with dependencies
                        finalSubtask = DecomposedSubtask(
                            id: subtask.id,
                            description: subtask.description,
                            agentName: subtask.agentName,
                            requiredCapabilities: subtask.requiredCapabilities,
                            priority: subtask.priority,
                            dependencies: dependencies,
                            canExecuteInParallel: dependencies.isEmpty && subtask.canExecuteInParallel,
                            estimatedTokenCost: subtask.estimatedTokenCost
                        )
                        print("🔗 TaskDecompositionParser: Subtask \(subtaskNumber) has \(dependencies.count) dependencies: \(dependencies.map { $0.uuidString.prefix(8) })")
                    } else {
                        print("⚠️ TaskDecompositionParser: Subtask \(subtaskNumber) has NO dependencies (may be incorrect)")
                    }
                } else {
                    print("⚠️ TaskDecompositionParser: No section text found for Subtask \(subtaskNumber)")
                }
                subtasks.append(finalSubtask)
            }
            
            // If we found subtasks with markdown pattern, don't fall back to other patterns
            if !subtasks.isEmpty {
                print("✅ TaskDecompositionParser: Found \(subtasks.count) subtasks via markdown pattern, skipping other patterns")
            }
        }
        
        // Pattern 1: Numbered list (1., 2., etc.) - only if markdown pattern didn't match
        if subtasks.isEmpty {
            let numberedPattern = #"(?m)^\s*(\d+)\.\s+(.+?)(?=\n\s*\d+\.|$)"#
            if let regex = try? NSRegularExpression(pattern: numberedPattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                
                // Debug logging
                await DebugLogger.shared.log(
                    location: "TaskDecompositionParser.swift:extractSubtasks",
                    message: "Numbered pattern matches",
                    hypothesisId: "D",
                    data: [
                        "matchCount": matches.count,
                        "matches": matches.prefix(10).map { match in
                            if match.numberOfRanges >= 3 {
                                let contentRange = match.range(at: 2)
                                if let content = Range(contentRange, in: text) {
                                    return String(text[content].prefix(100))
                                }
                            }
                            return ""
                        }
                    ]
                )
                for match in matches {
                    if match.numberOfRanges >= 3 {
                        let contentRange = match.range(at: 2)
                        if let content = Range(contentRange, in: text) {
                            let subtaskText = String(text[content])
                            if let subtask = parseSubtaskText(subtaskText, availableAgents: availableAgents) {
                                subtasks.append(subtask)
                            }
                        }
                    }
                }
            }
        }
        
        // Pattern 2: Bullet points (-, *, •)
        if subtasks.isEmpty {
            let bulletPattern = #"(?m)^\s*[-*•]\s+(.+?)(?=\n\s*[-*•]|$)"#
            if let regex = try? NSRegularExpression(pattern: bulletPattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                
                // Debug logging
                await DebugLogger.shared.log(
                    location: "TaskDecompositionParser.swift:extractSubtasks",
                    message: "Bullet pattern matches",
                    hypothesisId: "D",
                    data: [
                        "matchCount": matches.count,
                        "matches": matches.prefix(20).map { match in
                            if match.numberOfRanges >= 2 {
                                let contentRange = match.range(at: 1)
                                if let content = Range(contentRange, in: text) {
                                    return String(text[content].prefix(100))
                                }
                            }
                            return ""
                        }
                    ]
                )
                for match in matches {
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        if let content = Range(contentRange, in: text) {
                            let subtaskText = String(text[content])
                            if let subtask = parseSubtaskText(subtaskText, availableAgents: availableAgents) {
                                subtasks.append(subtask)
                            }
                        }
                    }
                }
            }
        }
        
        // Pattern 3: "Subtask:" labels
        if subtasks.isEmpty {
            let subtaskPattern = #"(?i)subtask\s*[:\-]\s*(.+?)(?=\n\s*(?:subtask|task|$))"#
            if let regex = try? NSRegularExpression(pattern: subtaskPattern, options: []) {
                let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in matches {
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        if let content = Range(contentRange, in: text) {
                            let subtaskText = String(text[content])
                            if let subtask = parseSubtaskText(subtaskText, availableAgents: availableAgents) {
                                subtasks.append(subtask)
                            }
                        }
                    }
                }
            }
        }
        
        // If still no subtasks, try to split by paragraphs and treat each as a subtask
        // But filter out metadata-heavy paragraphs
        if subtasks.isEmpty {
            let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            
            // Debug logging
            await DebugLogger.shared.log(
                location: "TaskDecompositionParser.swift:extractSubtasks",
                message: "Falling back to paragraph splitting",
                hypothesisId: "E",
                data: [
                    "paragraphCount": paragraphs.count,
                    "paragraphs": paragraphs.prefix(10).map { String($0.prefix(100)) }
                ]
            )
            for paragraph in paragraphs {
                // Skip paragraphs that are mostly metadata
                if isMetadataParagraph(paragraph) {
                    print("🔍 TaskDecompositionParser: Skipping metadata paragraph: \(paragraph.prefix(80))")
                    continue
                }
                if let subtask = parseSubtaskText(paragraph, availableAgents: availableAgents) {
                    subtasks.append(subtask)
                }
            }
        }
        
        // Debug logging
        await DebugLogger.shared.log(
            location: "TaskDecompositionParser.swift:extractSubtasks",
            message: "Extraction complete",
            hypothesisId: "D",
            data: [
                "finalSubtaskCount": subtasks.count,
                "subtasks": subtasks.map { [
                    "id": $0.id.uuidString,
                    "description": String($0.description.prefix(150)),
                    "agentName": $0.agentName ?? "none"
                ] }
            ]
        )
        
        return subtasks
    }
    
    /// Parse a single subtask text into a DecomposedSubtask
    private func parseSubtaskText(_ text: String, availableAgents: [any Agent]) -> DecomposedSubtask? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Filter out metadata-only lines (like "**Capabilities Needed:** dataAnalysis")
        // These are not actual subtasks, just metadata fields
        if isMetadataField(trimmed) {
            print("🔍 TaskDecompositionParser: Skipping metadata field: \(trimmed.prefix(80))")
            return nil
        }
        
        // Also filter out very short descriptions that are likely just labels
        if trimmed.count < 15 {
            print("🔍 TaskDecompositionParser: Skipping very short text (likely label): \(trimmed)")
            return nil
        }
        
        // Extract agent name mentions
        let agentName = extractAgentName(from: trimmed, availableAgents: availableAgents)
        
        // Extract capabilities
        let capabilities = extractCapabilities(from: trimmed)
        
        // Dependencies will be extracted in second pass, so return empty for now
        let dependencies: [UUID] = []
        
        // Detect if can execute in parallel (default to true unless dependencies exist)
        let canExecuteInParallel = dependencies.isEmpty && !containsSequentialKeywords(trimmed)
        
        return DecomposedSubtask(
            description: trimmed,
            agentName: agentName,
            requiredCapabilities: capabilities,
            dependencies: dependencies,
            canExecuteInParallel: canExecuteInParallel
        )
    }
    
    /// Check if a paragraph is mostly metadata (not an actual subtask)
    private func isMetadataParagraph(_ paragraph: String) -> Bool {
        let lines = paragraph.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        // If most lines are metadata fields, it's a metadata paragraph
        var metadataLineCount = 0
        for line in nonEmptyLines {
            if isMetadataField(line) {
                metadataLineCount += 1
            }
        }
        
        // If more than half the lines are metadata, skip this paragraph
        if nonEmptyLines.count > 0 && Double(metadataLineCount) / Double(nonEmptyLines.count) > 0.5 {
            return true
        }
        
        // Also check if the paragraph starts with numbered metadata items
        if let firstLine = nonEmptyLines.first, isMetadataField(firstLine) {
            // If it starts with metadata and has multiple numbered items, it's likely all metadata
            let numberedMetadataCount = nonEmptyLines.filter { line in
                let numberedMetadataPattern = #"^\s*\d+\.\s*\*\*"#
                if let regex = try? NSRegularExpression(pattern: numberedMetadataPattern, options: []) {
                    return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                }
                return false
            }.count
            
            if numberedMetadataCount >= 2 {
                return true
            }
        }
        
        return false
    }
    
    /// Check if text is a metadata field (not an actual subtask)
    private func isMetadataField(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Check for lines that start with "**" followed by metadata field names
        if trimmed.hasPrefix("**") {
            let metadataFieldPatterns = [
                "**dependencies",
                "**parallel capability",
                "**parallel",
                "**agent handling",
                "**agent to handle",
                "**agent:",
                "**capabilities needed",
                "**capability",
                "**can run in parallel",
                "**must be done after",
                "**requires completion"
            ]
            for pattern in metadataFieldPatterns {
                if lowercased.hasPrefix(pattern.lowercased()) {
                    return true
                }
            }
        }
        
        // Check for markdown-style metadata patterns
        let metadataPatterns = [
            "**capabilities needed:**",
            "**agent:**",
            "**agent to handle:**",
            "**dependencies:**",
            "**dependencies on other subtasks:**",
            "**parallel capability:**",
            "**parallel:**",
            "**can run in parallel:**",
            "**overall task flow:**",
            "**initialization:**",
            "**parallel execution:**",
            "**completion of subtasks:**",
            "**must be done after:**",
            "**requires completion:**",
            "capabilities needed:",
            "agent:",
            "agent to handle:",
            "dependencies:",
            "dependencies on other subtasks:",
            "parallel capability:",
            "parallel:",
            "can run in parallel:",
            "this breakdown ensures",
            "overall task flow",
            "initialization:",
            "parallel execution:",
            "completion of subtasks:",
            "must be done after",
            "requires completion"
        ]
        
        // If text starts with a metadata pattern, it's likely a metadata field
        for pattern in metadataPatterns {
            if lowercased.hasPrefix(pattern) || lowercased.trimmingCharacters(in: .whitespaces).hasPrefix(pattern) {
                return true
            }
        }
        
        // Check for numbered metadata items (1. **Task Description:**, 2. **Agent:**, etc.)
        let numberedMetadataPattern = #"^\s*\d+\.\s*\*\*"#
        if let regex = try? NSRegularExpression(pattern: numberedMetadataPattern, options: []),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        
        // Check for lines that start with "- **" or "* **" (bullet points with bold metadata)
        if trimmed.hasPrefix("- **") || trimmed.hasPrefix("* **") {
            return true
        }
        
        // Check for lines that are just metadata labels with minimal content
        if text.count < 50 && (text.contains(":") || text.contains("**")) {
            // Check if it's mostly just a label with minimal content
            let parts = text.split(separator: ":")
            if parts.count == 2 && parts[1].trimmingCharacters(in: .whitespaces).count < 20 {
                return true
            }
        }
        
        // Check for dependency statements that are just metadata
        if lowercased.contains("requires completion of subtask") || 
           lowercased.contains("depends on subtask") ||
           lowercased.contains("must be done after subtask") {
            // If the text is ONLY about dependencies and doesn't describe an actual task, it's metadata
            if !lowercased.contains("task description") && 
               !lowercased.contains("identify") &&
               !lowercased.contains("collect") &&
               !lowercased.contains("analyze") &&
               !lowercased.contains("compile") &&
               !lowercased.contains("finalize") &&
               !lowercased.contains("gather") {
                return true
            }
        }
        
        // Check for parallel capability statements that are just metadata
        if (lowercased.contains("parallel capability") || lowercased.contains("can run in parallel")) &&
           !lowercased.contains("task description") {
            // If it's just talking about parallel capability without describing a task, it's metadata
            if text.count < 80 {
                return true
            }
        }
        
        // Check for explanatory text that's not a task
        let explanatoryPatterns = [
            "this breakdown ensures",
            "overall task flow",
            "the task is divided",
            "manageable parts",
            "utilizing the right agent",
            "provide a breakdown",
            "certainly!",
            "let's break down",
            "format your response"
        ]
        for pattern in explanatoryPatterns {
            if lowercased.contains(pattern) && text.count < 200 {
                return true
            }
        }
        
        return false
    }
    
    /// Extract agent name from text
    private func extractAgentName(from text: String, availableAgents: [any Agent]) -> String? {
        let lowercased = text.lowercased()
        
        // Try to match agent names
        for agent in availableAgents {
            let agentNameLower = agent.name.lowercased()
            if lowercased.contains(agentNameLower) {
                return agent.name
            }
            
            // Also check for variations
            let variations = [
                "\(agentNameLower) agent",
                "\(agentNameLower) handler",
                "use \(agentNameLower)",
                "\(agentNameLower) should",
                "\(agentNameLower) will"
            ]
            
            for variation in variations {
                if lowercased.contains(variation) {
                    return agent.name
                }
            }
        }
        
        return nil
    }
    
    /// Extract required capabilities from text
    private func extractCapabilities(from text: String) -> Set<AgentCapability> {
        let lowercased = text.lowercased()
        var capabilities: Set<AgentCapability> = []
        
        if lowercased.contains("search") || lowercased.contains("web") || lowercased.contains("look up") {
            capabilities.insert(.webSearch)
        }
        
        if lowercased.contains("file") || lowercased.contains("read") || lowercased.contains("document") {
            capabilities.insert(.fileReading)
        }
        
        if lowercased.contains("code") || lowercased.contains("analyze code") || lowercased.contains("programming") {
            capabilities.insert(.codeAnalysis)
        }
        
        if lowercased.contains("data") || lowercased.contains("calculate") || lowercased.contains("statistics") {
            capabilities.insert(.dataAnalysis)
        }
        
        if lowercased.contains("coordinate") || lowercased.contains("reason") || lowercased.contains("plan") {
            capabilities.insert(.generalReasoning)
        }
        
        return capabilities
    }
    
    /// Extract dependencies from text
    /// - Parameters:
    ///   - text: The text to search for dependencies (full section text)
    ///   - subtaskNumber: The current subtask number
    ///   - subtaskNumberToID: Mapping of subtask numbers to their UUIDs
    /// - Returns: Array of UUIDs for dependent subtasks
    private func extractDependencies(
        from text: String,
        subtaskNumber: Int,
        subtaskNumberToID: [Int: UUID]
    ) -> [UUID] {
        var dependencyUUIDs: [UUID] = []
        let lowercased = text.lowercased()
        
        // First, try to extract from markdown bold format: **Dependencies:** Subtask N
        // Remove markdown bold markers for easier matching
        let cleanedText = text.replacingOccurrences(of: "**", with: "").lowercased()
        
        // Extract subtask numbers from dependency patterns
        // Patterns should account for markdown formatting and various phrasings
        let dependencyPatterns = [
            #"dependencies?\s*:\s*subtask\s+(\d+)"#,  // "Dependencies: Subtask 1"
            #"dependencies?\s+on\s+(?:other\s+)?subtasks?\s*:\s*subtask\s+(\d+)"#,  // "Dependencies on other subtasks: Subtask 1"
            #"depends?\s+on\s*:\s*subtask\s+(\d+)"#,  // "Depends on: Subtask 1"
            #"depends?\s+on\s+subtask\s+(\d+)"#,  // "Depends on Subtask 1"
            #"after\s+subtask\s+(\d+)"#,  // "After Subtask 1"
            #"following\s+subtask\s+(\d+)"#,  // "Following Subtask 1"
            #"requires?\s+subtask\s+(\d+)"#,  // "Requires Subtask 1"
            #"requires?\s+completion\s+of\s+subtask\s+(\d+)"#  // "Requires completion of Subtask 1"
        ]
        
        var foundNumbers: Set<Int> = []
        
        // Try patterns on both original and cleaned text
        for textToSearch in [lowercased, cleanedText] {
            for pattern in dependencyPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let matches = regex.matches(in: textToSearch, range: NSRange(textToSearch.startIndex..., in: textToSearch))
                    for match in matches {
                        if match.numberOfRanges >= 2,
                           let numberRange = Range(match.range(at: 1), in: textToSearch),
                           let depNumber = Int(String(textToSearch[numberRange])),
                           depNumber != subtaskNumber { // Don't depend on self
                            foundNumbers.insert(depNumber)
                            print("🔍 TaskDecompositionParser: Found dependency pattern '\(pattern)' matching Subtask \(depNumber)")
                        }
                    }
                }
            }
        }
        
        // Also check for comma-separated lists like "Dependencies: Subtask 1, Subtask 2"
        let listPattern = #"dependencies?\s*:\s*subtask\s+(\d+)(?:\s*,\s*subtask\s+(\d+))*"#
        for textToSearch in [lowercased, cleanedText] {
            if let regex = try? NSRegularExpression(pattern: listPattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: textToSearch, range: NSRange(textToSearch.startIndex..., in: textToSearch))
                for match in matches {
                    // First number is in group 1
                    if match.numberOfRanges >= 2,
                       let firstRange = Range(match.range(at: 1), in: textToSearch),
                       let firstNum = Int(String(textToSearch[firstRange])),
                       firstNum != subtaskNumber {
                        foundNumbers.insert(firstNum)
                        print("🔍 TaskDecompositionParser: Found list dependency pattern matching Subtask \(firstNum)")
                    }
                    // Additional numbers in subsequent groups
                    for i in 2..<match.numberOfRanges {
                        if let range = Range(match.range(at: i), in: textToSearch),
                           let num = Int(String(textToSearch[range])),
                           num != subtaskNumber {
                            foundNumbers.insert(num)
                            print("🔍 TaskDecompositionParser: Found list dependency pattern matching Subtask \(num)")
                        }
                    }
                }
            }
        }
        
        // Convert subtask numbers to UUIDs
        for depNumber in foundNumbers.sorted() {
            if let depUUID = subtaskNumberToID[depNumber] {
                dependencyUUIDs.append(depUUID)
                print("🔗 TaskDecompositionParser: Subtask \(subtaskNumber) depends on Subtask \(depNumber)")
            } else {
                print("⚠️ TaskDecompositionParser: Could not find UUID for Subtask \(depNumber) (dependency of Subtask \(subtaskNumber))")
            }
        }
        
        return dependencyUUIDs
    }
    
    /// Check if text contains keywords indicating sequential execution
    private func containsSequentialKeywords(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let sequentialKeywords = ["after", "then", "next", "following", "subsequently", "depends on", "requires"]
        return sequentialKeywords.contains { lowercased.contains($0) }
    }
    
    /// Estimate token costs for subtasks
    private func estimateTokenCosts(_ subtasks: [DecomposedSubtask]) async -> [DecomposedSubtask] {
        return await withTaskGroup(of: (Int, DecomposedSubtask).self, returning: [DecomposedSubtask].self) { group in
            for subtask in subtasks {
                group.addTask {
                    let cost = await self.tokenCounter.countTokens(subtask.description)
                    return (subtask.priority, DecomposedSubtask(
                        id: subtask.id,
                        description: subtask.description,
                        agentName: subtask.agentName,
                        requiredCapabilities: subtask.requiredCapabilities,
                        priority: subtask.priority,
                        dependencies: subtask.dependencies,
                        canExecuteInParallel: subtask.canExecuteInParallel,
                        estimatedTokenCost: cost
                    ))
                }
            }
            
            var results: [(Int, DecomposedSubtask)] = []
            for await result in group {
                results.append(result)
            }
            
            // Sort by priority to maintain order
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    /// Calculate execution order based on dependencies
    private func calculateExecutionOrder(subtasks: [DecomposedSubtask]) -> [UUID] {
        // Simple topological sort for dependency ordering
        var order: [UUID] = []
        var visited: Set<UUID> = []
        let subtasksById = Dictionary(uniqueKeysWithValues: subtasks.map { ($0.id, $0) })
        
        func visit(_ subtaskId: UUID) {
            guard !visited.contains(subtaskId) else { return }
            guard let subtask = subtasksById[subtaskId] else { return }
            
            // Visit dependencies first
            for depId in subtask.dependencies {
                visit(depId)
            }
            
            visited.insert(subtaskId)
            order.append(subtaskId)
        }
        
        // Visit all subtasks
        for subtask in subtasks {
            visit(subtask.id)
        }
        
        return order
    }
}

