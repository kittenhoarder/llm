//
//  ContentView.swift
//  FoundationChatiOS
//
//  Main content view for iOS app
//

import SwiftUI
import FoundationChatCore

@available(iOS 26.0, *)
struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showConversationList = false
    
    var body: some View {
        NavigationStack {
            ChatView(viewModel: viewModel)
                .navigationTitle(viewModel.currentConversation?.title ?? "New Conversation")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: {
                            showConversationList = true
                        }) {
                            Label("Conversations", systemImage: "list.bullet")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button(action: {
                            Task {
                                await viewModel.createNewConversation()
                            }
                        }) {
                            Label("New Conversation", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showConversationList) {
                    ConversationListView(viewModel: viewModel, isPresented: $showConversationList)
                }
        }
        .task {
            await viewModel.loadConversations()
        }
    }
}

