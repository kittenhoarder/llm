//
//  Theme.swift
//  FoundationChatMac
//
//  Dynamic theme configuration supporting light and dark modes
//

import SwiftUI

@available(macOS 26.0, *)
public enum Theme {
    // MARK: - Light Theme Colors
    
    /// Primary background (#FAFAFA - off-white)
    private static let lightBackground = Color(red: 0.98, green: 0.98, blue: 0.98)
    
    /// Secondary background for cards/panels (#F5F5F5)
    private static let lightSurface = Color(red: 0.96, green: 0.96, blue: 0.96)
    
    /// Elevated surface (#EEEEEE)
    private static let lightSurfaceElevated = Color(red: 0.93, green: 0.93, blue: 0.93)
    
    /// Subtle borders (#E0E0E0)
    private static let lightBorder = Color(red: 0.88, green: 0.88, blue: 0.88)
    
    /// Primary text (#1A1A1A - near-black)
    private static let lightTextPrimary = Color(red: 0.10, green: 0.10, blue: 0.10)
    
    /// Secondary text (#666666)
    private static let lightTextSecondary = Color(red: 0.40, green: 0.40, blue: 0.40)
    
    /// Modern accent blue (#0066CC)
    private static let lightAccent = Color(red: 0.0, green: 0.40, blue: 0.80)
    
    /// User message bubble (accent color)
    private static let lightUserBubble = Color(red: 0.0, green: 0.40, blue: 0.80)
    
    /// Assistant message bubble (#E8E8E8)
    private static let lightAssistantBubble = Color(red: 0.91, green: 0.91, blue: 0.91)
    
    // MARK: - Dark Theme Colors (existing)
    
    /// Primary background (#0d0d0d)
    private static let darkBackground = Color(red: 0.05, green: 0.05, blue: 0.05)
    
    /// Secondary background for cards/panels (#1a1a1a)
    private static let darkSurface = Color(red: 0.10, green: 0.10, blue: 0.10)
    
    /// Elevated surface (#242424)
    private static let darkSurfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.14)
    
    /// Subtle borders (#2a2a2a)
    private static let darkBorder = Color(red: 0.16, green: 0.16, blue: 0.16)
    
    /// Primary text
    private static let darkTextPrimary = Color(red: 0.93, green: 0.93, blue: 0.93)
    
    /// Secondary text
    private static let darkTextSecondary = Color(red: 0.55, green: 0.55, blue: 0.55)
    
    /// Muted accent (blue-gray)
    private static let darkAccent = Color(red: 0.35, green: 0.50, blue: 0.70)
    
    /// User message bubble
    private static let darkUserBubble = Color(red: 0.20, green: 0.30, blue: 0.45)
    
    /// Assistant message bubble
    private static let darkAssistantBubble = Color(red: 0.12, green: 0.12, blue: 0.12)
    
    // MARK: - Public Color API
    
    /// Primary background color
    public static func background(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightBackground
        case .dark: return darkBackground
        default: return darkBackground // fallback to dark
        }
    }
    
    /// Secondary background for cards/panels
    public static func surface(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightSurface
        case .dark: return darkSurface
        default: return darkSurface
        }
    }
    
    /// Elevated surface
    public static func surfaceElevated(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightSurfaceElevated
        case .dark: return darkSurfaceElevated
        default: return darkSurfaceElevated
        }
    }
    
    /// Subtle borders
    public static func border(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightBorder
        case .dark: return darkBorder
        default: return darkBorder
        }
    }
    
    /// Primary text color
    public static func textPrimary(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightTextPrimary
        case .dark: return darkTextPrimary
        default: return darkTextPrimary
        }
    }
    
    /// Secondary text color
    public static func textSecondary(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightTextSecondary
        case .dark: return darkTextSecondary
        default: return darkTextSecondary
        }
    }
    
    /// Accent color
    public static func accent(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightAccent
        case .dark: return darkAccent
        default: return darkAccent
        }
    }
    
    /// User message bubble color
    public static func userBubble(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightUserBubble
        case .dark: return darkUserBubble
        default: return darkUserBubble
        }
    }
    
    /// Assistant message bubble color
    public static func assistantBubble(for colorScheme: ColorScheme?) -> Color {
        switch colorScheme {
        case .light: return lightAssistantBubble
        case .dark: return darkAssistantBubble
        default: return darkAssistantBubble
        }
    }
    
    // MARK: - Backward Compatibility (deprecated - use functions above)
    
    /// Primary background (deprecated - use background(for:) instead)
    @available(*, deprecated, message: "Use Theme.background(for: colorScheme) instead")
    public static let background = darkBackground
    
    /// Secondary background (deprecated - use surface(for:) instead)
    @available(*, deprecated, message: "Use Theme.surface(for: colorScheme) instead")
    public static let surface = darkSurface
    
    /// Elevated surface (deprecated - use surfaceElevated(for:) instead)
    @available(*, deprecated, message: "Use Theme.surfaceElevated(for: colorScheme) instead")
    public static let surfaceElevated = darkSurfaceElevated
    
    /// Borders (deprecated - use border(for:) instead)
    @available(*, deprecated, message: "Use Theme.border(for: colorScheme) instead")
    public static let border = darkBorder
    
    /// Primary text (deprecated - use textPrimary(for:) instead)
    @available(*, deprecated, message: "Use Theme.textPrimary(for: colorScheme) instead")
    public static let textPrimary = darkTextPrimary
    
    /// Secondary text (deprecated - use textSecondary(for:) instead)
    @available(*, deprecated, message: "Use Theme.textSecondary(for: colorScheme) instead")
    public static let textSecondary = darkTextSecondary
    
    /// Accent (deprecated - use accent(for:) instead)
    @available(*, deprecated, message: "Use Theme.accent(for: colorScheme) instead")
    public static let accent = darkAccent
    
    /// User bubble (deprecated - use userBubble(for:) instead)
    @available(*, deprecated, message: "Use Theme.userBubble(for: colorScheme) instead")
    public static let userBubble = darkUserBubble
    
    /// Assistant bubble (deprecated - use assistantBubble(for:) instead)
    @available(*, deprecated, message: "Use Theme.assistantBubble(for: colorScheme) instead")
    public static let assistantBubble = darkAssistantBubble
    
    // MARK: - Typography
    
    public static func messageFont(size: CGFloat? = nil) -> Font {
        let fontSize = size ?? 14
        return Font.system(size: fontSize, design: .monospaced)
    }
    
    public static let titleFont = Font.system(.headline, design: .default, weight: .medium)
    public static let captionFont = Font.system(.caption, design: .monospaced)
}

