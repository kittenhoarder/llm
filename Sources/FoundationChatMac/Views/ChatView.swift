//
//  ChatView.swift
//  FoundationChatMac
//
//  Main chat interface with minimal dark theme
//

import SwiftUI
import AppKit
import FoundationChatCore
import UniformTypeIdentifiers

@available(macOS 26.0, *)
public struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var pendingAttachments: [FileAttachment] = []
    @FocusState private var isInputFocused: Bool
    @AppStorage("fontSizeAdjustment") private var fontSizeAdjustment: Double = 14
    @AppStorage("useContextualConversations") private var useContextualConversations: Bool = true
    @AppStorage("preferredColorScheme") private var preferredColorScheme: String = "dark"
    @Environment(\.colorScheme) private var systemColorScheme
    
    private var effectiveColorScheme: ColorScheme {
        switch preferredColorScheme {
        case "light": return .light
        case "dark": return .dark
        case "system": return systemColorScheme
        default: return .dark
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            conversationContent
            inputArea
        }
        .background(Theme.background(for: effectiveColorScheme))
        .navigationTitle(viewModel.currentConversation?.title ?? "New Chat")
    }
    
    @ViewBuilder
    private var conversationContent: some View {
        if let conversation = viewModel.currentConversation, !conversation.messages.isEmpty {
            messagesScrollView(conversation: conversation)
        } else {
            EmptyConversationView(colorScheme: effectiveColorScheme, onNewChat: {
                isInputFocused = true
            })
        }
    }
    
    private func messagesScrollView(conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(conversation.messages.enumerated()), id: \.element.id) { index, message in
                        messageRow(
                            message: message,
                            index: index,
                            totalCount: conversation.messages.count,
                            conversation: conversation
                        )
                        .id(message.id)
                    }
                    
                    if viewModel.isLoading {
                        LoadingIndicator(colorScheme: effectiveColorScheme)
                        
                        // Show orchestration diagram during execution (before assistant message exists)
                        if let orchestrationState = viewModel.orchestrationState {
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.showOrchestrationDiagram.toggle()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "flowchart")
                                            .font(.system(size: 11))
                                        Text(viewModel.showOrchestrationDiagram ? "Hide Orchestration" : "Show Orchestration")
                                            .font(.system(size: 11))
                                    }
                                    .foregroundColor(Theme.accent(for: effectiveColorScheme))
                                }
                                .buttonStyle(.plain)
                                
                                if viewModel.showOrchestrationDiagram || !orchestrationState.isComplete {
                                    OrchestrationDiagramView(state: orchestrationState, colorScheme: effectiveColorScheme)
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                                            removal: .opacity.combined(with: .move(edge: .top))
                                        ))
                                }
                            }
                            .padding(.top, 8)
                            .padding(.leading, 60) // Align with assistant messages
                            .onAppear {
                                // Auto-expand diagram when orchestration is active
                                if !orchestrationState.isComplete && !viewModel.showOrchestrationDiagram {
                                    viewModel.showOrchestrationDiagram = true
                                }
                            }
                            .onChange(of: orchestrationState.currentPhase) { oldPhase, newPhase in
                                // Auto-show when orchestration starts or phase changes
                                if newPhase != .complete && newPhase != .failed {
                                    if !viewModel.showOrchestrationDiagram {
                                        viewModel.showOrchestrationDiagram = true
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Theme.background(for: effectiveColorScheme))
            .onChange(of: conversation.messages.count) {
                if let lastMessage = conversation.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func messageRow(
        message: Message,
        index: Int,
        totalCount: Int,
        conversation: Conversation
    ) -> some View {
        let isLastMessage = index == totalCount - 1
        let storedOrchestrationState = viewModel.orchestrationStateByMessage[message.id]
        
        MessageView(
            message: message,
            isLastMessage: isLastMessage,
            conversationMessages: conversation.messages,
            fontSize: fontSizeAdjustment,
            useContextual: useContextualConversations,
            colorScheme: effectiveColorScheme,
            storedOrchestrationState: storedOrchestrationState,
            agentName: viewModel.agentNameByMessage[message.id],
            viewModel: viewModel,
            onCopy: { viewModel.copyMessageContent(message.content) },
            onRegenerate: message.role == .assistant && isLastMessage ? {
                Task { await viewModel.regenerateLastResponse() }
            } : nil
        )
    }
    
    private var inputArea: some View {
        InputArea(
            messageText: $messageText,
            pendingAttachments: $pendingAttachments,
            isInputFocused: $isInputFocused,
            isLoading: viewModel.isLoading,
            fontSize: fontSizeAdjustment,
            colorScheme: effectiveColorScheme,
            onSend: sendMessage,
            conversationId: viewModel.selectedConversationId
        )
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        
        // Clear input
        messageText = ""
        pendingAttachments = []
        
        Task {
            await viewModel.sendMessage(text, attachments: attachments)
        }
    }
}

// MARK: - Custom Scroll View with Dynamic Height

@available(macOS 26.0, *)
class CustomScrollView: NSView {
    let scrollView: NSScrollView
    let minHeight: CGFloat
    let maxHeight: CGFloat
    var currentHeight: CGFloat = 40 {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
    
    init(scrollView: NSScrollView, minHeight: CGFloat, maxHeight: CGFloat) {
        self.scrollView = scrollView
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.currentHeight = minHeight
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: currentHeight)
    }
}

// MARK: - File Chip View

@available(macOS 26.0, *)
struct FileChipView: View {
    let attachment: FileAttachment
    let showRemoveButton: Bool
    let onRemove: (() -> Void)?
    let onClick: (() -> Void)?
    let colorScheme: ColorScheme
    
    init(
        attachment: FileAttachment,
        showRemoveButton: Bool = false,
        onRemove: (() -> Void)? = nil,
        onClick: (() -> Void)? = nil,
        colorScheme: ColorScheme = .dark
    ) {
        self.attachment = attachment
        self.showRemoveButton = showRemoveButton
        self.onRemove = onRemove
        self.onClick = onClick
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // File icon
            Image(systemName: fileIcon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary(for: colorScheme))
                .frame(width: 20, height: 20)
            
            // File name and size
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.originalName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                    .lineLimit(1)
                
                Text(formatFileSize(attachment.fileSize))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
            }
            
            Spacer()
            
            // Remove button (if shown)
            if showRemoveButton, let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
                .buttonStyle(.plain)
                .help("Remove file")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border(for: colorScheme), lineWidth: 1)
        )
        .onTapGesture {
            onClick?()
        }
    }
    
    private var fileIcon: String {
        let pathExtension = (attachment.originalName as NSString).pathExtension.lowercased()
        
        switch pathExtension {
        case "pdf":
            return "doc.fill"
        case "txt", "md", "rtf":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo.fill"
        case "mp4", "mov", "avi":
            return "video.fill"
        case "mp3", "wav", "m4a":
            return "music.note"
        case "zip", "tar", "gz":
            return "archivebox.fill"
        case "swift", "py", "js", "ts", "java", "cpp", "c":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "plist":
            return "curlybraces"
        case "csv", "xlsx", "xls":
            return "tablecells.fill"
        default:
            return "doc.fill"
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Message View

@available(macOS 26.0, *)
struct MessageView: View {
    let message: Message
    let isLastMessage: Bool
    let conversationMessages: [Message]
    let fontSize: Double
    let useContextual: Bool
    let colorScheme: ColorScheme
    let storedOrchestrationState: OrchestrationState? // For completed messages
    let agentName: String?
    @ObservedObject var viewModel: ChatViewModel
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?
    
    @State private var showOrchestrationDiagram = false
    
    // Get the current orchestration state (live for last message, stored for others)
    private var orchestrationState: OrchestrationState? {
        if isLastMessage && message.role == .assistant {
            return viewModel.orchestrationState ?? storedOrchestrationState
        } else {
            return storedOrchestrationState
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // File attachments (if any)
                if !message.attachments.isEmpty {
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                        ForEach(message.attachments) { attachment in
                            FileChipView(
                                attachment: attachment,
                                onClick: {
                                    // On click: reveal in Finder
                                    let url = URL(fileURLWithPath: attachment.sandboxPath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                },
                                colorScheme: colorScheme
                            )
                        }
                    }
                }
                
                // Message bubble
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(Theme.messageFont(size: fontSize))
                        .foregroundColor(message.role == .user ? .white : Theme.textPrimary(for: colorScheme))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.role == .user ? Theme.userBubble(for: colorScheme) : Theme.assistantBubble(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Statistics and action buttons below the message
                if message.role == .user {
                    messageStatsAndActions
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    messageStatsAndActions
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Agent indicator badge (for single-agent mode)
                if message.role == .assistant, let agentName = agentName, orchestrationState == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                        Text(agentName)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Theme.accent(for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accent(for: colorScheme).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                if !message.toolCalls.isEmpty {
                    let toolNames = message.toolCalls.map { ToolNameMapper.friendlyName(for: $0.toolName) }
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 10))
                        Text(toolNames.joined(separator: ", "))
                    }
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
                
                // Orchestration diagram (for assistant messages with orchestration)
                if message.role == .assistant {
                    // #region debug log
                    let _ = {
                        Task {
                            await DebugLogger.shared.log(
                                location: "ChatView.swift:MessageView",
                                message: "Checking orchestration state for diagram",
                                hypothesisId: "G",
                                data: [
                                    "isLastMessage": isLastMessage,
                                    "hasOrchestrationState": orchestrationState != nil,
                                    "hasStoredState": storedOrchestrationState != nil,
                                    "hasViewModelState": viewModel.orchestrationState != nil,
                                    "decompositionCount": orchestrationState?.decomposition?.subtasks.count ?? 0,
                                    "currentPhase": orchestrationState?.currentPhase.rawValue ?? "nil"
                                ]
                            )
                        }
                    }()
                    // #endregion
                    
                    if let state = orchestrationState {
                        VStack(alignment: .leading, spacing: 8) {
                            // Toggle button
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showOrchestrationDiagram.toggle()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flowchart")
                                        .font(.system(size: 11))
                                    Text(showOrchestrationDiagram ? "Hide Orchestration" : "Show Orchestration")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(Theme.accent(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                            
                            // Diagram view - auto-show if orchestration is in progress or if explicitly shown
                            if showOrchestrationDiagram || !state.isComplete {
                                OrchestrationDiagramView(state: state, colorScheme: colorScheme)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                                        removal: .opacity.combined(with: .move(edge: .top))
                                    ))
                            }
                        }
                        .padding(.top, 4)
                        .onAppear {
                            // Auto-expand diagram when it first appears if orchestration is active
                            if !state.isComplete {
                                showOrchestrationDiagram = true
                            }
                        }
                        .onChange(of: state.currentPhase) { oldPhase, newPhase in
                            // Auto-show when orchestration starts or phase changes
                            if newPhase != .complete && newPhase != .failed {
                                if !showOrchestrationDiagram {
                                    showOrchestrationDiagram = true
                                }
                            }
                        }
                    } else {
                        // #region debug log
                        let _ = {
                            Task {
                                await DebugLogger.shared.log(
                                    location: "ChatView.swift:MessageView",
                                    message: "Orchestration state is nil, diagram not shown",
                                    hypothesisId: "G",
                                    data: [
                                        "isLastMessage": isLastMessage,
                                        "hasStoredState": storedOrchestrationState != nil,
                                        "hasViewModelState": viewModel.orchestrationState != nil
                                    ]
                                )
                            }
                        }()
                        // #endregion
                    }
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .contextMenu {
            Button("Copy") { onCopy() }
            if let onRegenerate = onRegenerate {
                Divider()
                Button("Regenerate") { onRegenerate() }
            }
        }
    }
    
    private var messageStatsAndActions: some View {
        HStack(spacing: 8) {
            // Statistics on the left
            MessageStatisticsView(
                message: message,
                conversationMessages: conversationMessages,
                useContextual: useContextual,
                colorScheme: colorScheme
            )
            
            Spacer()
            
            // Action buttons for last assistant message on the right
            if message.role == .assistant && isLastMessage {
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary(for: colorScheme))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")
                    
                    if let onRegenerate = onRegenerate {
                        Button(action: onRegenerate) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary(for: colorScheme))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate response")
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

// MARK: - Message Statistics View

@available(macOS 26.0, *)
struct MessageStatisticsView: View {
    let message: Message
    let conversationMessages: [Message]
    let useContextual: Bool
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 6) {
            // Timestamp
            Text(timeString)
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.6))
            
            // Bullet separator
            Text("•")
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.4))
            
            // Context size (estimated tokens)
            Text("\(estimatedTokens) tokens")
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.6))
            
            // Response time (for assistant messages only)
            if let responseTime = message.responseTime {
                Text("•")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.4))
                
                Text(String(format: "%.1fs", responseTime))
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.6))
            }
        }
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }
    
    private var estimatedTokens: Int {
        // Estimate tokens: 1 token ≈ 4 characters for English
        if useContextual {
            // For contextual mode, sum all previous messages up to this one
            if let index = conversationMessages.firstIndex(where: { $0.id == message.id }) {
                let messagesUpToThis = Array(conversationMessages.prefix(index + 1))
                let totalChars = messagesUpToThis.reduce(0) { $0 + $1.content.count }
                return totalChars / 4
            }
        }
        // Non-contextual mode or fallback: just this message
        return message.content.count / 4
    }
}

