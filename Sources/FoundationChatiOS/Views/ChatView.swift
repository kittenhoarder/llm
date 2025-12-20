//
//  ChatView.swift
//  FoundationChatiOS
//
//  Main chat interface for iOS
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import FoundationChatCore

@available(iOS 26.0, *)
struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let conversation = viewModel.currentConversation {
                            ForEach(conversation.messages) { message in
                                MessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.currentConversation?.messages.count) {
                    if let lastMessage = viewModel.currentConversation?.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Type your message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
            .padding()
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        messageText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
}

@available(iOS 26.0, *)
struct MessageView: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? Color.accentColor : Color(white: 0.95))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(12)
                
                if !message.toolCalls.isEmpty {
                    let toolNames = message.toolCalls.map { ToolNameMapper.friendlyName(for: $0.toolName) }
                    Text("Tools: \(toolNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

