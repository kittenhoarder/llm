//
//  ChatViewModel.swift
//  FoundationChatiOS
//
//  View model for chat interface (shared with macOS)
//

import SwiftUI
import FoundationChatCore

@available(iOS 26.0, *)
@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversationId: UUID?
    @Published var isLoading = false
    
    private let modelService = ModelService()
    private let conversationService: ConversationService
    private let agentService = AgentService()
    
    var currentConversation: Conversation? {
        guard let id = selectedConversationId else { return nil }
        return conversations.first { $0.id == id }
    }
    
    init() {
        do {
            self.conversationService = try ConversationService()
        } catch {
            fatalError("Failed to initialize ConversationService: \(error)")
        }
    }
    
    func loadConversations() async {
        do {
            conversations = try conversationService.loadConversations()
            if selectedConversationId == nil, let first = conversations.first {
                selectedConversationId = first.id
            }
        } catch {
            print("Error loading conversations: \(error)")
        }
    }
    
    func createNewConversation() async {
        do {
            var conversation = try conversationService.createConversation()
            conversation.conversationType = .singleAgent
            
            // Load enabled agents from settings (user-selectable agents only)
            var enabledAgentIds = await loadEnabledAgentIds()
            
            // Get useCoordinator setting
            let useCoordinator = UserDefaults.standard.object(forKey: "useCoordinator") as? Bool ?? false
            
            // Validation based on mode
            if useCoordinator {
                // Orchestrator mode: Require at least one specialized agent
                if enabledAgentIds.isEmpty {
                    // Default to all user-selectable agents
                    let agents = await agentService.getAvailableAgents()
                    let userSelectableAgents = agents.filter { $0.name != "Coordinator" }
                    enabledAgentIds = userSelectableAgents.map { $0.id }
                    // Store agent names, not IDs, so they persist across app restarts
                    let allNames = userSelectableAgents.map { $0.name }
                    UserDefaults.standard.set(allNames.joined(separator: ","), forKey: "enabledAgentNames")
                    UserDefaults.standard.removeObject(forKey: "enabledAgentIds")
                }
                
                // Automatically include Coordinator agent
                let allAgents = await agentService.getAvailableAgents()
                if let coordinator = allAgents.first(where: { $0.name == "Coordinator" }) {
                    if !enabledAgentIds.contains(coordinator.id) {
                        enabledAgentIds.append(coordinator.id)
                    }
                }
            } else {
                // Single-agent mode: Require exactly one agent
                if enabledAgentIds.isEmpty {
                    // Default to first available agent
                    let agents = await agentService.getAvailableAgents()
                    let userSelectableAgents = agents.filter { $0.name != "Coordinator" }
                    if let firstAgent = userSelectableAgents.first {
                        enabledAgentIds = [firstAgent.id]
                        // Store agent name, not ID, so it persists across app restarts
                        UserDefaults.standard.set(firstAgent.name, forKey: "enabledAgentNames")
                        UserDefaults.standard.removeObject(forKey: "enabledAgentIds")
                    } else {
                        throw NSError(domain: "ChatViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No agents available"])
                    }
                } else if enabledAgentIds.count > 1 {
                    // Single-agent mode: Use only the first selected agent
                    enabledAgentIds = [enabledAgentIds[0]]
                }
            }
            
            // Create agent configuration from settings
            let config = AgentConfiguration(
                selectedAgents: enabledAgentIds,
                orchestrationPattern: .orchestrator, // Pattern type, but routing logic checks useCoordinator
                agentSettings: [:]
            )
            conversation.agentConfiguration = config
            
            conversations.insert(conversation, at: 0)
            selectedConversationId = conversation.id
            
            try conversationService.updateConversation(conversation)
        } catch {
            print("Error creating conversation: \(error)")
        }
    }
    
    /// Load enabled agent IDs from UserDefaults
    /// Resolves agent names to current agent IDs (handles ID changes on app restart)
    private func loadEnabledAgentIds() async -> [UUID] {
        // Try to load agent names first (new approach)
        if let namesString = UserDefaults.standard.string(forKey: "enabledAgentNames"),
           !namesString.isEmpty {
            let agentNames = namesString.split(separator: ",").map { String($0) }
            
            // Resolve names to current agent IDs
            return await resolveAgentNamesToIds(agentNames: agentNames)
        }
        
        // Legacy: Try to load agent IDs (for migration)
        if let idsString = UserDefaults.standard.string(forKey: "enabledAgentIds"),
           !idsString.isEmpty {
            let idStrings = idsString.split(separator: ",").map { String($0) }
            let loadedIds = idStrings.compactMap { UUID(uuidString: $0) }
            
            // Validate these IDs against current agents
            let currentAgents = await agentService.getAvailableAgents()
            let validIds = loadedIds.filter { id in
                currentAgents.contains { $0.id == id }
            }
            
            // If some IDs are invalid, migrate to names
            if validIds.count < loadedIds.count {
                let validAgents = currentAgents.filter { validIds.contains($0.id) }
                let names = validAgents.filter { $0.name != "Coordinator" }.map { $0.name }
                UserDefaults.standard.set(names.joined(separator: ","), forKey: "enabledAgentNames")
                UserDefaults.standard.removeObject(forKey: "enabledAgentIds")
                return await resolveAgentNamesToIds(agentNames: names)
            }
            
            return validIds
        }
        
        // No settings found - return empty (will be set on first conversation creation)
        return []
    }
    
    /// Resolve agent names to current agent IDs
    private func resolveAgentNamesToIds(agentNames: [String]) async -> [UUID] {
        let allAgents = await agentService.getAvailableAgents()
        let userSelectableAgents = allAgents.filter { $0.name != "Coordinator" }
        
        var resolvedIds: [UUID] = []
        for name in agentNames {
            if let agent = userSelectableAgents.first(where: { $0.name == name }) {
                resolvedIds.append(agent.id)
            }
        }
        
        return resolvedIds
    }
    
    // Deprecated: Use createNewConversation instead
    func createAgentConversation(type: ConversationType, configuration: AgentConfiguration?) async {
        do {
            var conversation = try conversationService.createConversation()
            conversation.conversationType = type
            conversation.agentConfiguration = configuration
            
            conversations.insert(conversation, at: 0)
            selectedConversationId = conversation.id
            
            try conversationService.updateConversation(conversation)
        } catch {
            print("Error creating agent conversation: \(error)")
        }
    }
    
    func configureAgents(for conversationId: UUID, configuration: AgentConfiguration) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }
        
        conversations[index].agentConfiguration = configuration
        
        do {
            try conversationService.updateConversation(conversations[index])
        } catch {
            print("Error updating agent configuration: \(error)")
        }
    }
    
    func sendMessage(_ text: String) async {
        guard let conversationId = selectedConversationId else {
            // Create new conversation if none selected
            await createNewConversation()
            guard let newId = selectedConversationId else { return }
            await sendMessageToConversation(text, conversationId: newId)
            return
        }
        
        await sendMessageToConversation(text, conversationId: conversationId)
    }
    
    private func sendMessageToConversation(_ text: String, conversationId: UUID) async {
        isLoading = true
        
        // Create user message
        let userMessage = Message(role: .user, content: text)
        
        // Add to conversation
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index].messages.append(userMessage)
            do {
                try conversationService.addMessage(userMessage, to: conversationId)
            } catch {
                print("Error saving user message: \(error)")
            }
        }
        
        // Get response - use agent service if this is an agent conversation
        let assistantMessage: Message
        do {
            if let conversation = conversations.first(where: { $0.id == conversationId }),
               conversation.conversationType != .chat,
               let config = conversation.agentConfiguration {
                // Check useCoordinator setting to determine routing
                let useCoordinator = UserDefaults.standard.object(forKey: "useCoordinator") as? Bool ?? false
                
                let result: AgentResult
                if useCoordinator && config.orchestrationPattern == .orchestrator {
                    // Orchestrator mode: Use AgentService with orchestrator pattern
                    print("🤖 Using orchestrator mode for message processing...")
                    result = try await agentService.processMessage(text, conversationId: conversationId, conversation: conversation)
                } else if let singleAgentId = config.selectedAgents.first, config.selectedAgents.count == 1 {
                    // Single-agent mode: Use direct agent processing (no orchestrator)
                    print("🤖 Using single-agent mode for message processing...")
                    result = try await agentService.processSingleAgentMessage(text, agentId: singleAgentId, conversationId: conversationId, conversation: conversation)
                } else {
                    // Fallback: Use regular ModelService
                    print("💬 Falling back to regular ModelService for message processing...")
                    let response = try await modelService.respond(to: text)
                    assistantMessage = Message(role: .assistant, content: response.content, toolCalls: response.toolCalls)
                    // Add to conversation
                    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                        conversations[index].messages.append(assistantMessage)
                        conversations[index].updatedAt = Date()
                        
                        // Generate title if this is the first message
                        if conversations[index].messages.count == 2 {
                            conversations[index].generateTitle()
                        }
                        
                        do {
                            try conversationService.addMessage(assistantMessage, to: conversationId)
                            try conversationService.updateConversation(conversations[index])
                        } catch {
                            print("Error saving assistant message: \(error)")
                        }
                    }
                    isLoading = false
                    return
                }
                
                assistantMessage = Message(
                    role: .assistant,
                    content: result.content,
                    toolCalls: result.toolCalls
                )
            } else {
                // Use regular model service
                let response = try await modelService.respond(to: text)
                assistantMessage = Message(role: .assistant, content: response.content, toolCalls: response.toolCalls)
            }
            
            // Add to conversation
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index].messages.append(assistantMessage)
                conversations[index].updatedAt = Date()
                
                // Generate title if this is the first message
                if conversations[index].messages.count == 2 {
                    conversations[index].generateTitle()
                }
                
                do {
                    try conversationService.addMessage(assistantMessage, to: conversationId)
                    try conversationService.updateConversation(conversations[index])
                } catch {
                    print("Error saving assistant message: \(error)")
                }
            }
        } catch {
            print("Error getting model response: \(error)")
            // Show error message
            let errorMessage = Message(role: .assistant, content: "Error: \(error.localizedDescription)")
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index].messages.append(errorMessage)
            }
        }
        
        isLoading = false
    }
}


