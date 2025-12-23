//
//  Log.swift
//  FoundationChatCore
//

import Foundation
import os

@available(macOS 26.0, iOS 26.0, *)
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "FoundationChat"
    private static let core = Logger(subsystem: subsystem, category: "core")
    
    public static func debug(_ message: String) {
        #if DEBUG
        core.debug("\(message, privacy: .public)")
        #endif
    }
    
    public static func info(_ message: String) {
        core.info("\(message, privacy: .public)")
    }
    
    public static func warn(_ message: String) {
        core.warning("\(message, privacy: .public)")
    }
    
    public static func error(_ message: String) {
        core.error("\(message, privacy: .public)")
    }
}
