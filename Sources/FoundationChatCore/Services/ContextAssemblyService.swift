//
//  ContextAssemblyService.swift
//  FoundationChatCore
//
//  Centralized context assembly for agent execution
//

import Foundation

/// Assembles agent context from conversation state, attachments, and optimization services.
@available(macOS 26.0, iOS 26.0, *)
public actor ContextAssemblyService {
    public static let shared = ContextAssemblyService()

    private let tokenCounter = TokenCounter()

    private init() {}

    /// Build a context for a conversation.
    public func assemble(
        baseContext: AgentContext,
        conversationId: UUID,
        conversation: Conversation,
        fileReferences: [String] = [],
        currentMessage: String? = nil
    ) async -> AgentContext {
        var context = baseContext

        context.fileReferences = collectFileReferences(from: conversation, additionalFiles: fileReferences)
        context.metadata["conversationId"] = conversationId.uuidString

        if let lastMessage = conversation.messages.last {
            let currentAttachments = lastMessage.attachments.map { $0.sandboxPath }
            if !currentAttachments.isEmpty {
                context.metadata["currentFileReferences"] = currentAttachments.joined(separator: "\n")
            }
        }

        let useSVDB = UserDefaults.standard.object(forKey: UserDefaultsKey.useSVDBForContextOptimization) as? Bool ?? true
        if useSVDB, let query = currentMessage, !conversation.messages.isEmpty {
            do {
                let contextOptimizer = ContextOptimizer()
                let optimized = try await contextOptimizer.optimizeContextWithSVDB(
                    messages: conversation.messages,
                    query: query,
                    conversationId: conversationId
                )

                context.conversationHistory = optimized.messages

                let originalTokens = await tokenCounter.countTokens(conversation.messages)
                let optimizedTokens = optimized.tokenUsage.messageTokens
                if originalTokens > optimizedTokens {
                    context.metadata["tokens_original_context"] = String(originalTokens)
                    context.metadata["tokens_optimized_context"] = String(optimizedTokens)
                    context.metadata["tokens_svdb_saved_context"] = String(originalTokens - optimizedTokens)
                }

                print("📊 AgentService: SVDB optimization - Original: \(originalTokens) tokens, Optimized: \(optimizedTokens) tokens")
            } catch {
                print("⚠️ AgentService: SVDB optimization failed, using full history: \(error.localizedDescription)")
                context.conversationHistory = conversation.messages
            }
        } else {
            context.conversationHistory = conversation.messages
        }

        if !context.fileReferences.isEmpty, let query = currentMessage {
            do {
                let ragService = RAGService.shared
                let topK = UserDefaults.standard.integer(forKey: "ragTopK") > 0
                    ? UserDefaults.standard.integer(forKey: "ragTopK")
                    : 5

                var enhancedQuery = query
                if let sectionMatch = query.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
                    let sectionNumber = String(query[sectionMatch])
                    enhancedQuery = "section \(sectionNumber) \(query)"
                }

                await DebugLogger.shared.log(
                    location: "ContextAssemblyService.swift:assemble",
                    message: "Attempting RAG retrieval",
                    hypothesisId: "B",
                    data: [
                        "originalQuery": String(query.prefix(100)),
                        "enhancedQuery": String(enhancedQuery.prefix(100)),
                        "fileReferencesCount": context.fileReferences.count,
                        "topK": topK,
                        "conversationId": conversationId.uuidString
                    ]
                )

                let chunks = try await ragService.searchRelevantChunks(
                    query: enhancedQuery,
                    fileIds: nil,
                    conversationId: conversationId,
                    topK: topK
                )

                context.ragChunks = chunks

                await DebugLogger.shared.log(
                    location: "ContextAssemblyService.swift:assemble",
                    message: "RAG retrieval completed",
                    hypothesisId: "B",
                    data: [
                        "chunksRetrieved": chunks.count,
                        "chunkPreviews": chunks.prefix(3).map { String($0.content.prefix(100)) }
                    ]
                )
            } catch {
                await DebugLogger.shared.log(
                    location: "ContextAssemblyService.swift:assemble",
                    message: "RAG retrieval failed",
                    hypothesisId: "B",
                    data: ["error": error.localizedDescription]
                )
                print("⚠️ AgentService: RAG retrieval failed: \(error.localizedDescription)")
            }
        } else {
            await DebugLogger.shared.log(
                location: "ContextAssemblyService.swift:assemble",
                message: "Skipping RAG retrieval",
                hypothesisId: "B",
                data: [
                    "hasFileReferences": !context.fileReferences.isEmpty,
                    "hasCurrentMessage": currentMessage != nil
                ]
            )
        }

        let ragChunksCount = context.ragChunks.count
        let fileReferencesCount = context.fileReferences.count
        let messageCount = context.conversationHistory.count
        await DebugLogger.shared.log(
            location: "ContextAssemblyService.swift:assemble",
            message: "Context assembly completed",
            hypothesisId: "B",
            data: [
                "ragChunksCount": ragChunksCount,
                "fileReferencesCount": fileReferencesCount,
                "messageCount": messageCount
            ]
        )

        return context
    }

    private func collectFileReferences(
        from conversation: Conversation,
        additionalFiles: [String] = []
    ) -> [String] {
        var allFileReferences = additionalFiles

        for message in conversation.messages.suffix(AppConstants.recentMessagesCount) {
            for attachment in message.attachments {
                if FileManager.default.fileExists(atPath: attachment.sandboxPath) {
                    allFileReferences.append(attachment.sandboxPath)
                }
            }
        }

        var seen = Set<String>()
        return allFileReferences.filter { seen.insert($0).inserted }
    }
}
