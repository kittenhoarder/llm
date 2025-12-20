//
//  Theme.swift
//  FoundationChatMac
//
//  Minimal dark theme configuration
//

import SwiftUI

@available(macOS 26.0, *)
public enum Theme {
    // MARK: - Colors
    
    /// Primary background (#0d0d0d)
    public static let background = Color(red: 0.05, green: 0.05, blue: 0.05)
    
    /// Secondary background for cards/panels (#1a1a1a)
    public static let surface = Color(red: 0.10, green: 0.10, blue: 0.10)
    
    /// Elevated surface (#242424)
    public static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.14)
    
    /// Subtle borders (#2a2a2a)
    public static let border = Color(red: 0.16, green: 0.16, blue: 0.16)
    
    /// Primary text
    public static let textPrimary = Color(red: 0.93, green: 0.93, blue: 0.93)
    
    /// Secondary text
    public static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.55)
    
    /// Muted accent (blue-gray)
    public static let accent = Color(red: 0.35, green: 0.50, blue: 0.70)
    
    /// User message bubble
    public static let userBubble = Color(red: 0.20, green: 0.30, blue: 0.45)
    
    /// Assistant message bubble
    public static let assistantBubble = Color(red: 0.12, green: 0.12, blue: 0.12)
    
    // MARK: - Typography
    
    public static func messageFont(size: CGFloat? = nil) -> Font {
        let fontSize = size ?? 14
        return Font.system(size: fontSize, design: .monospaced)
    }
    
    public static let titleFont = Font.system(.headline, design: .default, weight: .medium)
    public static let captionFont = Font.system(.caption, design: .monospaced)
}