// MARK: - Loading Indicator

@available(macOS 26.0, *)
struct LoadingIndicator: View {
    @State private var dots = ""
    let colorScheme: ColorScheme
    
    init(colorScheme: ColorScheme = .dark) {
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(Theme.textSecondary(for: colorScheme))
            Text("Thinking\(dots)")
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary(for: colorScheme))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .task {
            while true {
                try? await Task.sleep(for: .milliseconds(400))
                dots = dots.count >= 3 ? "" : dots + "."
            }
        }
    }
}

// MARK: - Empty State

@available(macOS 26.0, *)
struct EmptyConversationView: View {
    let colorScheme: ColorScheme
    let onNewChat: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.5))
            
            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.system(size: 20, weight: .medium, design: .default))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                
                Text("Type a message below to begin")
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background(for: colorScheme))
    }
}

// MARK: - Input Area

@available(macOS 26.0, *)
struct InputArea: View {
    @Binding var messageText: String
    @Binding var pendingAttachments: [FileAttachment]
    var isInputFocused: FocusState<Bool>.Binding
    let isLoading: Bool
    let fontSize: Double
    let colorScheme: ColorScheme
    let onSend: () -> Void
    let conversationId: UUID?
    
    @State private var isDragOver: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    private let fileManagerService = FileManagerService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.border(for: colorScheme))
                .frame(height: 1)
            
            VStack(spacing: 8) {
                // Pending file attachments
                if !pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pendingAttachments) { attachment in
                                FileChipView(
                                    attachment: attachment,
                                    showRemoveButton: true,
                                    onRemove: {
                                        pendingAttachments.removeAll { $0.id == attachment.id }
                                    },
                                    colorScheme: colorScheme
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                }
                
                HStack(alignment: .bottom, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        TextEditorWithEnterHandler(
                            text: $messageText,
                            fontSize: fontSize,
                            placeholder: "Message",
                            colorScheme: colorScheme,
                            onEnter: {
                                if canSend {
                                    onSend()
                                }
                            }
                        )
                        .focused(isInputFocused)
                        .frame(minHeight: 40, maxHeight: 180)
                        .allowsHitTesting(true) // Allow hit testing for text editing
                        
                        if messageText.isEmpty {
                            Text("Message")
                                .font(Theme.messageFont(size: fontSize))
                                .foregroundColor(Theme.textSecondary(for: colorScheme))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                    }
                    .background(Theme.surface(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isDragOver ? Theme.accent(for: colorScheme) : Theme.border(for: colorScheme), lineWidth: isDragOver ? 2 : 1)
                    )
                    .contentShape(Rectangle()) // Make entire area droppable
                    .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                        handleFileDrop(providers: providers)
                    }
                    
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(canSend ? .white : Theme.textSecondary(for: colorScheme))
                            .frame(width: 32, height: 32)
                            .background(canSend ? Theme.accent(for: colorScheme) : Theme.surface(for: colorScheme))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(16)
                .background(Theme.background(for: colorScheme))
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var canSend: Bool {
        (!messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty) && !isLoading
    }
    
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard let conversationId = conversationId else {
            errorMessage = "Please select a conversation first"
            showError = true
            return false
        }
        
        // Prevent default paste behavior by returning true immediately
        // This tells SwiftUI we're handling the drop
        Task {
            for provider in providers {
                guard provider.hasItemConformingToTypeIdentifier("public.file-url") else { continue }
                
                do {
                    // Use async alternative to loadItem
                    let item = try await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil)
                    
                    guard let data = item as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString) else {
                        await MainActor.run {
                            errorMessage = "Invalid file URL"
                            showError = true
                        }
                        continue
                    }
                    
                    // Check if this looks like a file path that was pasted as text
                    // If the message text ends with this path, remove it
                    await MainActor.run {
                        let urlPath = url.path
                        if messageText.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(urlPath) {
                            // Remove the pasted path from text
                            messageText = String(messageText.dropLast(urlPath.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    
                    do {
                        let attachment = try await fileManagerService.copyToSandbox(fileURL: url, conversationId: conversationId)
                        await MainActor.run {
                            pendingAttachments.append(attachment)
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Failed to copy file: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to load file: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        }
        
        return true // Return true to indicate we handled the drop and prevent default behavior
    }
}

// MARK: - TextEditor with Enter Handler

@available(macOS 26.0, *)
struct TextEditorWithEnterHandler: NSViewRepresentable {
    typealias NSViewType = NSView
    
    @Binding var text: String
    let fontSize: Double
    let placeholder: String
    let colorScheme: ColorScheme
    let onEnter: () -> Void
    
    // Calculate row height based on font size
    private var rowHeight: CGFloat {
        // Approximate height per line: font size + line spacing
        return fontSize * 1.5
    }
    
    // Min height: 1 row (~40px)
    private var minHeight: CGFloat {
        return 40
    }
    
    // Max height: ~7 rows (~180px)
    private var maxHeight: CGFloat {
        return 180
    }
    
    func makeNSView(context: Context) -> NSView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        
        textView.font = NSFont.systemFont(ofSize: fontSize)
        // Set text color based on theme - use Theme.textPrimary for proper contrast
        let themeColor = Theme.textPrimary(for: colorScheme)
        textView.textColor = NSColor(themeColor)
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        
        // Disable automatic link detection to prevent file paths from being auto-detected
        textView.isAutomaticLinkDetectionEnabled = false
        
        // Add padding to match placeholder text margins (16px horizontal, 12px vertical)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        
        // Configure text container for dynamic sizing
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        
        // Enable vertical resizing up to max height
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: maxHeight)
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false // Start without scroller
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.minHeight = minHeight
        context.coordinator.maxHeight = maxHeight
        textView.delegate = context.coordinator
        
        // Create a custom scroll view that reports proper intrinsic content size
        let customScrollView = CustomScrollView(scrollView: scrollView, minHeight: minHeight, maxHeight: maxHeight)
        customScrollView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: customScrollView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: customScrollView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: customScrollView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: customScrollView.bottomAnchor)
        ])
        
        context.coordinator.customScrollView = customScrollView
        
        return customScrollView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let customScrollView = nsView as? CustomScrollView else { return }
        let scrollView = customScrollView.scrollView
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        // Update text color based on theme
        let themeColor = Theme.textPrimary(for: colorScheme)
        textView.textColor = NSColor(themeColor)
        
        // Update height based on content
        Task { @MainActor in
            context.coordinator.updateHeight()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: TextEditorWithEnterHandler
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var customScrollView: CustomScrollView?
        var minHeight: CGFloat = 40
        var maxHeight: CGFloat = 120
        
        init(_ parent: TextEditorWithEnterHandler) {
            self.parent = parent
        }
        
        
        @MainActor
        func updateHeight() {
            guard let textView = textView, let scrollView = scrollView, let customScrollView = customScrollView else { return }
            
            // Capture min/max heights to avoid actor isolation issues
            let minH = minHeight
            let maxH = maxHeight
            
            // Force layout update
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            
            // Calculate content height (including text container inset padding)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
            let textInset = textView.textContainerInset
            let contentHeight = usedRect.height + textInset.height * 2 // Top + bottom padding
            
            // Determine if scrolling is needed
            let needsScrolling = contentHeight > maxH
            
            // Update text view max size
            if needsScrolling {
                // Content exceeds max - allow unlimited height, enable scrolling
                textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                textView.minSize = NSSize(width: 0, height: minH)
                scrollView.hasVerticalScroller = true
                customScrollView.currentHeight = maxH
            } else {
                // Content fits - size to content, disable scrolling
                let clampedHeight = max(contentHeight, minH)
                textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: clampedHeight)
                textView.minSize = NSSize(width: 0, height: clampedHeight)
                scrollView.hasVerticalScroller = false
                customScrollView.currentHeight = clampedHeight
            }
            
            // Update text view frame to match content
            let textViewHeight = needsScrolling ? contentHeight : max(contentHeight, minH)
            textView.frame = NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: textViewHeight)
            
            // Invalidate intrinsic content size
            customScrollView.invalidateIntrinsicContentSize()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            Task { @MainActor in
                updateHeight()
            }
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Enter key
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Shift is held
                if NSEvent.modifierFlags.contains(.shift) {
                    // Shift+Enter: insert newline (default behavior)
                    return false
                } else {
                    // Plain Enter: trigger onEnter callback
                    parent.onEnter()
                    return true // Prevent default behavior
                }
            }
            
            
            return false
        }
    }
}
