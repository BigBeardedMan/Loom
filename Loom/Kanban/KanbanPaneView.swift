import SwiftUI

/// Runs pane: live mirror of CLI agent task lists plus graph-ledger task
/// projections. The Kanban data model still exists in SwiftData so
/// previously-saved cards aren't lost, but the pane no longer renders them.
struct KanbanPaneView: View {
    @Environment(LiveAgentTasksService.self) private var liveAgentTasks
    @State private var confirmClearAll: Bool = false
    @State private var runSummaries: [AgentGraphRunSummary] = []
    @State private var projectedRunGroups: [LiveAgentTaskGroup] = []
    @State private var expandedRunID: String?
    @State private var loadingRunID: String?
    @State private var runEventsByID: [String: [AgentGraphEvent]] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            if visibleTaskGroups.isEmpty && runSummaries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleTaskGroups) { group in
                            sessionHeader(group, isHistorical: !isLiveGroup(group))
                            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { idx, task in
                                taskRow(task)
                                if idx < group.tasks.count - 1 {
                                    Divider().overlay(LoomTheme.hairline)
                                        .padding(.leading, 38)
                                }
                            }
                        }
                        if !runSummaries.isEmpty {
                            historyHeader
                            ForEach(runSummaries) { summary in
                                historyRow(summary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(LoomTheme.panel)
        .task {
            await refreshRunHistory()
        }
        .confirmationDialog(
            "Clear all task data?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                liveAgentTasks.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(clearAllMessage)
        }
    }

    private var visibleTaskGroups: [LiveAgentTaskGroup] {
        let liveIDs = Set(liveAgentTasks.groups.map(\.id))
        return liveAgentTasks.groups + projectedRunGroups.filter { !liveIDs.contains($0.id) }
    }

    private var visibleTasks: [LiveAgentTask] {
        visibleTaskGroups.flatMap(\.tasks)
    }

    private func isLiveGroup(_ group: LiveAgentTaskGroup) -> Bool {
        liveAgentTasks.groups.contains { $0.id == group.id }
    }

    private func sessionHeader(_ group: LiveAgentTaskGroup, isHistorical: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.source.systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(group.source.brandColor)
            Text(group.displayName)
                .font(.system(size: 10, weight: .semibold))
            Text(group.sessionID.prefix(8))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let headline = group.headline {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(headline)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            if isHistorical {
                Text("History")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
            }
            Spacer()
            Text("\(group.tasks.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            if !isHistorical {
                Button {
                    liveAgentTasks.clear(group: group)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(clearHelp(for: group))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LoomTheme.inset)
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
    }

    private var header: some View {
        HStack(spacing: 8) {
            let sessionCount = visibleTaskGroups.count
            if sessionCount == 0 {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("No active sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LoomTheme.orange)
                Text(sessionCount == 1 ? "1 session" : "\(sessionCount) sessions")
                    .font(.system(size: 11, weight: .medium))
            }
            Spacer()
            if !visibleTasks.isEmpty {
                Text("\(visibleTasks.count) tasks")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
            Button {
                liveAgentTasks.refresh()
                Task { await refreshRunHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh now")

            if !liveAgentTasks.groups.isEmpty {
                Button {
                    confirmClearAll = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear all visible run sessions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(LoomTheme.inset)
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
    }

    private var historyHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text("Recent runs")
                .font(.system(size: 10, weight: .semibold))
            Text("\(runSummaries.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LoomTheme.inset)
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
    }

    private func historyRow(_ summary: AgentGraphRunSummary) -> some View {
        VStack(spacing: 0) {
            Button {
                toggleHistory(summary)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    historyStatusIcon(summary.status)
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 6) {
                            Text(historySourceLabel(summary))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(summary.status.capitalized)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(historyStatusColor(summary.status))
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(summary.lastActivity, style: .relative)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(summary.id.prefix(8))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(historySummaryChips(summary).joined(separator: " · "))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Image(systemName: expandedRunID == summary.id ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if expandedRunID == summary.id {
                timeline(for: summary)
            }
        }
        .contextMenu {
            Button("Copy run id") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary.id, forType: .string)
            }
            Button("Copy ledger path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary.ledgerPath, forType: .string)
            }
            Button("Reveal ledger in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: summary.ledgerPath)
                ])
            }
        }
    }

    @ViewBuilder
    private func timeline(for summary: AgentGraphRunSummary) -> some View {
        if loadingRunID == summary.id {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                Text("Loading timeline")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 40)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.12))
        } else {
            let events = runEventsByID[summary.id] ?? []
            if events.isEmpty {
                Text("No ledger events found for this run.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 40)
                    .padding(.trailing, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.12))
            } else {
                ForEach(events.sorted { $0.occurredAt < $1.occurredAt }) { event in
                    timelineRow(event)
                }
            }
        }
    }

    private func timelineRow(_ event: AgentGraphEvent) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: timelineIcon(for: event.type))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(timelineColor(for: event.type))
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(timelineLabel(for: event.type))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(event.occurredAt, style: .time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                if let text = timelineText(for: event) {
                    Text(text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                let chips = timelineChips(for: event)
                if !chips.isEmpty {
                    Text(chips.joined(separator: " · "))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.12))
    }

    private func taskRow(_ task: LiveAgentTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(task.status)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle(for: task))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(task.status == .completed ? Color.secondary : Color.primary)
                    .strikethrough(task.status == .completed)
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(task.sourceLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    if task.status != .pending {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(task.status.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(statusColor(task.status))
                    }
                }
                .padding(.top, 1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy task title") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.subject, forType: .string)
            }
        }
    }

    private var clearAllMessage: String {
        let labels = Array(Set(liveAgentTasks.groups.map(\.displayName))).sorted()
        let labelText: String
        if labels.count <= 3 {
            labelText = labels.joined(separator: ", ")
        } else {
            labelText = labels.prefix(3).joined(separator: ", ") + ", and \(labels.count - 3) more"
        }
        return "Clears every visible session\(labelText.isEmpty ? "" : " for \(labelText)"). File-backed task sessions delete their task JSON files; log-backed sessions such as Codex are hidden until their task plan updates, so stuck sessions stay gone and active sessions reappear on the next plan update."
    }

    private func clearHelp(for group: LiveAgentTaskGroup) -> String {
        switch group.source {
        case .claude, .lmstudio:
            return "Clear \(group.displayName) task files"
        case .codex, .gemini, .ollama, .openAICompatible:
            return "Hide \(group.displayName) until it next updates"
        }
    }

    private func displayTitle(for task: LiveAgentTask) -> String {
        if task.status == .inProgress, !task.activeForm.isEmpty {
            return task.activeForm
        }
        return task.subject
    }

    @ViewBuilder
    private func statusIcon(_ status: LiveAgentTaskStatus) -> some View {
        switch status {
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .pending:
            Circle()
                .stroke(Color.secondary.opacity(0.55), lineWidth: 1.5)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.46))
        case .cancelled:
            Image(systemName: "xmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
        case .deleted:
            Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    private func statusColor(_ status: LiveAgentTaskStatus) -> Color {
        switch status {
        case .inProgress: return Color(red: 0.96, green: 0.77, blue: 0.20)
        case .pending:    return .secondary
        case .completed:  return Color(red: 0.23, green: 0.86, blue: 0.46)
        case .cancelled:  return Color(red: 0.95, green: 0.39, blue: 0.18)
        case .deleted:    return .secondary.opacity(0.5)
        }
    }

    @ViewBuilder
    private func historyStatusIcon(_ status: String) -> some View {
        switch status.lowercased() {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.46))
        case "failed":
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
        case "cancelled":
            Image(systemName: "xmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
        default:
            Circle()
                .stroke(Color.secondary.opacity(0.55), lineWidth: 1.5)
                .frame(width: 12, height: 12)
        }
    }

    private func historyStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed": return Color(red: 0.23, green: 0.86, blue: 0.46)
        case "failed", "cancelled": return Color(red: 0.95, green: 0.39, blue: 0.18)
        default: return .secondary
        }
    }

    private func historySourceLabel(_ summary: AgentGraphRunSummary) -> String {
        let label = [summary.source, summary.modelLabel]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return label.isEmpty ? "Run" : label
    }

    private func historySummaryChips(_ summary: AgentGraphRunSummary) -> [String] {
        var chips = ["\(summary.eventCount) events"]
        if summary.toolEventCount > 0 {
            chips.append("\(summary.toolEventCount) tool events")
        }
        if summary.taskCount > 0 {
            chips.append("\(summary.taskCount) tasks")
        }
        if !summary.toolNames.isEmpty {
            chips.append(summary.toolNames.prefix(3).joined(separator: ", "))
        }
        if let gitBranch = summary.gitBranch, gitBranch != "HEAD" {
            chips.append("branch: \(gitBranch)")
        }
        if let gitHead = summary.gitHead {
            chips.append("head: \(gitHead)")
        }
        if summary.gitDirty == true {
            chips.append("dirty")
        }
        if let workspacePath = summary.workspacePath, !workspacePath.isEmpty {
            chips.append(URL(fileURLWithPath: workspacePath).lastPathComponent)
        } else if let gitRoot = summary.gitRoot, !gitRoot.isEmpty {
            chips.append(URL(fileURLWithPath: gitRoot).lastPathComponent)
        }
        return chips
    }

    private func toggleHistory(_ summary: AgentGraphRunSummary) {
        if expandedRunID == summary.id {
            expandedRunID = nil
            return
        }
        expandedRunID = summary.id
        guard runEventsByID[summary.id] == nil else { return }
        loadingRunID = summary.id
        Task {
            let events = (try? await AgentGraphLedger.shared.events(rootRunID: summary.id)) ?? []
            runEventsByID[summary.id] = events
            if loadingRunID == summary.id {
                loadingRunID = nil
            }
        }
    }

    private func timelineLabel(for type: AgentGraphEventType) -> String {
        switch type {
        case .graphCreated: return "Graph created"
        case .runStarted: return "Run started"
        case .runHeartbeat: return "Heartbeat"
        case .runStatusChanged: return "Run status"
        case .runCompleted: return "Run completed"
        case .runFailed: return "Run failed"
        case .runCancelled: return "Run cancelled"
        case .taskCreated: return "Task created"
        case .taskUpdated: return "Task updated"
        case .taskStatusChanged: return "Task status"
        case .edgeCreated: return "Lineage edge"
        case .spawnRequested: return "Spawn requested"
        case .spawnStarted: return "Spawn started"
        case .spawnCompleted: return "Spawn completed"
        case .spawnFailed: return "Spawn failed"
        case .toolStarted: return "Tool started"
        case .toolCompleted: return "Tool completed"
        case .handoffWritten: return "Handoff written"
        case .handoffAccepted: return "Handoff accepted"
        case .handoffRejected: return "Handoff rejected"
        case .attentionRequested: return "Attention requested"
        case .andonPaused: return "Andon paused"
        case .andonResumed: return "Andon resumed"
        }
    }

    private func timelineIcon(for type: AgentGraphEventType) -> String {
        switch type {
        case .graphCreated, .edgeCreated: return "point.3.connected.trianglepath.dotted"
        case .runCompleted: return "checkmark.circle.fill"
        case .runFailed: return "exclamationmark.circle.fill"
        case .runCancelled: return "xmark.circle"
        case .taskCreated, .taskUpdated, .taskStatusChanged: return "checklist"
        case .toolStarted, .toolCompleted: return "wrench.and.screwdriver"
        case .handoffWritten, .handoffAccepted, .handoffRejected: return "arrow.left.arrow.right"
        case .attentionRequested: return "bell.badge"
        case .andonPaused, .andonResumed: return "pause.circle"
        default: return "circle"
        }
    }

    private func timelineColor(for type: AgentGraphEventType) -> Color {
        switch type {
        case .runCompleted, .spawnCompleted, .handoffAccepted: return Color(red: 0.23, green: 0.86, blue: 0.46)
        case .runFailed, .spawnFailed, .handoffRejected, .attentionRequested: return Color(red: 0.95, green: 0.39, blue: 0.18)
        case .runCancelled, .andonPaused: return .secondary
        case .toolStarted, .toolCompleted: return LoomTheme.purple
        case .taskCreated, .taskUpdated, .taskStatusChanged: return LoomTheme.orange
        default: return .secondary
        }
    }

    private func timelineText(for event: AgentGraphEvent) -> String? {
        let text = [event.title, event.summary, event.payload["reviewSummary"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        return text.isEmpty ? nil : text
    }

    private func timelineChips(for event: AgentGraphEvent) -> [String] {
        var chips: [String] = []
        for key in ["tool", "status", "taskID", "subject", "activeForm"] {
            if let value = event.payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                chips.append("\(key): \(value)")
            }
        }
        if let branch = event.payload["gitBranch"], !branch.isEmpty, branch != "HEAD" {
            chips.append("branch: \(branch)")
        }
        if let head = event.payload["gitHead"], !head.isEmpty {
            chips.append("head: \(head)")
        }
        if event.payload["gitDirty"] == "true" {
            chips.append("dirty")
        }
        if let parent = event.parentRunID, !parent.isEmpty {
            chips.append("parent: \(parent.prefix(8))")
        }
        if let workspacePath = event.workspacePath, !workspacePath.isEmpty {
            chips.append(URL(fileURLWithPath: workspacePath).lastPathComponent)
        } else if let gitRoot = event.payload["gitRoot"], !gitRoot.isEmpty {
            chips.append(URL(fileURLWithPath: gitRoot).lastPathComponent)
        }
        if let permissionMode = event.permissionMode, !permissionMode.isEmpty {
            chips.append(permissionMode)
        }
        return chips
    }

    private func refreshRunHistory() async {
        let summaries = (try? await AgentGraphLedger.shared.summaries()) ?? []
        runSummaries = summaries

        var projected: [LiveAgentTaskGroup] = []
        for summary in summaries.prefix(8) {
            let events = (try? await AgentGraphLedger.shared.events(rootRunID: summary.id)) ?? []
            projected.append(contentsOf: AgentGraphProjection.taskGroups(from: events))
        }
        var seen: Set<String> = []
        projectedRunGroups = projected.filter { group in
            seen.insert(group.id).inserted
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No runs yet")
                .font(.system(size: 13, weight: .medium))
            Text("Run claude, codex, or lmstudio in the terminal. Their live task lists will mirror here in real time.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
