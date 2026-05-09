import SwiftUI

/// Surfaces the JSONL log Loom's shell shim writes as a list of recent
/// commands. Each row is one card: command text, cwd, duration, exit
/// code badge. Click to copy the command to the pasteboard, or to send
/// it back into the active terminal so the user can rerun it.
struct CommandHistoryPaneView: View {
    @Environment(CommandHistoryService.self) private var history
    @Environment(WorkspaceLayout.self) private var layout
    @State private var filterToWorkspace: Bool = true
    @State private var copiedID: String?
    @State private var expandedID: String?
    @State private var expandedOutputCache: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .background(LoomTheme.panel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LoomTheme.green)
            Text("Recent Commands")
                .font(.system(size: 11, weight: .semibold))
            if let cwd = layout.defaultCwd.path.split(separator: "/").last,
               filterToWorkspace {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(String(cwd))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $filterToWorkspace) {
                Text("Workspace only")
                    .font(.system(size: 10))
            }
            .toggleStyle(.checkbox)
            Button {
                history.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Refresh now")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(LoomTheme.inset)
        .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        let visible = visibleRecords
        if visible.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(visible) { record in
                        row(record)
                    }
                }
                .padding(8)
            }
        }
    }

    private var visibleRecords: [CommandRecord] {
        if filterToWorkspace {
            return history.records(in: layout.defaultCwd.path)
        }
        return history.records
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(filterToWorkspace
                 ? "No commands logged for this workspace yet."
                 : "No commands logged yet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Run something in a Loom terminal pane and it'll show up here.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func toggleExpand(_ record: CommandRecord) {
        if expandedID == record.id {
            expandedID = nil
            return
        }
        if expandedOutputCache[record.id] == nil, let path = record.outputPath {
            expandedOutputCache[record.id] = CommandHistoryService.readCapturedOutput(at: path)
        }
        expandedID = record.id
    }

    private func row(_ record: CommandRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                statusBadge(for: record)
                Text(record.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LoomTheme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Button {
                    copyToPasteboard(record)
                } label: {
                    Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Copy command to pasteboard")
                if let session = layout.firstTerminalSession() {
                    Button {
                        session.submit(record.command, capture: true)
                    } label: {
                        Image(systemName: "arrow.uturn.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help("Send to active terminal (captures output)")
                }
                if record.hasCapturedOutput {
                    Button {
                        toggleExpand(record)
                    } label: {
                        Image(systemName: expandedID == record.id ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(expandedID == record.id ? "Hide output" : "Show captured output")
                }
            }
            HStack(spacing: 6) {
                Text(displayCwd(record.cwd))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(record.started, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if record.duration >= 1 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(Int(record.duration))s")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            if expandedID == record.id, let body = expandedOutputCache[record.id] {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(body.isEmpty ? "(empty)" : body)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LoomTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 240)
                .background(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(LoomTheme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(LoomTheme.softPanel)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func statusBadge(for record: CommandRecord) -> some View {
        Group {
            if record.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LoomTheme.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(LoomTheme.orange)
            }
        }
        .font(.system(size: 11))
        .help(record.succeeded ? "Exit 0" : "Exit \(record.exitCode)")
    }

    private func displayCwd(_ raw: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if raw == home { return "~" }
        if raw.hasPrefix(home) { return "~" + raw.dropFirst(home.count) }
        return raw
    }

    private func copyToPasteboard(_ record: CommandRecord) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(record.command, forType: .string)
        copiedID = record.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if copiedID == record.id { copiedID = nil }
            }
        }
    }
}
