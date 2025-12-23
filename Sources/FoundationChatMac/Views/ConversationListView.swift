//
//  ConversationListView.swift
//  FoundationChatMac
//
//  Sidebar view showing list of conversations with minimal dark theme
//

import SwiftUI
import FoundationChatCore

@available(macOS 26.0, *)
struct ConversationListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var hoveredId: UUID?
    @State private var editingTitle = ""
    @AppStorage(UserDefaultsKey.preferredColorScheme) private var preferredColorScheme: String = "dark"
    @Environment(\.colorScheme) private var systemColorScheme
    
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
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                
                TextField("Search", text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchConversations($0) }
                ))
                .textFieldStyle(.plain)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textPrimary(for: effectiveColorScheme))
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchConversations("") }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated(for: effectiveColorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Conversation list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.displayedConversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: viewModel.selectedConversationId == conversation.id,
                            isHovered: hoveredId == conversation.id,
                            isEditing: viewModel.editingConversationId == conversation.id,
                            editingTitle: $editingTitle,
                            colorScheme: effectiveColorScheme,
                            onSelect: {
                                viewModel.selectedConversationId = conversation.id
                            },
                            onDelete: {
                                viewModel.requestDeleteConversation(conversation.id)
                            },
                            onRename: {
                                editingTitle = conversation.title
                                viewModel.startRenaming(conversation.id)
                            },
                            onFinishRename: {
                                viewModel.finishRenaming(conversation.id, newTitle: editingTitle)
                            },
                            onCancelRename: {
                                viewModel.cancelRenaming()
                            }
                        )
                        .onHover { hovering in
                            hoveredId = hovering ? conversation.id : nil
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(Theme.surface(for: effectiveColorScheme))
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task {
                        await viewModel.createNewConversation()
                    }
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .task {
            await viewModel.loadConversations()
        }
        .alert("Delete Conversation?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteConversation()
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.confirmDeleteConversation()
                }
            }
        } message: {
            Text("This conversation will be permanently deleted.")
        }
    }
}

@available(macOS 26.0, *)
struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isHovered: Bool
    let isEditing: Bool
    @Binding var editingTitle: String
    let colorScheme: ColorScheme
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void
    let onFinishRename: () -> Void
    let onCancelRename: () -> Void
    
    @FocusState private var isTitleFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            if isEditing {
                TextField("Title", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(Theme.titleFont)
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                    .focused($isTitleFocused)
                    .onSubmit { onFinishRename() }
                    .onExitCommand { onCancelRename() }
                    .onAppear { isTitleFocused = true }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(Theme.titleFont)
                        .foregroundColor(Theme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    
                    Text(conversation.updatedAt, style: .relative)
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
            }
            
            Spacer()
            
            if isHovered && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
                .buttonStyle(.plain)
                .help("Delete conversation")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Theme.accent(for: colorScheme).opacity(0.3) : (isHovered ? Theme.surfaceElevated(for: colorScheme) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename") { onRename() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
