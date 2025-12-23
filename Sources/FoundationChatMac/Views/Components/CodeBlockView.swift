//
//  CodeBlockView.swift
//  FoundationChatMac
//
//  Rendering for code blocks with syntax highlighting and copy capability
//

import SwiftUI
import AppKit

@available(macOS 26.0, *)
struct CodeBlockView: View {
    let code: String
    let language: String?
    let colorScheme: ColorScheme
    
    @State private var isHovering = false
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with language and copy button
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                
                Spacer()
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(code, forType: .string)
                    
                    withAnimation {
                        isCopied = true
                    }
                    
                    // Reset copy state after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surfaceElevated(for: colorScheme).opacity(0.8))

            
            // Code Content
            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlightedCode)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(12)
                    .frame(minWidth: 50, alignment: .leading)
            }
            .background(Theme.surface(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border(for: colorScheme), lineWidth: 1)
        )
        .padding(.vertical, 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    // Basic syntax highlighting using AttributedString
    private var highlightedCode: AttributedString {
        var attributed = AttributedString(code)
        attributed.foregroundColor = Theme.textPrimary(for: colorScheme)
        
        // Very basic simple keyword highlighting
        // In a real app, you'd use a parser like Splash or Highlightr
        let keywords = ["func", "var", "let", "if", "else", "return", "struct", "class", "import", "public", "private", "view", "body", "some", "init"]
        let types = ["String", "Int", "Bool", "Double", "View", "Text", "VStack", "HStack", "Image"]
        
        // We iterate specifically for Swift-like tokens for this demo
        for keyword in keywords {
            if let range = attributed.range(of: "\\b\(keyword)\\b", options: .regularExpression) {
                attributed[range].foregroundColor = .purple
                attributed[range].font = .system(size: 12, weight: .bold, design: .monospaced)
            }
            // Need to handle multiple occurrences manually if AttributedString.range gets only first
            // This is a naive implementation limitation
        }
        
        for type in types {
            if let range = attributed.range(of: "\\b\(type)\\b", options: .regularExpression) {
                attributed[range].foregroundColor = .blue
                attributed[range].font = .system(size: 12, weight: .semibold, design: .monospaced)
            }
        }
        
        return attributed
    }
}
