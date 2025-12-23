# Testing Orchestration Visualization - Debug Guide

## Quick Debug Steps

### 1. Verify Settings
1. Open Settings (Cmd+,)
2. Check "Use Coordinator" is **ON**
3. Verify at least 2 agents are enabled (e.g., Web Search + File Reader)
4. Check console for: `💬 useCoordinator: true`
   - Note: in non-DEBUG builds, some debug logs are suppressed. Use a DEBUG build for full visibility.

### 2. Create New Conversation
- Click "New Conversation" (Cmd+N) - **Important**: Must be a NEW conversation
- Check console for conversation creation logs

### 3. Send Test Message
Try this message to trigger orchestration:
```
Search the web for Swift best practices and analyze the results
```

### 4. Check Console Output
Look for these log messages in order:

**Expected Flow:**
```
💬 Conversation check - Type: singleAgent, Has Config: true, Is Agent: true
💬 useCoordinator: true, pattern: orchestrator, agents: X
🤖 Using orchestrator mode for message processing...
📊 Initializing orchestration visualization...
📊 Orchestration state initialized: true
🤖 AgentService obtained, calling processMessage()...
🎯 OrchestratorPattern: Starting execution...
📊 Handling progress event: ...
📊 Updated orchestration state - Phase: ..., Subtasks: ...
```

### 5. What to Look For

**If you see "Using orchestrator mode":**
- ✅ Orchestration is enabled
- Check if "📊 Orchestration state initialized: true" appears
- Watch for "📊 Handling progress event" messages

**If you see "Using single-agent mode":**
- ❌ Orchestration is NOT enabled
- Check Settings → "Use Coordinator" toggle
- Verify multiple agents are enabled

**If you see "Using regular ModelService":**
- ❌ Conversation is not configured as agent conversation
- Create a NEW conversation after enabling orchestration

### 6. Visual Checks

**During Processing:**
- Look below the "Thinking..." indicator
- Diagram should appear automatically
- Phase indicator should show current phase
- Subtask nodes should appear as they're created

**After Completion:**
- Diagram should persist
- Metrics summary should appear
- All subtasks should show "Completed" status

### 7. Common Issues

**Issue: Only see "Thinking..." animation**
- **Cause**: Orchestration state not being set or diagram not showing
- **Fix**: Check console logs - if you see "📊 Orchestration state initialized: true" but no diagram, the view might not be updating

**Issue: No orchestration logs in console**
- **Cause**: Not using orchestrator mode
- **Fix**: Verify Settings → "Use Coordinator" is ON and multiple agents enabled

**Issue: Diagram appears but doesn't update**
- **Cause**: Progress events not being received
- **Fix**: Check for "📊 Handling progress event" logs - if missing, events aren't being emitted

### 8. Manual Verification

Add this temporary debug view to see the state:

In ChatView.swift, add after the message bubble:
```swift
// Debug: Show orchestration state
if let state = orchestrationState {
    Text("DEBUG: Phase = \(state.currentPhase.rawValue), Subtasks = \(state.subtaskStates.count)")
        .font(.caption)
        .foregroundColor(.red)
}
```

### 9. Test Prompts That Should Trigger Orchestration

**Simple (should delegate):**
- "Search for information about X"
- "Read this file and summarize it"
- "Analyze this code and search for similar patterns"

**Complex (definitely delegates):**
- "Search the web, read files, analyze code, and provide recommendations"
- "I need you to: 1) search online, 2) analyze files, 3) calculate statistics"

**Won't trigger (direct response):**
- "Hello"
- "Thanks"
- Simple greetings

### 10. Force Diagram to Show

If diagram exists but is hidden, the "Show Orchestration" button should appear below assistant messages. Click it to reveal the diagram.

