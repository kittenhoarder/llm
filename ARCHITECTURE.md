# Architecture Documentation

## Coordinator-Based Orchestration Pattern

The system uses a **coordinator pattern** where a single coordinator agent analyzes tasks, decomposes them, delegates to specialized agents, and synthesizes results.

## Core Components

### 1. AgentService

High-level service managing agent lifecycle and message processing.

**File**: `Sources/FoundationChatCore/Services/AgentService.swift`

**Key Methods**:
- `processMessage(_:conversationId:conversation:tokenBudget:)` - Main entry point
- `initializeDefaultAgents()` - Registers all agents including coordinator

**Coordinator Creation**:
```swift
let coordinator = BaseAgent(
    name: "Coordinator",
    description: "Coordinates tasks and delegates to specialized agents",
    capabilities: [.generalReasoning]
)
await orchestrator.setPattern(OrchestratorPattern(coordinator: coordinatorAgent))
```

### 2. AgentOrchestrator

Manages orchestration patterns and agent selection.

**File**: `Sources/FoundationChatCore/Agents/AgentOrchestrator.swift`

**Responsibilities**:
- Pattern management (orchestrator pattern - coordinator-based)
- Agent selection based on task capabilities
- Task execution via current pattern

**Note**: The orchestrator is only used when "Use Coordinator" toggle is enabled. When disabled, messages are processed directly by the selected agent without orchestration.

### 3. OrchestratorPattern

Implements the coordinator pattern execution flow.

**File**: `Sources/FoundationChatCore/Agents/Orchestration/OrchestratorPattern.swift`

**Execution Flow**:

```
1. Coordinator Analysis
   ├── Analyzes task
   ├── Breaks down into subtasks
   └── Determines agent assignments

2. Task Decomposition
   ├── TaskDecompositionParser extracts subtasks
   ├── DynamicPruner removes redundant subtasks
   └── Groups subtasks by dependencies

3. Agent Execution
   ├── Parallel execution when possible
   ├── Sequential execution for dependencies
   └── Context sharing between agents

4. Result Synthesis
   ├── ResultSummarizer summarizes agent outputs
   ├── Coordinator synthesizes final result
   └── Token tracking and budget enforcement
```

**Key Components**:
- `TaskDecompositionParser`: Parses coordinator's analysis into structured subtasks
- `DynamicPruner`: Removes redundant or duplicate subtasks
- `ProgressiveContextBuilder`: Builds isolated context for each agent
- `ResultSummarizer`: Summarizes agent results before synthesis
- `AgentTokenTracker`: Tracks token usage per agent
- `TokenBudgetGuard`: Enforces token budgets

### 4. Coordinator Agent

The coordinator is a `BaseAgent` with `generalReasoning` capability. It has no special tools - it uses pure reasoning to:
- Analyze complex tasks
- Break them into subtasks
- Assign subtasks to appropriate agents
- Synthesize results from multiple agents

**Capabilities**: `[.generalReasoning]`

**Tools**: None (pure reasoning agent)

### 5. Specialized Agents

#### FileReaderAgent

**Capabilities**: `[.fileReading]`

**Tools**: None (reads files directly)

**Features**:
- Reads text, markdown, Swift, JSON, CSV files
- 10MB file size limit
- File content caching
- Basic PDF support (limited)

**File**: `Sources/FoundationChatCore/Agents/Specialized/FileReaderAgent.swift`

#### WebSearchAgent

**Capabilities**: `[.webSearch]`

**Tools**: `[SerpAPIFoundationTool()]`

**Features**:
- Web search via SerpAPI (Google search)
- Real-time information retrieval
- Requires SerpAPI API key

**File**: `Sources/FoundationChatCore/Agents/Specialized/WebSearchAgent.swift`

#### CodeAnalysisAgent

**Capabilities**: `[.codeAnalysis]`

**Tools**: File reading capabilities

**Features**:
- Analyzes code files
- Understands code structure
- Provides code insights

**File**: `Sources/FoundationChatCore/Agents/Specialized/CodeAnalysisAgent.swift`

#### DataAnalysisAgent

**Capabilities**: `[.dataAnalysis]`

**Tools**: Data processing capabilities

**Features**:
- Performs calculations
- Analyzes data
- Statistical operations

**File**: `Sources/FoundationChatCore/Agents/Specialized/DataAnalysisAgent.swift`

## Task Decomposition Flow

### Step 1: Coordinator Analysis

The coordinator receives a task analysis prompt:

```
Analyze the following task and break it down into subtasks. For each subtask, specify:
1. The specific task description
2. Which agent should handle it (from available agents)
3. What capabilities are needed
4. Dependencies on other subtasks (if any)
5. Whether it can run in parallel with other subtasks
```

