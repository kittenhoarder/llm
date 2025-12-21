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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("fontSizeAdjustment") private var fontSizeAdjustment: Double = 14
    @AppStorage("preferredColorScheme") private var preferredColorScheme: String = "dark"
    @AppStorage("useContextualConversations") private var useContextualConversations: Bool = true
    @AppStorage("serpapiApiKey") private var serpapiApiKey: String = ""
    @AppStorage("enabledAgentNames") private var enabledAgentNamesJSON: String = ""
    // Legacy support: also check old enabledAgentIds key for migration
    @AppStorage("enabledAgentIds") private var enabledAgentIdsJSON: String = ""
    @AppStorage("useCoordinator") private var useCoordinator: Bool = true
    @AppStorage("smartDelegation") private var smartDelegation: Bool = true
    @AppStorage("useRAG") private var useRAG: Bool = true
    @AppStorage("ragChunkSize") private var ragChunkSize: Int = 1000
    @AppStorage("ragTopK") private var ragTopK: Int = 5
    @State private var showClearDataConfirmation = false
    @State private var availableAgents: [AgentInfo] = []
    
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
                    
                    // Agents & Tools section
                    SettingsSection(title: "Agents & Tools", colorScheme: effectiveColorScheme) {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle(isOn: Binding(
                                get: { useCoordinator },
                                set: { newValue in
                                    useCoordinator = newValue
                                    // Validate agent selection when toggling
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
                            
                            // Smart Delegation toggle (only shown when coordinator is enabled)
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
                            
                            ForEach(availableAgents) { agent in
                                Toggle(isOn: Binding(
                                    get: { isAgentEnabled(agent.id) },
                                    set: { isOn in
                                        setAgentEnabled(agent.id, enabled: isOn)
                                        // Validate after change
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
                            }
                            
                            // Validation message
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
                                    Text("Clear All Conversations")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .font(Theme.titleFont)
                            }
                            .buttonStyle(.plain)
                            
                            Text("This will permanently delete all conversations and messages.")
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
            Text("All conversations will be permanently deleted. This cannot be undone.")
        }
        .task {
            await loadAgents()
        }
    }
    
    private func clearAllData() {
        // Clear the database by reinitializing
        Task {
            do {
                let service = try ConversationService()
                let conversations = try service.loadConversations()
                for conversation in conversations {
                    try await service.deleteConversation(id: conversation.id)
                }
            } catch {
                print("Error clearing data: \(error)")
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
        
        // Initialize enabled agents if empty (default: all user-selectable agents enabled)
        // Store agent names, not IDs, so they persist across app restarts
        if enabledAgentNamesJSON.isEmpty {
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

