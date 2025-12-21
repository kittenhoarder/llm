//
//  OrchestrationDiagramView.swift
//  FoundationChatMac
//
//  Visualization of agent orchestration progress and workflow
//

import SwiftUI
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
                    
                    // Task decomposition tree
                    // #region debug log
                    let _ = {
                        Task {
                            await DebugLogger.shared.log(
                                location: "OrchestrationDiagramView.swift:body",
                                message: "Checking decomposition for tree view",
                                hypothesisId: "G",
                                data: [
                                    "hasDecomposition": state.decomposition != nil,
                                    "subtaskCount": state.decomposition?.subtasks.count ?? 0,
                                    "subtaskStatesCount": state.subtaskStates.count,
                                    "parallelGroupsCount": state.parallelGroups.count
                                ]
                            )
                        }
                    }()
                    // #endregion
                    
                    if let decomposition = state.decomposition, !decomposition.subtasks.isEmpty {
                        TaskDecompositionTreeView(
                            decomposition: decomposition,
                            subtaskStates: state.subtaskStates,
                            parallelGroups: state.parallelGroups,
                            colorScheme: colorScheme
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        // #region debug log
                        let _ = {
                            Task {
                                await DebugLogger.shared.log(
                                    location: "OrchestrationDiagramView.swift:body",
                                    message: "Decomposition tree not shown",
                                    hypothesisId: "G",
                                    data: [
                                        "hasDecomposition": state.decomposition != nil,
                                        "subtaskCount": state.decomposition?.subtasks.count ?? 0,
                                        "isEmpty": state.decomposition?.subtasks.isEmpty ?? true
                                    ]
                                )
                            }
                        }()
                        // #endregion
                    }
                    
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

// MARK: - Task Decomposition Tree

@available(macOS 26.0, *)
struct TaskDecompositionTreeView: View {
    let decomposition: TaskDecomposition
    let subtaskStates: [UUID: SubtaskExecutionState]
    let parallelGroups: [[DecomposedSubtask]]
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Decomposition")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textPrimary(for: colorScheme))
            
            if !parallelGroups.isEmpty {
                // Show parallel groups
                ForEach(Array(parallelGroups.enumerated()), id: \.offset) { groupIndex, group in
                    VStack(alignment: .leading, spacing: 6) {
                        if group.count > 1 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                                Text("Parallel Group \(groupIndex + 1)")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.textSecondary(for: colorScheme))
                            }
                            .padding(.leading, 8)
                        }
                        
                        ForEach(group) { subtask in
                            SubtaskNodeView(
                                subtask: subtask,
                                state: subtaskStates[subtask.id] ?? .pending,
                                colorScheme: colorScheme
                            )
                        }
                    }
                    .padding(.leading, group.count > 1 ? 12 : 0)
                }
            } else {
                // Fallback: show all subtasks sequentially
                ForEach(decomposition.subtasks) { subtask in
                    SubtaskNodeView(
                        subtask: subtask,
                        state: subtaskStates[subtask.id] ?? .pending,
                        colorScheme: colorScheme
                    )
                }
            }
        }
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
            case .failed:
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
            case .failed(let error):
                Text("Failed: \(error)")
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
        case .failed: return Color.red.opacity(0.1)
        }
    }
    
    private var borderColor: Color {
        switch state {
        case .pending: return Theme.border(for: colorScheme)
        case .inProgress: return Theme.accent(for: colorScheme)
        case .completed: return Color.green
        case .failed: return Color.red
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