### Step 2: Parsing

`TaskDecompositionParser` extracts structured subtasks from the coordinator's response:
- Subtask descriptions
- Agent assignments
- Required capabilities
- Dependencies
- Parallel execution flags

### Step 3: Pruning

`DynamicPruner` removes:
- Redundant subtasks
- Duplicate operations
- Unnecessary steps

### Step 4: Execution

Subtasks are grouped by dependencies:
- **Parallel groups**: Subtasks with no dependencies execute simultaneously
- **Sequential groups**: Dependent subtasks execute in order

Each agent receives:
- Isolated context (via `ProgressiveContextBuilder`)
- Relevant conversation history
- Previous results from other agents
- Token budget constraints

### Step 5: Synthesis

The coordinator receives:
- Summarized results from all agents
- Full context of the task
- Token budget for synthesis

It synthesizes a coherent final response.

## Context Sharing

### AgentContext Structure

```swift
public struct AgentContext: Sendable {
    var conversationHistory: [Message]
    var toolResults: [String: String]
    var fileReferences: [String]
    var agentState: [UUID: [String: String]]
    var metadata: [String: String]
}
```

### Context Isolation

`ProgressiveContextBuilder` creates isolated contexts for each agent:
- Only relevant conversation history (via SVDB semantic retrieval when enabled)
- Only relevant tool results
- Token budget enforcement
- Prevents context pollution between agents

**SVDB Integration:**
- When SVDB optimization is enabled, context building uses semantic retrieval
- Each agent receives only messages relevant to their subtask
- Recent messages are always included for context continuity

### Context Merging

After agent execution, contexts are merged:
- Tool results aggregated
- File references combined
- Agent state preserved
- Metadata updated

## Token Management

### Token Tracking

`AgentTokenTracker` tracks:
- Prompt tokens per agent
- Response tokens per agent
- Context tokens per agent
- Tool call tokens
- Total task tokens

### Budget Enforcement

`TokenBudgetGuard` enforces budgets by:
- Summarizing context when budget exceeded
- Truncating conversation history
- Prioritizing recent messages
- Using `ContextSummarizer` for compression

### Context Optimization

The system uses multiple strategies to optimize context:

1. **SVDB Semantic Retrieval** (primary, when enabled):
   - Retrieves only relevant messages based on current query
   - Automatically indexes all messages in SVDB
   - Falls back to summarization if SVDB unavailable

2. **Message Summarization** (fallback):
   - Summarizes old messages when context exceeds budget
   - Keeps recent messages full
   - Uses `MessageCompactor` for compression

**File**: `Sources/FoundationChatCore/Services/ContextOptimizer.swift`

### Token Savings

The system tracks token savings vs. single-agent approach:
- Coordinator analysis tokens
- Specialized agent tokens (isolated contexts)
- Synthesis tokens
- **SVDB-based context optimization savings** (new)
- Total vs. estimated single-agent usage

#### SVDB-Based Context Optimization

The system uses SVDB (Semantic Vector Database) to optimize conversation context and reduce token usage:

**How it works:**
1. **Message Indexing**: All conversation messages are automatically indexed in SVDB when saved
2. **Semantic Retrieval**: When building context, the system uses the current user message as a query to retrieve only relevant messages from SVDB
3. **Recent Messages**: Last N messages (configurable, default: 3) are always included regardless of relevance
4. **Token Savings**: Only relevant messages are sent to the LLM instead of full conversation history

**Configuration:**
- `useSVDBForContextOptimization` (UserDefaults): Enable/disable SVDB optimization (default: true)
- `svdbContextTopK` (UserDefaults): Number of relevant messages to retrieve (default: 10)
- `svdbContextRecentMessages` (UserDefaults): Number of recent messages to always include (default: 3)

**Files:**
- `Sources/FoundationChatCore/Services/RAGService.swift` - Message indexing and retrieval
- `Sources/FoundationChatCore/Services/ContextOptimizer.swift` - SVDB-based optimization
- `Sources/FoundationChatCore/Services/AgentService.swift` - Context building with SVDB

**Expected Savings:**
- **Before**: Full conversation history sent (could be 1000s of tokens)
- **After**: Only top-K relevant messages + recent messages (typically 200-500 tokens)
- **Expected Savings**: 50-80% reduction in context tokens for long conversations

**Migration:**
- New messages are automatically indexed when saved
- Use `RAGService.indexExistingConversations()` to retroactively index existing conversations

## Agent Registry

`AgentRegistry` manages all available agents:

**File**: `Sources/FoundationChatCore/Agents/AgentRegistry.swift`

**Features**:
- Agent registration by ID
- Agent lookup by ID, name, or capability
- Capability-based indexing
- Thread-safe (actor-based)

