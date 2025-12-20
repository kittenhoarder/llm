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
    
    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                
                TextField("Search", text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchConversations($0) }
                ))
                .textFieldStyle(.plain)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textPrimary)
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchConversations("") }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated)
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
        .background(Theme.surface)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task {
                        await viewModel.createNewConversation()
                    }
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(Theme.textSecondary)
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
                    .foregroundColor(Theme.textPrimary)
                    .focused($isTitleFocused)
                    .onSubmit { onFinishRename() }
                    .onExitCommand { onCancelRename() }
                    .onAppear { isTitleFocused = true }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(Theme.titleFont)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    
                    Text(conversation.updatedAt, style: .relative)
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            
            Spacer()
            
            if isHovered && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
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
                .fill(isSelected ? Theme.accent.opacity(0.3) : (isHovered ? Theme.surfaceElevated : Color.clear))
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
