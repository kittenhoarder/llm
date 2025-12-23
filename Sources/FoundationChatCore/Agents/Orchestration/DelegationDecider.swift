//
//  DelegationDecider.swift
//  FoundationChatCore
//
//  Heuristics for orchestration delegation decisions
//

import Foundation

@available(macOS 26.0, iOS 26.0, *)
struct DelegationDecision {
    let shouldDelegate: Bool
    let reason: String
}

@available(macOS 26.0, iOS 26.0, *)
struct DelegationDecider {
    func forcedDecision(
        taskDescription: String,
        hasFiles: Bool,
        availableCapabilities: Set<AgentCapability>
    ) -> DelegationDecision? {
        let normalized = taskDescription.lowercased()

        let hasWebSearch = availableCapabilities.contains(.webSearch)

        let explicitSearchTriggers = [
            "search the web", "search web", "web search", "look up online",
            "search for", "look up", "find online"
        ]

        if hasWebSearch && explicitSearchTriggers.contains(where: { normalized.contains($0) }) {
            return DelegationDecision(
                shouldDelegate: true,
                reason: "Explicit web search request detected."
            )
        }

        if hasFiles {
            return nil
        }

        if !hasWebSearch {
            return nil
        }

        let timeSensitiveSignals = [
            "current", "latest", "today", "now", "recent", "as of",
            "this week", "this month", "this year", "last speech", "breaking", "news"
        ]

        let factualEntities = [
            "president", "prime minister", "ceo", "stock", "price", "weather",
            "score", "standings", "election", "results", "release date"
        ]

        let questionSignals = ["who", "what", "when", "where", "how"]

        let hasTimeSignal = timeSensitiveSignals.contains(where: { normalized.contains($0) })
        let hasFactualEntity = factualEntities.contains(where: { normalized.contains($0) })
        let hasQuestionSignal = questionSignals.contains(where: { normalized.hasPrefix($0) || normalized.contains("\n\($0) ") })

        if hasTimeSignal || (hasFactualEntity && hasQuestionSignal) {
            return DelegationDecision(
                shouldDelegate: true,
                reason: "Likely time-sensitive or factual query; prefer Web Search."
            )
        }

        return nil
    }
}
