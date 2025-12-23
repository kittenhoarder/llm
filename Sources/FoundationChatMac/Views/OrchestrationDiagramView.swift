//
//  OrchestrationDiagramView.swift
//  FoundationChatMac
//
//  Visualization of agent orchestration progress and workflow
//

import SwiftUI
import AppKit
import FoundationChatCore

@available(macOS 26.0, *)
struct OrchestrationDiagramView: View {
    let state: OrchestrationState
    let colorScheme: ColorScheme
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with collapse/expand
            HStack {
                Image(systemName: "flowchart")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent(for: colorScheme))
                
                Text("Orchestration Flow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                
                Spacer()
                
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surfaceElevated(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Phase indicator
                    PhaseIndicatorView(phase: state.currentPhase, colorScheme: colorScheme)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    
                    // Delegation decision (if available)
                    if let shouldDelegate = state.shouldDelegate {
                        DelegationDecisionView(shouldDelegate: shouldDelegate, reason: state.delegationReason, colorScheme: colorScheme)
                    }
                    
                    // Orchestration timeline
                    OrchestrationTimelineView(
                        state: state,
                        colorScheme: colorScheme
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    
                    // Metrics summary (when complete)
                    if let metrics = state.metrics {
                        MetricsSummaryView(metrics: metrics, colorScheme: colorScheme)
                    }
                    
                    // Error display (if failed)
                    if let error = state.error {
                        ErrorView(error: error)
                    }
                }
                .padding(12)
                .background(Theme.surface(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

// MARK: - Phase Indicator

@available(macOS 26.0, *)
struct PhaseIndicatorView: View {
    let phase: OrchestrationPhase
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            // Phase icon
            Image(systemName: phaseIcon)
                .font(.system(size: 14))
                .foregroundColor(phaseColor)
                .frame(width: 20, height: 20)
            
            Text("Phase: \(phase.rawValue)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary(for: colorScheme))
            
            if phase == .execution {
                // Show progress indicator for execution phase
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(phaseColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(phaseColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var phaseIcon: String {
        switch phase {
        case .decision: return "questionmark.circle"
        case .analysis: return "brain.head.profile"
        case .decomposition: return "list.bullet.rectangle"
        case .execution: return "gearshape.2"
        case .synthesis: return "arrow.triangle.merge"
        case .complete: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var phaseColor: Color {
        switch phase {
        case .decision: return .blue
        case .analysis: return .purple
        case .decomposition: return .orange
        case .execution: return .green
        case .synthesis: return .cyan
        case .complete: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Delegation Decision

@available(macOS 26.0, *)
struct DelegationDecisionView: View {
    let shouldDelegate: Bool
    let reason: String?
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: shouldDelegate ? "arrow.triangle.branch" : "arrow.right")
                .font(.system(size: 12))
                .foregroundColor(shouldDelegate ? Theme.accent(for: colorScheme) : Theme.textSecondary(for: colorScheme))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(shouldDelegate ? "Delegating to specialized agents" : "Responding directly")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                
                if let reason = reason, shouldDelegate {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
        .background(Theme.surfaceElevated(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Orchestration Timeline

@available(macOS 26.0, *)
struct OrchestrationTimelineView: View {
    let state: OrchestrationState
    let colorScheme: ColorScheme
    @State private var startTime: Date?
    
    private func copyAllEventsToClipboard() {
        let sortedEvents = state.eventHistory.sorted { $0.timestamp < $1.timestamp }
        let start = sortedEvents.first?.timestamp ?? Date()
        
        var lines: [String] = []
        for event in sortedEvents {
            let timestamp = formatTimestamp(event.timestamp, relativeTo: start)
            var line = "\(timestamp) | \(event.description)"
            if let agentName = event.agentName {
                line += " | Agent: \(agentName)"
            }
            lines.append(line)
        }
        
        let text = lines.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func formatTimestamp(_ timestamp: Date, relativeTo startTime: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: timestamp)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Orchestration Timeline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                
                Spacer()
                
                // Copy all events button
                if !state.eventHistory.isEmpty {
                    Button(action: {
                        copyAllEventsToClipboard()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                            Text("Copy Timeline")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(Theme.accent(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if state.eventHistory.isEmpty {
                // Show current state if no events yet
                if let decomposition = state.decomposition, !decomposition.subtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(decomposition.subtasks.count) subtasks created")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary(for: colorScheme))
                        Text("Timeline will appear as orchestration progresses")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textSecondary(for: colorScheme).opacity(0.7))
                    }
                } else {
                    Text("Waiting for orchestration to begin...")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
            } else {
                // Display timeline - ensure events are sorted by timestamp
                let sortedEvents = state.eventHistory.sorted { $0.timestamp < $1.timestamp }
                TimelineContentView(
                    events: sortedEvents,
                    currentPhase: state.currentPhase,
                    subtaskStates: state.subtaskStates,
                    colorScheme: colorScheme,
                    startTime: startTime ?? sortedEvents.first?.timestamp ?? Date()
                )
                .onAppear {
                    if startTime == nil {
                        startTime = sortedEvents.first?.timestamp ?? Date()
                    }
                }
            }
        }
    }
}

@available(macOS 26.0, *)
struct TimelineContentView: View {
    let events: [OrchestrationEvent]
    let currentPhase: OrchestrationPhase
    let subtaskStates: [UUID: SubtaskExecutionState]
    let colorScheme: ColorScheme
    let startTime: Date
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    HStack(alignment: .top, spacing: 0) {
                        // Timeline line and node
                        VStack(spacing: 0) {
                            // Timeline node
                            Circle()
                                .fill(nodeColor(for: event))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Theme.background(for: colorScheme), lineWidth: 2)
                                )
                                .shadow(color: nodeColor(for: event).opacity(isEventActive(event) ? 0.5 : 0), radius: isEventActive(event) ? 4 : 0)
                                .animation(isEventActive(event) ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default, value: isEventActive(event))
                            
                            // Connecting line (except for last event)
                            if index < events.count - 1 {
                                Rectangle()
                                    .fill(Theme.border(for: colorScheme))
                                    .frame(width: 2, height: 22)
                                    .padding(.vertical, 2)
                            }
                        }
                        .frame(width: 30)
                        
                        // Event content
                        TimelineEventNode(
                            event: event,
                            index: index,
                            isActive: isEventActive(event),
                            relativeToStart: startTime,
                            colorScheme: colorScheme
                        )
                        .padding(.leading, 8)
                        .padding(.bottom, index < events.count - 1 ? 4 : 0)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 400)
    }
    
    private func isEventActive(_ event: OrchestrationEvent) -> Bool {
        switch event.eventType {
        case .subtaskStarted:
            if let subtaskId = event.subtaskId,
               case .inProgress = subtaskStates[subtaskId] {
                return true
            }
            return false
        case .phaseChange:
            // Check if this is the current phase
            if let phase = event.metadata["phase"],
               phase == currentPhase.rawValue {
                return true
            }
            return false
        default:
            return false
        }
    }
    
    private func nodeColor(for event: OrchestrationEvent) -> Color {
        switch event.eventType {
        case .phaseChange:
            return .blue
        case .delegationDecision:
            return .purple
        case .taskDecomposition:
            return .orange
        case .subtaskStarted:
            return .green
        case .subtaskCompleted:
            return .green
        case .subtaskFailed:
            return .red
        case .subtaskRetry:
            return .orange
        case .synthesisStarted, .synthesisCompleted:
            return .cyan
        case .orchestrationCompleted:
            return .green
        case .orchestrationFailed:
            return .red
        }
    }
}

@available(macOS 26.0, *)
struct TimelineEventNode: View {
    let event: OrchestrationEvent
    let index: Int
    let isActive: Bool
    let relativeToStart: Date
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTimestamp(event.timestamp, relativeTo: relativeToStart))
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Theme.textSecondary(for: colorScheme))
                .frame(width: 85, alignment: .leading)
                .lineLimit(1)
            
            // Event content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: eventIcon)
                        .font(.system(size: 10))
                        .foregroundColor(nodeColor)
                    
                    Text(eventDescription)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .foregroundColor(Theme.textPrimary(for: colorScheme))
                        .lineLimit(2)
                }
                
                if let agentName = event.agentName {
                    Text("Agent: \(agentName)")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textSecondary(for: colorScheme))
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isActive ? nodeColor.opacity(0.1) : Theme.surfaceElevated(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? nodeColor : Theme.border(for: colorScheme), lineWidth: isActive ? 2 : 1)
        )
    }
    
    private var nodeColor: Color {
        switch event.eventType {
        case .phaseChange:
            return .blue
        case .delegationDecision:
            return .purple
        case .taskDecomposition:
            return .orange
        case .subtaskStarted:
            return .green
        case .subtaskCompleted:
            return .green
        case .subtaskFailed:
            return .red
        case .subtaskRetry:
            return .orange
        case .synthesisStarted, .synthesisCompleted:
            return .cyan
        case .orchestrationCompleted:
            return .green
        case .orchestrationFailed:
            return .red
        }
    }
    
    private var eventIcon: String {
        switch event.eventType {
        case .phaseChange:
            return "arrow.right.circle.fill"
        case .delegationDecision:
            return "arrow.triangle.branch"
        case .taskDecomposition:
            return "list.bullet.rectangle"
        case .subtaskStarted:
            return "play.circle.fill"
        case .subtaskCompleted:
            return "checkmark.circle.fill"
        case .subtaskFailed:
            return "xmark.circle.fill"
        case .subtaskRetry:
            return "arrow.clockwise.circle.fill"
        case .synthesisStarted:
            return "arrow.triangle.merge"
        case .synthesisCompleted:
            return "checkmark.circle.fill"
        case .orchestrationCompleted:
            return "checkmark.circle.fill"
        case .orchestrationFailed:
            return "xmark.circle.fill"
        }
    }
    
    private var eventDescription: String {
        return event.description
    }
    
    private func formatTimestamp(_ timestamp: Date, relativeTo startTime: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: timestamp)
    }
}

// MARK: - Subtask Node

@available(macOS 26.0, *)
struct SubtaskNodeView: View {
    let subtask: DecomposedSubtask
    let state: SubtaskExecutionState
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status indicator
            statusIndicator
            
            VStack(alignment: .leading, spacing: 4) {
                // Subtask description
                Text(subtask.description)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textPrimary(for: colorScheme))
                    .lineLimit(2)
                
                // Agent assignment and status
                HStack(spacing: 6) {
                    if let agentName = subtask.agentName {
                        Label(agentName, systemImage: "person.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textSecondary(for: colorScheme))
                    }
                    
                    statusText
                }
            }
            
            Spacer()
        }
        .padding(8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var statusIndicator: some View {
        Group {
            switch state {
            case .pending:
                Circle()
                    .fill(Theme.textSecondary(for: colorScheme).opacity(0.3))
                    .frame(width: 8, height: 8)
            case .inProgress(_, _, _):
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                    .transition(.scale.combined(with: .opacity))
            case .failed(_, _):
                Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
    }
    
    private var statusText: some View {
        Group {
            switch state {
            case .pending:
                Text("Pending")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.textSecondary(for: colorScheme))
            case .inProgress(_, let agentName, _):
                Text("\(agentName) working...")
                    .font(.system(size: 8))
                    .foregroundColor(Theme.accent(for: colorScheme))
            case .completed:
                Text("Completed")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
            case .failed(let error, let retryAttempts):
                let errorText = String(describing: error)
                let retryInfo = retryAttempts.isEmpty ? "" : " (\(retryAttempts.count) retries)"
                Text("Failed: \(errorText)\(retryInfo)")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
    
    private var backgroundColor: Color {
        switch state {
        case .pending: return Theme.surfaceElevated(for: colorScheme)
        case .inProgress: return Theme.accent(for: colorScheme).opacity(0.1)
        case .completed: return Color.green.opacity(0.1)
        case .failed(_, _): return Color.red.opacity(0.1)
        }
    }
    
    private var borderColor: Color {
        switch state {
        case .pending: return Theme.border(for: colorScheme)
        case .inProgress: return Theme.accent(for: colorScheme)
        case .completed: return Color.green
        case .failed(_, _): return Color.red
        }
    }
}

// MARK: - Metrics Summary

@available(macOS 26.0, *)
struct MetricsSummaryView: View {
    let metrics: DelegationMetrics
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Execution Summary")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textPrimary(for: colorScheme))
            
            VStack(alignment: .leading, spacing: 6) {
                MetricRow(label: "Subtasks Created", value: "\(metrics.subtasksCreated)", colorScheme: colorScheme)
                MetricRow(label: "Subtasks Pruned", value: "\(metrics.subtasksPruned)", colorScheme: colorScheme)
                MetricRow(label: "Agents Used", value: "\(metrics.agentsUsed)", colorScheme: colorScheme)
                MetricRow(label: "Total Tokens", value: "\(metrics.totalTokens)", colorScheme: colorScheme)
                MetricRow(label: "Token Savings", value: String(format: "%.1f%%", metrics.tokenSavingsPercentage), colorScheme: colorScheme)
                
                Divider()
                    .background(Theme.border(for: colorScheme))
                
                MetricRow(label: "Analysis Time", value: String(format: "%.2fs", metrics.executionTimeBreakdown.coordinatorAnalysisTime), colorScheme: colorScheme)
                MetricRow(label: "Execution Time", value: String(format: "%.2fs", metrics.executionTimeBreakdown.specializedAgentsTime), colorScheme: colorScheme)
                MetricRow(label: "Synthesis Time", value: String(format: "%.2fs", metrics.executionTimeBreakdown.coordinatorSynthesisTime), colorScheme: colorScheme)
                MetricRow(label: "Total Time", value: String(format: "%.2fs", metrics.executionTimeBreakdown.totalTime), colorScheme: colorScheme)
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

@available(macOS 26.0, *)
struct MetricRow: View {
    let label: String
    let value: String
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(Theme.textSecondary(for: colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.textPrimary(for: colorScheme))
        }
    }
}

// MARK: - Error View

@available(macOS 26.0, *)
struct ErrorView: View {
    let error: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
            
            Text(error)
                .font(.system(size: 10))
                .foregroundColor(.red)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

