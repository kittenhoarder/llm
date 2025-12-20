//
//  FoundationChatApp.swift
//  FoundationChat
//
//  macOS app entry point - wraps the SPM FoundationChatMac module
//

import SwiftUI
import FoundationChatMac
import FoundationChatCore

@available(macOS 26.0, *)
@main
struct FoundationChatApp: App {
    init() {
        print("🚀 FoundationChatApp initializing...")
    }
    
    var body: some Scene {
        WindowGroup {
            AppContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

@available(macOS 26.0, *)
struct AppContentView: View {
    @State private var useSimpleView = false
    
    var body: some View {
        if useSimpleView {
            // Simple test view to see if SwiftUI works at all
            VStack {
                Text("Hello World")
                    .font(.largeTitle)
                Text("If you see this, SwiftUI is working")
                Button("Try Full View") {
                    useSimpleView = false
                }
            }
            .frame(width: 400, height: 300)
            .onAppear {
                print("✅ Simple test view appeared")
            }
        } else {
            ContentView()
                .preferredColorScheme(.dark)
                .onAppear {
                    print("✅ AppContentView appeared")
                }
                .onDisappear {
                    print("⚠️ AppContentView disappeared")
                }
        }
    }
}





