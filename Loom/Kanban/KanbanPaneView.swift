import SwiftUI

/// Tasks pane: live mirror of the running CLI agent's task list. The Kanban
/// data model still exists in SwiftData so previously-saved cards aren't lost,
/// but the pane no longer renders them — only Claude/Codex/Gemini's own task
/// state shows up here.
struct KanbanPaneView: View {
    @Environment(LiveAgentTasksService.self) private var liveAgentTasks
    @State private var confirmClearAll: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if liveAgentTasks.groups.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(liveAgentTasks.groups) { group in
                            sessionHeader(group)
                            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { idx, task in
                                taskRow(task)
                                if idx < group.tasks.count - 1 {
                                    Divider().overlay(LoomTheme.hairline)
                                        .padding(.leading, 38)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(LoomTheme.panel)
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

    private func sessionHeader(_ group: LiveAgentTaskGroup) -> some View {
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
            Spacer()
            Text("\(group.tasks.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LoomTheme.inset)
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
    }

    private var header: some View {
        HStack(spacing: 8) {
            let sessionCount = liveAgentTasks.groups.count
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
            if !liveAgentTasks.tasks.isEmpty {
                Text("\(liveAgentTasks.tasks.count) tasks")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
            Button {
                liveAgentTasks.refresh()
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
                .help("Clear all visible task sessions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(LoomTheme.inset)
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No tasks yet")
                .font(.system(size: 13, weight: .medium))
            Text("Run claude or codex in the terminal — their task lists will mirror here in real time.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
