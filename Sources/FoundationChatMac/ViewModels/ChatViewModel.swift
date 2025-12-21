//
//  ChatViewModel.swift
//  FoundationChatMac
//
//  View model for chat interface
//

import SwiftUI
import FoundationChatCore

@available(macOS 26.0, *)
@MainActor
public class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var filteredConversations: [Conversation] = []
    @Published var selectedConversationId: UUID?
    @Published var isLoading = false
    @Published var searchQuery = ""
    @Published var editingConversationId: UUID?
    @Published var showDeleteConfirmation = false
    @Published var conversationToDelete: UUID?
    
    private var modelService: ModelService?
    private let conversationService: ConversationService
    /// Use shared AgentService instance to prevent duplicate agent registration
    private var agentService: AgentService {
        return AgentService.shared
    }
    @AppStorage("useContextualConversations") private var useContextualConversations: Bool = true
    
    /// Get or create ModelService instance (async to avoid blocking)
    private func getModelService() async -> ModelService {
        if modelService == nil {
            print("📱 Creating ModelService in detached task...")
            // Create ModelService off the main thread to avoid blocking
            modelService = await Task.detached(priority: .userInitiated) {
                print("📱 ModelService creation starting in detached task...")
                let service = ModelService()
                print("✅ ModelService created in detached task")
                return service
            }.value
            print("✅ ModelService created and assigned")
        }
        return modelService!
    }
    
    var currentConversation: Conversation? {
        guard let id = selectedConversationId else { return nil }
        return conversations.first { $0.id == id }
    }
    
    var displayedConversations: [Conversation] {
        searchQuery.isEmpty ? conversations : filteredConversations
    }
    
    init() {
        print("📱 ========================================")
        print("📱 ChatViewModel init() CALLED")
        print("📱 Thread: \(Thread.isMainThread ? "Main" : "Background")")
        print("📱 ========================================")
        
        // Initialize conversation service - this might be blocking
        var service: ConversationService?
        do {
            print("📱 Step 1: About to create ConversationService...")
            print("📱 Step 1.1: Calling ConversationService()...")
            service = try ConversationService()
            print("✅ Step 3: ConversationService() returned successfully")
        } catch {
            print("❌ Failed to initialize ConversationService: \(error)")
            print("   Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                print("   UserInfo: \(nsError.userInfo)")
            }
            
            // Try with a temp path as fallback
            do {
                print("📱 Trying temp path fallback...")
                let tempDir = FileManager.default.temporaryDirectory
                let tempDB = tempDir.appendingPathComponent("foundationchat_temp.db")
                service = try ConversationService(dbPath: tempDB.path)
                print("✅ ConversationService created with temp path")
            } catch let fallbackError {
                print("❌ Failed even with temp path: \(fallbackError)")
                print("   Fallback error: \(fallbackError.localizedDescription)")
                // Use fatalError to see the actual error
                fatalError("Failed to initialize ConversationService: \(error). Fallback also failed: \(fallbackError)")
            }
        }
        
        print("📱 Step 4: Checking if service is nil...")
        guard let finalService = service else {
            print("❌ Service is nil!")
            fatalError("ConversationService is nil after initialization")
        }
        
        print("📱 Step 5: Assigning conversationService...")
        self.conversationService = finalService
        print("✅ Step 6: ChatViewModel init complete")
        print("📱 Step 7: Starting async loadConversations task...")
        
        // Load conversations asynchronously to avoid blocking UI
        Task { @MainActor in
            print("📱 Step 8: Inside loadConversations task...")
            await loadConversations()
            print("✅ Step 9: Conversations loaded")
        }
        
        print("📱 Step 10: ChatViewModel init returning...")
    }
    
    // MARK: - Conversation Loading
    
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
    
    // MARK: - Conversation Creation
    
    func createNewConversation() async {
        do {
            var conversation = try conversationService.createConversation()
            conversation.conversationType = .singleAgent
            
            // Load enabled agents from settings (user-selectable agents only)
            var enabledAgentIds = await loadEnabledAgentIds()
            
            // Debug logging
            await DebugLogger.shared.log(
                location: "ChatViewModel.swift:createNewConversation",
                message: "Starting conversation creation",
                hypothesisId: "C",
                data: [
                    "loadedAgentIds": enabledAgentIds.map { $0.uuidString },
                    "loadedCount": enabledAgentIds.count
                ]
            )
            
            // Get useCoordinator setting
            let useCoordinator = UserDefaults.standard.object(forKey: UserDefaultsKey.useCoordinator) as? Bool ?? false
            
            // Validation based on mode
            if useCoordinator {
                // Orchestrator mode: Require at least one specialized agent
                if enabledAgentIds.isEmpty {
                    // Default to all user-selectable agents
                    let agents = await agentService.getAvailableAgents()
                    let userSelectableAgents = agents.filter { $0.name != AgentName.coordinator }
                    enabledAgentIds = userSelectableAgents.map { $0.id }
                    // Store agent names, not IDs, so they persist across app restarts
                    let allNames = userSelectableAgents.map { $0.name }
                    UserDefaults.standard.set(allNames.joined(separator: ","), forKey: "enabledAgentNames")
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKey.enabledAgentIds)
                }
                
                // Automatically include Coordinator agent
                let allAgents = await agentService.getAvailableAgents()
                if let coordinator = allAgents.first(where: { $0.name == AgentName.coordinator }) {
                    if !enabledAgentIds.contains(coordinator.id) {
                        enabledAgentIds.append(coordinator.id)
                    }
                }
            } else {
                // Single-agent mode: Require exactly one agent
                if enabledAgentIds.isEmpty {
                    // Default to first available agent
                    let agents = await agentService.getAvailableAgents()
                    let userSelectableAgents = agents.filter { $0.name != AgentName.coordinator }
                    
                    // Debug logging
                    await DebugLogger.shared.log(
                        location: "ChatViewModel.swift:createNewConversation",
                        message: "Getting available agents for default selection",
                        hypothesisId: "C",
                        data: [
                            "allAgents": agents.map { ["id": $0.id.uuidString, "name": $0.name] },
                            "userSelectableAgents": userSelectableAgents.map { ["id": $0.id.uuidString, "name": $0.name] },
                            "firstAgentId": userSelectableAgents.first?.id.uuidString ?? "nil",
                            "firstAgentName": userSelectableAgents.first?.name ?? "nil"
                        ]
                    )
                    
                    if let firstAgent = userSelectableAgents.first {
                        enabledAgentIds = [firstAgent.id]
                        // Store agent name, not ID, so it persists across app restarts
                        UserDefaults.standard.set(firstAgent.name, forKey: "enabledAgentNames")
                        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.enabledAgentIds)
                        
                        // Debug logging
                        await DebugLogger.shared.log(
                            location: "ChatViewModel.swift:createNewConversation",
                            message: "Selected default agent and saved to UserDefaults",
                            hypothesisId: "C",
                            data: [
                                "selectedAgentId": firstAgent.id.uuidString,
                                "selectedAgentName": firstAgent.name,
                                "savedToUserDefaults": firstAgent.id.uuidString
                            ]
                        )
                    } else {
                        throw NSError(domain: "ChatViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No agents available"])
                    }
                } else if enabledAgentIds.count > 1 {
                    // Single-agent mode: Use only the first selected agent
                    enabledAgentIds = [enabledAgentIds[0]]
                }
            }
            
            // Debug logging
            await DebugLogger.shared.log(
                location: "ChatViewModel.swift:createNewConversation",
                message: "Creating conversation with agent configuration",
                hypothesisId: "A",
                data: [
                    "conversationId": conversation.id.uuidString,
                    "enabledAgentIds": enabledAgentIds.map { $0.uuidString },
                    "useCoordinator": useCoordinator,
                    "agentCount": enabledAgentIds.count
                ]
            )
            
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
        if let idsString = UserDefaults.standard.string(forKey: UserDefaultsKey.enabledAgentIds),
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
                let names = validAgents.filter { $0.name != AgentName.coordinator }.map { $0.name }
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
        let userSelectableAgents = allAgents.filter { $0.name != AgentName.coordinator }
        
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
    
    // MARK: - Conversation Deletion
    
    func requestDeleteConversation(_ id: UUID) {
        conversationToDelete = id
        showDeleteConfirmation = true
    }
    
    func confirmDeleteConversation() async {
        guard let id = conversationToDelete else { return }
        
        // Clear the session for this conversation
        let service = await getModelService()
        await service.clearSession(for: id)
        
        do {
            // Use Task.detached and create a new ConversationService instance
            // to avoid sending main actor-isolated conversationService across isolation boundaries
            try await Task.detached {
                let service = try ConversationService()
                try await service.deleteConversation(id: id)
            }.value
            conversations.removeAll { $0.id == id }
            
            // Select another conversation if we deleted the current one
            if selectedConversationId == id {
                selectedConversationId = conversations.first?.id
            }
        } catch {
            print("Error deleting conversation: \(error)")
        }
        
        conversationToDelete = nil
        showDeleteConfirmation = false
    }
    
    func cancelDeleteConversation() {
        conversationToDelete = nil
        showDeleteConfirmation = false
    }
    
    // MARK: - Conversation Renaming
    
    func startRenaming(_ id: UUID) {
        editingConversationId = id
    }
    
    func finishRenaming(_ id: UUID, newTitle: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            editingConversationId = nil
            return
        }
        
        conversations[index].title = trimmedTitle
        conversations[index].updatedAt = Date()
        
        do {
            try conversationService.updateConversation(conversations[index])
        } catch {
            print("Error renaming conversation: \(error)")
        }
        
        editingConversationId = nil
    }
    
    func cancelRenaming() {
        editingConversationId = nil
    }
    
    // MARK: - Search
    
    func searchConversations(_ query: String) {
        searchQuery = query
        if query.isEmpty {
            filteredConversations = []
        } else {
            do {
                filteredConversations = try conversationService.searchConversations(query: query)
            } catch {
                print("Error searching conversations: \(error)")
                filteredConversations = []
            }
        }
    }
    
    // MARK: - Message Sending
    
    func sendMessage(_ text: String, attachments: [FileAttachment] = []) async {
        guard let conversationId = selectedConversationId else {
            await createNewConversation()
            guard let newId = selectedConversationId else { return }
            await sendMessageToConversation(text, attachments: attachments, conversationId: newId)
            return
        }
        
        await sendMessageToConversation(text, attachments: attachments, conversationId: conversationId)
    }
    
    private func sendMessageToConversation(_ text: String, attachments: [FileAttachment], conversationId: UUID) async {
        isLoading = true
        
        let userMessage = Message(role: .user, content: text, attachments: attachments)
        
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[index].messages.append(userMessage)
            do {
                try conversationService.addMessage(userMessage, to: conversationId)
            } catch {
                print("Error saving user message: \(error)")
            }
        }
        
        let startTime = Date()
        do {
            // Check if this is an agent conversation
            let conversation = conversations.first(where: { $0.id == conversationId })
            let isAgentConversation = conversation?.conversationType != .chat && conversation?.agentConfiguration != nil
            
            let response: ModelResponse
            if isAgentConversation, let conv = conversation, let config = conv.agentConfiguration {
                // Check useCoordinator setting to determine routing
                let useCoordinator = UserDefaults.standard.object(forKey: UserDefaultsKey.useCoordinator) as? Bool ?? false
                
                if useCoordinator && config.orchestrationPattern == .orchestrator {
                    // Orchestrator mode: Use AgentService with orchestrator pattern
                    print("🤖 Using orchestrator mode for message processing...")
                let service = agentService
                print("🤖 AgentService obtained, calling processMessage()...")
                let result = try await service.processMessage(text, conversationId: conversationId, conversation: conv)
                print("✅ AgentService.processMessage() completed")
                response = ModelResponse(content: result.content, toolCalls: result.toolCalls)
                } else if let singleAgentId = config.selectedAgents.first, config.selectedAgents.count == 1 {
                    // Single-agent mode: Use direct agent processing (no orchestrator)
                    print("🤖 Using single-agent mode for message processing...")
                    
                    // Debug logging
                    await DebugLogger.shared.log(
                        location: "ChatViewModel.swift:sendMessageToConversation",
                        message: "Routing to single-agent processing",
                        hypothesisId: "A",
                        data: [
                            "conversationId": conversationId.uuidString,
                            "singleAgentId": singleAgentId.uuidString,
                            "configSelectedAgents": config.selectedAgents.map { $0.uuidString },
                            "configSelectedCount": config.selectedAgents.count,
                            "useCoordinator": useCoordinator,
                            "orchestrationPattern": config.orchestrationPattern.rawValue
                        ]
                    )
                    
                    let service = agentService
                    print("🤖 AgentService obtained, calling processSingleAgentMessage()...")
                    // Extract file references from attachments
                    let fileReferences = attachments.map { $0.sandboxPath }
                    let result = try await service.processSingleAgentMessage(text, agentId: singleAgentId, conversationId: conversationId, conversation: conv, fileReferences: fileReferences)
                    print("✅ AgentService.processSingleAgentMessage() completed")
                    response = ModelResponse(content: result.content, toolCalls: result.toolCalls)
                } else {
                    // Fallback: Use regular ModelService
                    print("💬 Falling back to regular ModelService for message processing...")
                    let previousMessages: [Message]
                    if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                        previousMessages = Array(conversations[index].messages.dropLast())
                    } else {
                        previousMessages = []
                    }
                    let service = await getModelService()
                    response = try await service.respond(
                        to: text,
                        conversationId: conversationId,
                        previousMessages: previousMessages,
                        useContextual: useContextualConversations
                    )
                }
            } else {
                print("💬 Using regular ModelService for message processing...")
                // Get previous messages for contextual mode
                let previousMessages: [Message]
                if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                    // Get all messages except the one we just added
                    previousMessages = Array(conversations[index].messages.dropLast())
                } else {
                    previousMessages = []
                }
                
                print("💬 Getting ModelService (async)...")
                let service = await getModelService()
                print("💬 ModelService obtained, calling respond()...")
                response = try await service.respond(
                    to: text,
                    conversationId: conversationId,
                    previousMessages: previousMessages,
                    useContextual: useContextualConversations
                )
            }
            
            let responseTime = Date().timeIntervalSince(startTime)
            let assistantMessage = Message(
                role: .assistant,
                content: response.content,
                toolCalls: response.toolCalls,
                responseTime: responseTime
            )
            
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index].messages.append(assistantMessage)
                conversations[index].updatedAt = Date()
                
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
            let responseTime = Date().timeIntervalSince(startTime)
            let friendlyMessage = Self.friendlyErrorMessage(for: error)
            let errorMessage = Message(role: .assistant, content: friendlyMessage, responseTime: responseTime)
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index].messages.append(errorMessage)
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Message Actions
    
    func regenerateLastResponse() async {
        guard let conversationId = selectedConversationId,
              let index = conversations.firstIndex(where: { $0.id == conversationId }),
              conversations[index].messages.count >= 2 else { return }
        
        // Find the last user message
        guard let lastUserMessageIndex = conversations[index].messages.lastIndex(where: { $0.role == .user }) else { return }
        let lastUserMessage = conversations[index].messages[lastUserMessageIndex]
        
        // Remove all messages after the last user message
        conversations[index].messages = Array(conversations[index].messages.prefix(lastUserMessageIndex + 1))
        
        // Regenerate
        isLoading = true
        let startTime = Date()
        do {
            // Get previous messages for contextual mode (up to but not including the last user message)
            let previousMessages = Array(conversations[index].messages.prefix(lastUserMessageIndex))
            
            let service = await getModelService()
            let response = try await service.respond(
                to: lastUserMessage.content,
                conversationId: conversationId,
                previousMessages: previousMessages,
                useContextual: useContextualConversations
            )
            let responseTime = Date().timeIntervalSince(startTime)
            let assistantMessage = Message(
                role: .assistant,
                content: response.content,
                toolCalls: response.toolCalls,
                responseTime: responseTime
            )
            
            conversations[index].messages.append(assistantMessage)
            conversations[index].updatedAt = Date()
            
            try conversationService.updateConversation(conversations[index])
            try conversationService.addMessage(assistantMessage, to: conversationId)
        } catch {
            print("Error regenerating response: \(error)")
            let responseTime = Date().timeIntervalSince(startTime)
            let errorMessage = Message(role: .assistant, content: "Error: \(error.localizedDescription)", responseTime: responseTime)
            conversations[index].messages.append(errorMessage)
        }
        isLoading = false
    }
    
    func clearConversation() async {
        guard let conversationId = selectedConversationId,
              let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        
        conversations[index].messages = []
        conversations[index].updatedAt = Date()
        conversations[index].title = "New Conversation"
        
        // Clear the session for this conversation
        let service = await getModelService()
        await service.clearSession(for: conversationId)
        
        do {
            try conversationService.updateConversation(conversations[index])
        } catch {
            print("Error clearing conversation: \(error)")
        }
    }
    
    func copyMessageContent(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    // MARK: - Error Handling
    
    private static func friendlyErrorMessage(for error: Error) -> String {
        let description = error.localizedDescription.lowercased()
        
        if description.contains("unsafe") || description.contains("safety") || description.contains("content") {
            return "This request couldn't be completed. Try rephrasing your message."
        } else if description.contains("unavailable") || description.contains("not ready") {
            return "Apple Intelligence is currently unavailable. Please try again later."
        } else if description.contains("network") || description.contains("connection") {
            return "Connection issue. Please check your network and try again."
        } else {
            return "Something went wrong. Please try again."
        }
    }
}
