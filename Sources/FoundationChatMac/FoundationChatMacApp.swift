//
//  FoundationChatMacApp.swift
//  FoundationChatMac
//
//  App scene definition (entry point is in the Xcode wrapper)
//

import SwiftUI

@available(macOS 26.0, *)
public struct FoundationChatMacApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}
