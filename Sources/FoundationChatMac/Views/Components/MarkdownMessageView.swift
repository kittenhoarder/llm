//
//  MarkdownMessageView.swift
//  FoundationChatMac
//
//  Parses a message string and renders mixed content (Text and Code Blocks)
//

import SwiftUI
import FoundationChatCore

@available(macOS 26.0, *)
struct MarkdownMessageView: View {
    let content: String
    let fontSize: Double
    let role: MessageRole
    let colorScheme: ColorScheme
    
    private struct ContentBlock: Identifiable {
        let id = UUID()
        let type: BlockType
        let content: String
        let language: String?
    }
    
    private enum BlockType {
        case text
        case code
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseContent(content)) { block in
                switch block.type {
                case .text:
                    if !block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(LocalizedStringKey(block.content)) // LocalizedStringKey supports basic Markdown (bold, italic)
                            .font(.system(size: fontSize, design: .default)) // Use default design for better readability
                            .lineSpacing(4)
                            .foregroundColor(role == .user ? .white : Theme.textPrimary(for: colorScheme))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .code:
                    CodeBlockView(
                        code: block.content,
                        language: block.language,
                        colorScheme: colorScheme
                    )
                }
            }
        }
    }
    
    private func parseContent(_ text: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let components = text.components(separatedBy: "```")
        
        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Even indices are text (outside code blocks)
                // Need to only add if it's not empty
                if !component.isEmpty {
                    blocks.append(ContentBlock(type: .text, content: component, language: nil))
                }
            } else {
                // Odd indices are code
                // Try to parse language identifier first line
                let lines = component.components(separatedBy: .newlines)
                var codeContent = component
                var language: String? = nil
                
                if let firstLine = lines.first, !firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    language = firstLine.trimmingCharacters(in: .whitespaces)
                    // Remove the first line (language identifier) from the content
                    // Re-join the rest
                    if lines.count > 1 {
                        let rest = lines.dropFirst()
                        codeContent = rest.joined(separator: "\n")
                    } else {
                        codeContent = "" 
                    }
                }
                
                // Trim leading/trailing newlines for cleaner look
                codeContent = codeContent.trimmingCharacters(in: .newlines)
                
                blocks.append(ContentBlock(type: .code, content: codeContent, language: language))
            }
        }
        
        return blocks
    }
}
