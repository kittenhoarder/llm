# Foundation Chat

Single-agent chat system using Apple's FoundationModels with coordinator-based orchestration.

## Overview

Foundation Chat is a Swift-based agent system that uses a **coordinator pattern** to orchestrate specialized agents. The coordinator analyzes tasks, decomposes them into subtasks, delegates to specialized agents, and synthesizes results. All conversations are single-agent conversations with agent selection configured via Settings.

## Architecture

The system supports two modes:

### Single-Agent Mode (Recommended)
```
User Message
    ↓
AgentService.processSingleAgentMessage()
    ↓
Selected Agent (direct processing)
    ├── WebSearchAgent
    ├── FileReaderAgent
    ├── CodeAnalysisAgent
    └── DataAnalysisAgent
    ↓
Final Response
```

### Orchestrator Mode (Experimental)
```
User Message
    ↓
AgentService.processMessage()
    ↓
AgentOrchestrator (OrchestratorPattern)
    ↓
Coordinator Agent (analyzes & decomposes)
    ↓
Specialized Agents (execute subtasks)
    ├── FileReaderAgent
    ├── WebSearchAgent
    ├── CodeAnalysisAgent
    └── DataAnalysisAgent
    ↓
Coordinator (synthesizes results)
    ↓
Final Response
```

## Quick Start

### Requirements

- macOS 26.0+ or iOS 26.0+
- Apple Intelligence enabled
- Swift 6.2+

### Build

```bash
swift build
```

### Run CLI

```bash
# Interactive chat
swift run foundation-chat chat

# Single message
swift run foundation-chat chat -m "Analyze this codebase"
```

## Key Components

### Coordinator Agent

The coordinator (`BaseAgent` with `generalReasoning` capability) is responsible for:
- Task analysis and decomposition
- Subtask assignment to specialized agents
- Result synthesis

**Location**: `Sources/FoundationChatCore/Services/AgentService.swift` (lines 64-72)

### Specialized Agents

- **FileReaderAgent**: Reads and processes files (text, markdown, Swift, JSON, CSV)
- **WebSearchAgent**: Performs web searches using SerpAPI
- **CodeAnalysisAgent**: Analyzes code files
- **DataAnalysisAgent**: Performs data analysis and calculations

**Location**: `Sources/FoundationChatCore/Agents/Specialized/`

### Orchestration Pattern

`OrchestratorPattern` implements the coordinator pattern:
1. Coordinator analyzes task
2. Task decomposition parser extracts subtasks
3. Dynamic pruner removes redundant subtasks
4. Specialized agents execute subtasks (parallel when possible)
5. Coordinator synthesizes results

**Location**: `Sources/FoundationChatCore/Agents/Orchestration/OrchestratorPattern.swift`

## Development Guide

### Adding a New Agent

1. Create agent class in `Sources/FoundationChatCore/Agents/Specialized/`:

```swift
public class MyAgent: BaseAgent {
    public init() {
        super.init(
            name: "My Agent",
            description: "Does something specific",
            capabilities: [.myCapability],
            tools: [MyTool()]
        )
    }
}
```

2. Register in `AgentService.initializeDefaultAgents()`:

```swift
await registry.register(MyAgent())
```

3. Add capability to `AgentCapability` enum if needed.

4. The agent will automatically appear in Settings for user selection.

### Conversation Creation

- All new conversations are created as single-agent conversations (`.singleAgent` type)
- Agent selection is configured in Settings → Agents & Tools
- **Use Coordinator** toggle switches between:
  - **OFF**: Single-agent mode (recommended) - direct agent processing
  - **ON**: Orchestrator mode (experimental) - coordinator-based orchestration
- Coordinator agent is automatically included in orchestrator mode (not user-selectable)
- Changes to agent selection apply to new conversations only

### Task Flow

1. User message → `AgentService.processMessage()`
2. Creates `AgentTask` with required capabilities
3. `AgentOrchestrator.execute()` uses `OrchestratorPattern`
4. Coordinator analyzes and decomposes
5. Specialized agents execute subtasks
6. Coordinator synthesizes final result

### Context Sharing

Agents share context via `AgentContext`:
- `conversationHistory`: Previous messages
- `toolResults`: Results from tool calls
- `fileReferences`: File paths
- `agentState`: Agent-specific state

**Location**: `Sources/FoundationChatCore/Agents/AgentContext.swift`

## Project Structure

```
Sources/
├── FoundationChatCore/        # Core library
│   ├── Agents/
│   │   ├── Orchestration/     # Orchestration patterns
│   │   └── Specialized/       # Specialized agents
│   ├── Services/              # AgentService, ModelService, etc.
│   ├── Models/                # AgentTask, AgentContext, etc.
│   └── Tools/                 # Tool implementations
├── FoundationChat/            # CLI executable
├── FoundationChatMac/         # macOS app library
└── FoundationChatiOS/         # iOS app library
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture documentation
- [KNOWN_ISSUES.md](KNOWN_ISSUES.md) - Known issues and workarounds

## Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter AgentRegistryTests
```

## License

[Add license information]

