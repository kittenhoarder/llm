//
//  SettingsView.swift
//  FoundationChatMac
//
//  Settings panel with theme and data management options
//

import SwiftUI
import FoundationChatCore

@available(macOS 26.0, *)
struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage(UserDefaultsKey.fontSizeAdjustment) private var fontSizeAdjustment: Double = 14
    @AppStorage(UserDefaultsKey.preferredColorScheme) private var preferredColorScheme: String = "dark"
    @AppStorage(UserDefaultsKey.useContextualConversations) private var useContextualConversations: Bool = true
    @AppStorage(UserDefaultsKey.serpapiApiKey) private var serpapiApiKey: String = ""
    @AppStorage(UserDefaultsKey.enabledAgentNames) private var enabledAgentNamesJSON: String = ""
    // Legacy support: also check old enabledAgentIds key for migration
    @AppStorage(UserDefaultsKey.enabledAgentIds) private var enabledAgentIdsJSON: String = ""
    @AppStorage(UserDefaultsKey.useCoordinator) private var useCoordinator: Bool = true
    @AppStorage(UserDefaultsKey.smartDelegation) private var smartDelegation: Bool = true
    @AppStorage(UserDefaultsKey.useRAG) private var useRAG: Bool = true
    @AppStorage(UserDefaultsKey.ragChunkSize) private var ragChunkSize: Int = 1000
    @AppStorage(UserDefaultsKey.ragTopK) private var ragTopK: Int = 5
    @State private var showClearDataConfirmation = false
    @State private var availableAgents: [AgentInfo] = []
    
    // Code Analysis state
    @State private var codeAnalysisIndexingState: LEANNBridgeService.IndexingState = .notIndexed
    @State private var isIndexingCodebase = false
    @State private var showIndexingError = false
    @State private var indexingErrorMessage = ""
    
    struct AgentInfo: Identifiable {
        let id: UUID
        let name: String
        let description: String
        let isCoordinator: Bool
    }
    
    private var effectiveColorScheme: ColorScheme {
        switch preferredColorScheme {
        case "light": return .light
        case "dark": return .dark
        case "system": return systemColorScheme
        default: return .dark
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(20)
            .background(Theme.surface(for: effectiveColorScheme))
            
            Divider()
                .background(Theme.border(for: effectiveColorScheme))
            
            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Appearance section
                    SettingsSection(title: "Appearance", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Theme picker
                            HStack {
                                Text("Theme")
                                    .font(Theme.titleFont)
                                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                
                                Spacer()
                                
                                Picker("", selection: $preferredColorScheme) {
                                    Text("Dark").tag("dark")
                                    Text("Light").tag("light")
                                    Text("System").tag("system")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                            }
                            
                            // Font size
                            HStack {
                                Text("Font Size")
                                    .font(Theme.titleFont)
                                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                
                                Spacer()
                                
                                HStack(spacing: 12) {
                                    Button(action: { fontSizeAdjustment = max(12, fontSizeAdjustment - 2) }) {
                                        Image(systemName: "minus")
                                            .font(.system(size: 12, weight: .medium))
                                            .frame(width: 24, height: 24)
                                            .background(Theme.surfaceElevated(for: effectiveColorScheme))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Text("\(Int(fontSizeAdjustment))pt")
                                        .font(Theme.captionFont)
                                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                        .frame(width: 50)
                                    
                                    Button(action: { fontSizeAdjustment = min(24, fontSizeAdjustment + 2) }) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .medium))
                                            .frame(width: 24, height: 24)
                                            .background(Theme.surfaceElevated(for: effectiveColorScheme))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    AgentsToolsSectionView(
                        useCoordinator: $useCoordinator,
                        smartDelegation: $smartDelegation,
                        availableAgents: availableAgents,
                        effectiveColorScheme: effectiveColorScheme,
                        isAgentEnabled: isAgentEnabled,
                        setAgentEnabled: setAgentEnabled,
                        validateAgentSelection: validateAgentSelection,
                        codeAnalysisIndexingState: $codeAnalysisIndexingState,
                        isIndexingCodebase: $isIndexingCodebase
                    )
                    
                    // Conversation section
                    SettingsSection(title: "Conversation", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle(isOn: $useContextualConversations) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Contextual Conversations")
                                        .font(Theme.titleFont)
                                        .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                    Text("Send conversation history to the model for better context-aware responses")
                                        .font(Theme.captionFont)
                                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                }
                            }
                        }
                    }
                    
                    // RAG (Retrieval-Augmented Generation) section
                    SettingsSection(title: "RAG Settings", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Enable RAG toggle
                            Toggle(isOn: $useRAG) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enable RAG")
                                        .font(Theme.titleFont)
                                        .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                    Text("Use semantic search to retrieve only relevant file chunks instead of sending entire files to the LLM. Dramatically improves token efficiency.")
                                        .font(Theme.captionFont)
                                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                }
                            }
                            .toggleStyle(.switch)
                            
                            if useRAG {
                                Divider()
                                    .background(Theme.border(for: effectiveColorScheme))
                                
                                // Chunk size
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Chunk Size")
                                            .font(Theme.titleFont)
                                            .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                        Spacer()
                                        Text("\(ragChunkSize) characters")
                                            .font(Theme.captionFont)
                                            .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                    }
                                    
                                    Slider(value: Binding(
                                        get: { Double(ragChunkSize) },
                                        set: { ragChunkSize = Int($0) }
                                    ), in: 500...2000, step: 100)
                                    .tint(Theme.accent(for: effectiveColorScheme))
                                    
                                    Text("Size of text chunks for indexing. Larger chunks provide more context but may be less precise.")
                                        .font(Theme.captionFont)
                                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                }
                                
                                // Top-K
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Chunks to Retrieve")
                                            .font(Theme.titleFont)
                                            .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                        Spacer()
                                        Text("\(ragTopK) chunks")
                                            .font(Theme.captionFont)
                                            .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                    }
                                    
                                    Stepper(value: $ragTopK, in: 1...20) {
                                        Text("\(ragTopK)")
                                            .font(Theme.captionFont)
                                            .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                    }
                                    
                                    Text("Number of most relevant chunks to retrieve per query. More chunks provide more context but use more tokens.")
                                        .font(Theme.captionFont)
                                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                }
                            }
                        }
                    }
                    
                    // API Keys section
                    SettingsSection(title: "API Keys", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SerpAPI Key")
                                    .font(Theme.titleFont)
                                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                                
                                SecureField("Enter your SerpAPI key", text: $serpapiApiKey)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(Theme.surfaceElevated(for: effectiveColorScheme))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                
                                HStack(spacing: 4) {
                                    if serpapiApiKey.isEmpty {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 10))
                                        Text("No API key set")
                                            .foregroundColor(.orange)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 10))
                                        Text("API key configured")
                                            .foregroundColor(.green)
                                    }
                                }
                                .font(Theme.captionFont)
                                
                                Text("Get your free API key at [serpapi.com](https://serpapi.com)")
                                    .font(Theme.captionFont)
                                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                    .tint(Theme.textSecondary(for: effectiveColorScheme))
                            }
                        }
                    }
                    
                    // Data section
                    SettingsSection(title: "Data", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: { showClearDataConfirmation = true }) {
                                HStack {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                    Text("Clear All Data")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .font(Theme.titleFont)
                            }
                            .buttonStyle(.plain)
                            
                            Text("This will permanently delete all conversations, messages, file attachments, and RAG indexes. This cannot be undone.")
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                        }
                    }
                    
                    // About section
                    SettingsSection(title: "About", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Version")
                                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                Spacer()
                                Text("1.0.0")
                                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                            }
                            .font(Theme.captionFont)
                            
                            HStack {
                                Text("Built with")
                                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                Spacer()
                                Text("SwiftUI + FoundationModels")
                                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                            }
                            .font(Theme.captionFont)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 500)
        .background(Theme.background(for: effectiveColorScheme))
        .alert("Clear All Data?", isPresented: $showClearDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete:\n\n• All conversations\n• All messages\n• All file attachments\n• All RAG indexes\n\nThis action cannot be undone.")
        }
        .task {
            await loadAgents()
        }
    }
    
    private func clearAllData() {
        // Clear all database data, files, and RAG indexes
        Task {
            do {
                let service = try ConversationService()
                let conversations = try service.loadConversations()
                
                // Delete all conversations (this also deletes messages via cascade and files)
                for conversation in conversations {
                    try await service.deleteConversation(id: conversation.id)
                }
                
                // Clear all RAG indexes and SVDB data
                let ragService = RAGService.shared
                do {
                    // Clear all SVDB data (this clears everything including orphaned collections)
                    try await ragService.clearAllData()
                    Log.info("✅ Cleared all SVDB/RAG data")
                } catch {
                    Log.warn("⚠️ Warning: Could not clear all RAG data: \(error)")
                    // Fallback: try to clear per conversation
                    for conversation in conversations {
                        do {
                            try await ragService.deleteConversationIndexes(conversationId: conversation.id)
                        } catch {
                            Log.warn("⚠️ Warning: Could not delete RAG indexes for conversation \(conversation.id): \(error)")
                        }
                    }
                }
                
                // Clear all file attachments by deleting the entire base directory
                let fileManager = FileManager.default
                let fileManagerService = FileManagerService.shared
                let baseDir = await fileManagerService.getSandboxDirectory()
                
                // Delete entire base directory if it exists
                if fileManager.fileExists(atPath: baseDir.path) {
                    try fileManager.removeItem(at: baseDir)
                    // Recreate empty directory
                    try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
                    // Recreate empty directory
                    try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
                    Log.info("✅ Cleared file attachments directory")
                }
                
                // Clear LEANN Code Analysis index
                await LEANNBridgeService.shared.clearIndex()
                Log.info("✅ Cleared LEANN Code Analysis index")
                
                // Clear UI state in ChatViewModel
                await MainActor.run {
                    viewModel.conversations = []
                    viewModel.filteredConversations = []
                    viewModel.selectedConversationId = nil
                    viewModel.orchestrationStateByMessage = [:]
                    viewModel.agentNameByMessage = [:]
                }
                
                Log.info("✅ All data cleared successfully")
            } catch {
                Log.error("❌ Error clearing data: \(error)")
                // Show error to user
                await MainActor.run {
                    // Could add an error alert here if needed
                }
            }
            
            await MainActor.run {
                dismiss()
            }
        }
    }
    
    private func loadAgents() async {
        let service = AgentService.shared
        let agents = await service.getAvailableAgents()
        
        // Filter out Coordinator - it's not user-selectable
        let userSelectableAgents = agents.filter { $0.name != "Coordinator" }
        
        availableAgents = userSelectableAgents.map { agent in
            AgentInfo(
                id: agent.id,
                name: agent.name,
                description: agent.description,
                isCoordinator: false // Coordinator is filtered out, so this is always false
            )
        }
        
        // Initialize enabled agents if not set (first run)
        // We check for existence of the key directly because an empty string is a valid state (user disabled all agents)
        let hasInitializedAgents = UserDefaults.standard.object(forKey: UserDefaultsKey.enabledAgentNames) != nil
        
        if !hasInitializedAgents {
            // Check for legacy enabledAgentIds and migrate
            if !enabledAgentIdsJSON.isEmpty {
                // Migrate from IDs to names
                let oldIds = enabledAgentIdsJSON.split(separator: ",").map { String($0) }
                let enabledNames = userSelectableAgents.filter { agent in
                    oldIds.contains(agent.id.uuidString)
                }.map { $0.name }
                enabledAgentNamesJSON = enabledNames.joined(separator: ",")
                // Clear old key
                enabledAgentIdsJSON = ""
            } else {
                // Default: all agents enabled
                let allNames = userSelectableAgents.map { $0.name }
                enabledAgentNamesJSON = allNames.joined(separator: ",")
            }
        }
    }
    
    private func isAgentEnabled(_ id: UUID) -> Bool {
        // Find agent by ID to get its name
        guard let agent = availableAgents.first(where: { $0.id == id }) else {
            return false
        }
        let names = enabledAgentNamesJSON.split(separator: ",").map { String($0) }
        return names.contains(agent.name)
    }
    
    private func setAgentEnabled(_ id: UUID, enabled: Bool) {
        // Find agent by ID to get its name
        guard let agent = availableAgents.first(where: { $0.id == id }) else {
            return
        }
        var names = enabledAgentNamesJSON.split(separator: ",").map { String($0) }
        
        if enabled {
            if !names.contains(agent.name) {
                names.append(agent.name)
            }
        } else {
            names.removeAll { $0 == agent.name }
        }
        
        enabledAgentNamesJSON = names.joined(separator: ",")
    }
    
    private func validateAgentSelection() {
        let enabledCount = availableAgents.filter { isAgentEnabled($0.id) }.count
        
        if !useCoordinator && enabledCount > 1 {
            // Single-agent mode: Keep only the first enabled agent
            let enabledAgents = availableAgents.filter { isAgentEnabled($0.id) }
            if enabledAgents.first != nil {
                // Disable all except the first
                for agent in enabledAgents.dropFirst() {
                    setAgentEnabled(agent.id, enabled: false)
                }
            }
        }
    }
}

