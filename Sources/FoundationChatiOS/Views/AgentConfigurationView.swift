//
//  AgentConfigurationView.swift
//  FoundationChatiOS
//
//  View for configuring agent setup
//

import SwiftUI
import FoundationChatCore

@available(iOS 26.0, *)
struct AgentConfigurationView: View {
    @Binding var isPresented: Bool
    @State private var selectedAgents: Set<UUID> = []
    @State private var availableAgents: [AgentInfo] = []
    let conversationType: ConversationType
    let onConfigure: (AgentConfiguration) -> Void
    
    struct AgentInfo: Identifiable {
        let id: UUID
        let name: String
        let description: String
        let capabilities: Set<AgentCapability>
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Available Agents") {
                    ForEach(availableAgents) { agent in
                        Toggle(isOn: Binding(
                            get: { selectedAgents.contains(agent.id) },
                            set: { isOn in
                                if isOn {
                                    selectedAgents.insert(agent.id)
                                } else {
                                    selectedAgents.remove(agent.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name)
                                    .font(.headline)
                                Text(agent.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Capabilities: \(agent.capabilities.map { $0.rawValue }.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Configure Agents")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
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
                    .disabled(selectedAgents.isEmpty && conversationType != .chat)
                }
            }
            .task {
                await loadAgents()
            }
        }
    }
    
    private func loadAgents() async {
        let service = AgentService()
        let agents = await service.getAvailableAgents()
        
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


