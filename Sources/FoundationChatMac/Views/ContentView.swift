//
//  ContentView.swift
//  FoundationChatMac
//
//  Main content view for macOS app with minimal dark theme
//

import SwiftUI
import FoundationChatCore

@available(macOS 26.0, *)
public struct ContentView: View {
    @State private var viewModel: ChatViewModel?
    @State private var showSettings = false
    @AppStorage("preferredColorScheme") private var preferredColorScheme: String = "dark"
    
    public init() {
        print("🎨 ContentView initializing...")
    }
    
    public var body: some View {
        let _ = print("🎨 ContentView body rendering...")
        
        // Try to create viewModel lazily
        if viewModel == nil {
            return AnyView(
                VStack {
                    Text("Initializing...")
                        .onAppear {
                            print("📱 Creating ChatViewModel...")
                            print("📱 Current thread: \(Thread.isMainThread ? "Main" : "Background")")
                            print("📱 About to create Task...")
                            
                            // Try to create it on a background thread first
                            Task { @MainActor in
                                print("📱 ✅ Task started executing")
                                print("📱 About to call ChatViewModel()...")
                                
                                print("📱 Calling ChatViewModel init...")
                                let vm = ChatViewModel()
                                print("📱 ChatViewModel() returned, assigning to viewModel...")
                                self.viewModel = vm
                                print("✅ ChatViewModel created and assigned successfully")
                            }
                            
                            print("📱 Task created (but may not have executed yet)")
                        }
                }
                .frame(width: 400, height: 300)
            )
        }
        
        guard let vm = viewModel else {
            return AnyView(Text("Loading..."))
        }
        
        return AnyView(
        NavigationSplitView {
            ConversationListView(viewModel: vm)
            .background(Theme.surface)
        } detail: {
            ChatView(viewModel: vm)
        }
        .background(Theme.background)
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // Global keyboard shortcuts using focusedSceneValue or commands
        .onKeyPress(.upArrow) {
            navigateConversation(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateConversation(direction: 1)
            return .handled
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .onAppear {
            print("✅ ContentView appeared")
        }
        )
    }
    
    private func navigateConversation(direction: Int) {
        guard let vm = viewModel else { return }
        let conversations = vm.displayedConversations
        guard !conversations.isEmpty else { return }
        
        if let currentId = vm.selectedConversationId,
           let currentIndex = conversations.firstIndex(where: { $0.id == currentId }) {
            let newIndex = max(0, min(conversations.count - 1, currentIndex + direction))
            vm.selectedConversationId = conversations[newIndex].id
        } else {
            vm.selectedConversationId = conversations.first?.id
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch preferredColorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        case "system":
            return nil
        default:
            return .dark
        }
    }
}
