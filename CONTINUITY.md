- Goal (incl. success criteria):
  - Implement low-risk improvements and improve existing docs; design/introduce Context Assembly + orchestration modularization; pause at major UAT milestones.

- Constraints/Assumptions:
  - Do not remove/undo other devs’ positive changes (including untracked files like `AGENTS.md`).
  - Pause for UAT after major milestones.

- Key decisions:
  - No new docs; improve existing docs only.

- State:
  - Implemented web-search grounding in synthesis; needs UAT.

- Done:
  - Implemented stable agent IDs, fixed DebugLogger default path, and made RAG delete use embedding dimension.
  - Improved existing docs (README, ARCHITECTURE) with LLM-friendly edit boundaries and stability note.

- Now:
  - Await UAT on web-search grounding behavior.

- Next:
  - UAT for web-search grounding; proceed to orchestration modularization if approved.

- Open questions (UNCONFIRMED if needed):
  - UNCONFIRMED: Whether synthesis should hard-require citations when Web Search is used.

- Working set (files/ids/):
  - `Sources/FoundationChatCore/Services/ContextAssemblyService.swift`
  - `Sources/FoundationChatCore/Agents/Orchestration/DelegationDecider.swift`
  - `Sources/FoundationChatCore/Agents/Orchestration/OrchestratorPattern.swift`
  - `Sources/FoundationChatCore/Agents/Specialized/WebSearchAgent.swift`
  - `Sources/FoundationChatCore/Services/AgentService.swift`
  - `Sources/FoundationChatCore/Constants/AppConstants.swift`
  - `Sources/FoundationChatCore/Agents/Specialized/FileReaderAgent.swift`
  - `Sources/FoundationChatCore/Agents/Specialized/CodeAnalysisAgent.swift`
  - `Sources/FoundationChatCore/Agents/Specialized/DataAnalysisAgent.swift`
  - `Sources/FoundationChatCore/Agents/Specialized/VisionAgent.swift`
  - `Sources/FoundationChatCore/Agents/AgentOrchestrator.swift`
  - `Sources/FoundationChatCore/Utilities/DebugLogger.swift`
  - `Sources/FoundationChatCore/Services/RAGService.swift`
  - `README.md`
  - `ARCHITECTURE.md`