## Orchestration Patterns

The system supports two processing modes:

1. **Single-Agent Mode** (default, recommended): Direct agent processing
   - Selected agent processes messages directly
   - No orchestration overhead
   - Agent's tools are automatically available
   - Used when "Use Coordinator" toggle is OFF

2. **OrchestratorPattern** (experimental): Coordinator delegates to specialists
   - Coordinator analyzes tasks and delegates to specialized agents
   - Used when "Use Coordinator" toggle is ON
   - Still in development

**File**: `Sources/FoundationChatCore/Agents/Orchestration/`

**Note**: Other patterns (CollaborativePattern, HierarchicalPattern) exist in the codebase but are not used in the UI.

## Error Handling

### Agent Errors

Agents return `AgentResult` with:
- `success: Bool`
- `error: String?`
- `content: String` (even on error)

### Orchestration Errors

- `AgentOrchestratorError.noAgentsAvailable`: No agents match task requirements
- Fallback to capability-based matching if decomposition fails
- Coordinator handles errors gracefully

## Performance Optimizations

1. **Lazy ModelService Creation**: Agents create ModelService only when needed
2. **Parallel Execution**: Independent subtasks run simultaneously
3. **Context Isolation**: Reduces token usage per agent
4. **Result Summarization**: Compresses results before synthesis
5. **File Caching**: FileReaderAgent caches file contents

## Conversation Creation

### User Flow

1. User clicks "New Conversation" button
2. System creates a single-agent conversation (`.singleAgent` type)
3. Agent configuration is loaded from Settings:
   - Enabled agent IDs from `enabledAgentIds` UserDefaults key
   - Coordinator pattern enabled/disabled from `useCoordinator` UserDefaults key
4. Conversation is created with `AgentConfiguration` containing enabled agents

### Two Operating Modes

#### Single-Agent Mode (Use Coordinator: OFF)
- **Recommended mode** - known to work reliably
- User selects exactly one specialized agent (Web Search, File Reader, Code Analysis, or Data Analysis)
- Messages are processed directly by the selected agent using its ModelService
- Agent's tools are automatically available
- No orchestration overhead
- **Implementation**: `AgentService.processSingleAgentMessage()`

#### Orchestrator Mode (Use Coordinator: ON)
- **Experimental mode** - still in development
- User can select multiple specialized agents
- Coordinator agent is automatically included
- Messages are processed through the orchestrator pattern
- Coordinator analyzes tasks, delegates to specialized agents, and synthesizes results
- **Implementation**: `AgentService.processMessage()` with orchestrator pattern

### Settings Configuration

Agent selection is managed in Settings:
- **Agents & Tools** section allows enabling/disabling specialized agents
- Coordinator agent is **not** user-selectable (automatically included in orchestrator mode)
- **Use Coordinator** toggle switches between single-agent and orchestrator modes
- When single-agent mode: Exactly one agent must be selected (first selected is used)
- When orchestrator mode: At least one specialized agent must be selected
- Changes apply to new conversations only (existing conversations keep their config)

**Files**:
- `Sources/FoundationChatMac/Views/SettingsView.swift` - Settings UI
- `Sources/FoundationChatMac/ViewModels/ChatViewModel.swift` - Conversation creation logic

## Extension Points

### Adding New Agents

1. Create agent class extending `BaseAgent`
2. Define capabilities
3. Add tools if needed
4. Register in `AgentService.initializeDefaultAgents()`
5. Agent will appear in Settings for user selection

### Adding New Capabilities

1. Add to `AgentCapability` enum
2. Update agent implementations
3. Update capability matching logic

### Custom Orchestration Patterns

1. Implement `OrchestrationPattern` protocol
2. Define execution flow
3. Set pattern via `AgentOrchestrator.setPattern()`

## Data Flow Diagram

```
User Message
    ↓
AgentService.processMessage()
    ↓
AgentOrchestrator.execute()
    ↓
OrchestratorPattern.execute()
    ↓
┌─────────────────────────────────────┐
│ Coordinator Analysis                │
│ - Analyzes task                     │
│ - Breaks into subtasks              │
│ - Assigns agents                    │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Task Decomposition                  │
│ - Parser extracts subtasks          │
│ - Pruner removes redundancy         │
│ - Groups by dependencies             │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Agent Execution (Parallel/Seq)      │
│ - FileReaderAgent                   │
│ - WebSearchAgent                    │
│ - CodeAnalysisAgent                 │
│ - DataAnalysisAgent                 │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Result Synthesis                     │
│ - Summarize results                 │
│ - Coordinator synthesizes           │
│ - Token tracking                    │
└─────────────────────────────────────┘
    ↓
Final Response
```