@available(macOS 26.0, *)
struct SettingsSection<Content: View>: View {
    let title: String
    let colorScheme: ColorScheme
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(Theme.textSecondary(for: colorScheme))
                .tracking(1)
            
            content
                .padding(16)
                .background(Theme.surface(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

@available(macOS 26.0, *)
private struct AgentsToolsSectionView: View {
    @Binding var useCoordinator: Bool
    @Binding var smartDelegation: Bool
    let availableAgents: [SettingsView.AgentInfo]
    let effectiveColorScheme: ColorScheme
    let isAgentEnabled: (UUID) -> Bool
    let setAgentEnabled: (UUID, Bool) -> Void
    let validateAgentSelection: () -> Void
    @Binding var codeAnalysisIndexingState: LEANNBridgeService.IndexingState
    @Binding var isIndexingCodebase: Bool
    
    var body: some View {
        SettingsSection(title: "Agents & Tools", colorScheme: effectiveColorScheme) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: Binding(
                    get: { useCoordinator },
                    set: { newValue in
                        useCoordinator = newValue
                        validateAgentSelection()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use Coordinator")
                            .font(Theme.titleFont)
                            .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                        Text(useCoordinator
                             ? "Coordinator-based orchestration (experimental)"
                             : "Direct single-agent conversations (recommended)")
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                    }
                }
                
                if useCoordinator {
                    Divider()
                        .background(Theme.border(for: effectiveColorScheme))
                    
                    Toggle(isOn: $smartDelegation) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Delegation")
                                .font(Theme.titleFont)
                                .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                            Text(smartDelegation
                                 ? "Coordinator decides when to delegate vs. respond directly (recommended)"
                                 : "Always delegate tasks to specialized agents")
                                .font(Theme.captionFont)
                                .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                        }
                    }
                }
                
                Divider()
                    .background(Theme.border(for: effectiveColorScheme))
                
                Text("Available Agents")
                    .font(Theme.titleFont)
                    .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                
                ForEach(availableAgents, id: \.id) { agent in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { isAgentEnabled(agent.id) },
                            set: { isOn in
                                setAgentEnabled(agent.id, isOn)
                                validateAgentSelection()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(agent.description)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                            }
                        }
                        
                        if agent.name == AgentName.codeAnalysis {
                            CodebasePickerInline(
                                isEnabled: isAgentEnabled(agent.id),
                                indexingState: $codeAnalysisIndexingState,
                                isIndexing: $isIndexingCodebase,
                                colorScheme: effectiveColorScheme
                            )
                        }
                    }
                }
                
