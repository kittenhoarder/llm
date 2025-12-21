//
//  AgentConfigurationView.swift
//  FoundationChatMac
//
//  View for configuring agent setup
//

import SwiftUI
import FoundationChatCore

@available(macOS 26.0, *)
struct AgentConfigurationView: View {
    @Binding var isPresented: Bool
    @State private var selectedAgents: Set<UUID> = []
    @State private var availableAgents: [AgentInfo] = []
    let conversationType: ConversationType
    let onConfigure: (AgentConfiguration) -> Void
    @AppStorage("preferredColorScheme") private var preferredColorScheme: String = "dark"
    @Environment(\.colorScheme) private var systemColorScheme
    
    struct AgentInfo: Identifiable {
        let id: UUID
        let name: String
        let description: String
        let capabilities: Set<AgentCapability>
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
                Text("Configure Agents")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                Button("Done") {
                    // Always use orchestrator pattern (coordinator)
                    let useCoordinator = UserDefaults.standard.bool(forKey: "useCoordinator")
                    let config = AgentConfiguration(
                        selectedAgents: Array(selectedAgents),
                        orchestrationPattern: useCoordinator ? .orchestrator : .orchestrator
                    )
                    onConfigure(config)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAgents.isEmpty && conversationType != .chat)
            }
            .padding()
            .background(Theme.surfaceElevated(for: effectiveColorScheme))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Available Agents")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(availableAgents) { agent in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { selectedAgents.contains(agent.id) },
                                set: { isOn in
                                    if isOn {
                                        selectedAgents.insert(agent.id)
                                    } else {
                                        selectedAgents.remove(agent.id)
                                    }
                                }
                            ))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(agent.description)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                                Text("Capabilities: \(agent.capabilities.map { $0.rawValue }.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Theme.surfaceElevated(for: effectiveColorScheme))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 500, height: 600)
        .background(Theme.surface(for: effectiveColorScheme))
        .task {
            await loadAgents()
        }
    }
    
    private func loadAgents() async {
        print("🔧 AgentConfigurationView: loadAgents() starting...")
        print("🔧 Using shared AgentService...")
        let service = AgentService.shared
        print("🔧 AgentService.shared obtained, calling getAvailableAgents()...")
        let agents = await service.getAvailableAgents()
        print("🔧 Got \(agents.count) agents")
        
        availableAgents = agents.map { agent in
            AgentInfo(
                id: agent.id,
                name: agent.name,
                description: agent.description,
                capabilities: agent.capabilities
            )
        }
        
        // Load enabled agents from settings as default selection
        let enabledIds = loadEnabledAgentIds()
        if !enabledIds.isEmpty {
            selectedAgents = Set(enabledIds)
        } else if conversationType == .singleAgent, let firstAgent = availableAgents.first {
            // Fallback: auto-select first agent for single agent mode
            selectedAgents = [firstAgent.id]
        }
    }
    
    private func loadEnabledAgentIds() -> [UUID] {
        guard let jsonString = UserDefaults.standard.string(forKey: "enabledAgentIds"),
              !jsonString.isEmpty else {
            return []
        }
        
        let idStrings = jsonString.split(separator: ",").map { String($0) }
        return idStrings.compactMap { UUID(uuidString: $0) }
    }
}





