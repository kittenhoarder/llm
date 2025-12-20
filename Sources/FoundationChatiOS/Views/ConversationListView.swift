//
//  ConversationListView.swift
//  FoundationChatiOS
//
//  Modal view showing list of conversations
//

import SwiftUI
import FoundationChatCore

@available(iOS 26.0, *)
struct ConversationListView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.conversations) { conversation in
                    Button(action: {
                        viewModel.selectedConversationId = conversation.id
                        isPresented = false
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(conversation.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

