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
    @AppStorage(UserDefaultsKey.preferredColorScheme) private var preferredColorScheme: String = "dark"
    @Environment(\.colorScheme) private var systemColorScheme
    
    public init() {
        Log.debug("🎨 ContentView initializing...")
    }
    
    public var body: some View {
        let _ = Log.debug("🎨 ContentView body rendering...")
        let effectiveColorScheme = effectiveColorSchemeForTheme
        
        // Try to create viewModel lazily
        if viewModel == nil {
            return AnyView(
                VStack {
                    Text("Initializing...")
                        .onAppear {
                            Log.debug("📱 Creating ChatViewModel...")
                            Log.debug("📱 Current thread: \(Thread.isMainThread ? "Main" : "Background")")
                            Log.debug("📱 About to create Task...")
                            
                            // Try to create it on a background thread first
                            Task { @MainActor in
                                Log.debug("📱 ✅ Task started executing")
                                Log.debug("📱 About to call ChatViewModel()...")
                                
                                Log.debug("📱 Calling ChatViewModel init...")
                                let vm = ChatViewModel()
                                Log.debug("📱 ChatViewModel() returned, assigning to viewModel...")
                                self.viewModel = vm
                                Log.debug("✅ ChatViewModel created and assigned successfully")
                            }
                            
                            Log.debug("📱 Task created (but may not have executed yet)")
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
            .background(Theme.surface(for: effectiveColorScheme))
        } detail: {
            ChatView(viewModel: vm)
        }
        .background(Theme.background(for: effectiveColorScheme))
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showSettings) {
            if let vm = viewModel {
                SettingsView(viewModel: vm)
            }
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
                        .foregroundColor(Theme.textSecondary(for: effectiveColorScheme))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .onAppear {
            Log.debug("✅ ContentView appeared")
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
    
    /// Effective color scheme for theme colors (uses system when "system" is selected)
    private var effectiveColorSchemeForTheme: ColorScheme {
        switch preferredColorScheme {
        case "light":
            return .light
        case "dark":
            return .dark
        case "system":
            return systemColorScheme
        default:
            return .dark
        }
    }
}