                if !useCoordinator {
                    let enabledCount = availableAgents.filter { isAgentEnabled($0.id) }.count
                    if enabledCount == 0 {
                        Text("⚠️ Please select at least one agent")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    } else if enabledCount > 1 {
                        Text("ℹ️ Single-agent mode: Only the first selected agent will be used")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                            .padding(.top, 4)
                    }
                }
                
                if useCoordinator {
                    Text("Note: Coordinator is automatically included when orchestrator mode is enabled.")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Inline Codebase Picker for Code Analysis

@available(macOS 26.0, *)
struct CodebasePickerInline: View {
    let isEnabled: Bool
    @Binding var indexingState: LEANNBridgeService.IndexingState
    @Binding var isIndexing: Bool
    let colorScheme: ColorScheme
    
    @State private var showError = false
    @State private var errorMessage = ""
    @AppStorage(UserDefaultsKey.leannRootPath) private var leannRootPath: String = ""
    @State private var resolvedLeannRootPath: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status and actions row
            HStack(spacing: 12) {
                // Status indicator
                indexStatusView
                
                Spacer()
                
                // Select/Change button
                Button(action: selectCodebase) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 11))
                        Text(hasIndex ? "Change" : "Select Codebase")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(isEnabled ? Theme.accent(for: colorScheme) : Theme.textSecondary(for: colorScheme).opacity(0.5))
                .disabled(!isEnabled || isIndexing)
                
                // Clear button (only when indexed)
                if hasIndex && isEnabled {
                    Button(action: clearIndex) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.7))
                    .disabled(isIndexing)
                }
            }
            .padding(.leading, 28) // Indent to align with toggle label
            
            // Indexing progress
            if isIndexing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Indexing...")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
                .padding(.leading, 28)
            }
            
            Divider()
                .background(Theme.border(for: colorScheme))
                .padding(.leading, 28)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("LEANN Installation (Optional)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))

                if let resolvedLeannRootPath {
                    Text("Resolved: \(resolvedLeannRootPath)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                        .lineLimit(1)
                } else {
                    Text("Resolved: Not found")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                
                HStack(spacing: 8) {
                    TextField("Path to leann_poc directory", text: $leannRootPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .background(Theme.surfaceElevated(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Button("Choose…", action: selectLeannRoot)
                        .buttonStyle(.plain)
                        .foregroundColor(isEnabled ? Theme.accent(for: colorScheme) : Theme.textSecondary(for: colorScheme).opacity(0.5))
                        .disabled(!isEnabled)
                    
                    if !leannRootPath.isEmpty {
                        Button("Clear", action: clearLeannRoot)
                            .buttonStyle(.plain)
                            .foregroundColor(.red.opacity(0.7))
                            .disabled(!isEnabled)
                    }
                }
                
                Text("Overrides the bundled/default LEANN location if set.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
            }
            .padding(.leading, 28)
        }
        .opacity(isEnabled ? 1.0 : 0.5)
        .task {
            await loadIndexState()
            await loadLeannConfiguration()
        }
        .onChange(of: leannRootPath) { _, _ in
            Task {
                let service = LEANNBridgeService.shared
                await service.reloadConfiguration()
                await loadLeannConfiguration()
            }
        }
        .alert("Indexing Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var hasIndex: Bool {
        if case .indexed = indexingState {
            return true
        }
        return false
    }
    
    @ViewBuilder
    private var indexStatusView: some View {
        switch indexingState {
        case .notIndexed:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(isEnabled ? .orange : Theme.textSecondary(for: colorScheme))
                Text("No codebase indexed")
                    .font(.system(size: 10))
                    .foregroundColor(isEnabled ? .orange : Theme.textSecondary(for: colorScheme))
            }
            
        case .indexing(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text(progress)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
            }
            
        case .indexed(let fileCount, let path):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("\(fileCount) files")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                    .lineLimit(1)
            }
            
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
    
    private func loadIndexState() async {
        let service = LEANNBridgeService.shared
        indexingState = await service.indexingState
    }
    
    private func loadLeannConfiguration() async {
        let service = LEANNBridgeService.shared
        resolvedLeannRootPath = await service.getResolvedLeannRootPath()
    }
    
    private func selectCodebase() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your codebase directory"
        panel.prompt = "Index"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            Task {
                await indexCodebase(url: url)
            }
        }
    }
    
    private func indexCodebase(url: URL) async {
        isIndexing = true
        indexingState = .indexing(progress: "Indexing...")
        
        do {
            let service = LEANNBridgeService.shared
            let fileCount = try await service.indexCodebase(url: url)
            indexingState = .indexed(fileCount: fileCount, path: url.path)
        } catch {
            indexingState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isIndexing = false
    }
    
    private func clearIndex() {
        Task {
            let service = LEANNBridgeService.shared
            await service.clearIndex()
            indexingState = .notIndexed
        }
    }
    
    private func selectLeannRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the leann_poc directory"
        panel.prompt = "Choose"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            leannRootPath = url.path
        }
    }
    
    private func clearLeannRoot() {
        leannRootPath = ""
    }
}
