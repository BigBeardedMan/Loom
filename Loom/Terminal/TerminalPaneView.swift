import SwiftUI
import SwiftTerm

/// Top-level terminal block view. Renders a single pane, a 2- or 3-pane
/// HSplitView/VSplitView depending on `terminalSplitAxis`, or a 2x2 quad
/// when the pane count hits 4. Each pane keeps its own header so split
/// + close + cwd live next to the terminal they describe.
struct TerminalPaneView: View {
    @Environment(WorkspaceLayout.self) private var layout
    let block: WorkspaceBlock

    var body: some View {
        // SwiftUI only diffs an array of children when each child is keyed.
        // Capturing identifier+index pairs lets us hand stable identities to
        // ForEach while keeping the splits inexpensive to recompose when the
        // user adds or removes a pane.
        let sessions = block.terminalSessions
        Group {
            switch sessions.count {
            case 0:
                emptyState
            case 1:
                pane(for: sessions[0])
            case 2:
                two(sessions)
            case 3:
                three(sessions)
            default:
                quad(sessions)
            }
        }
        .background(Color(red: 0.018, green: 0.022, blue: 0.026))
    }

    private var emptyState: some View {
        VStack {
            Text("No terminal session")
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func two(_ sessions: [TerminalSession]) -> some View {
        if block.terminalSplitAxis == .vertical {
            VSplitView {
                pane(for: sessions[0])
                pane(for: sessions[1])
            }
        } else {
            HSplitView {
                pane(for: sessions[0])
                pane(for: sessions[1])
            }
        }
    }

    @ViewBuilder
    private func three(_ sessions: [TerminalSession]) -> some View {
        if block.terminalSplitAxis == .vertical {
            VSplitView {
                pane(for: sessions[0])
                pane(for: sessions[1])
                pane(for: sessions[2])
            }
        } else {
            HSplitView {
                pane(for: sessions[0])
                pane(for: sessions[1])
                pane(for: sessions[2])
            }
        }
    }

    @ViewBuilder
    private func quad(_ sessions: [TerminalSession]) -> some View {
        // Always 2x2 at four panes. Axis is intentionally ignored here so
        // the user has a predictable destination state when growing past
        // three panes.
        VSplitView {
            HSplitView {
                pane(for: sessions[0])
                pane(for: sessions[1])
            }
            HSplitView {
                pane(for: sessions[2])
                pane(for: sessions[3])
            }
        }
    }

    private func pane(for session: TerminalSession) -> some View {
        TerminalSinglePane(block: block, session: session)
            .frame(minWidth: 240, minHeight: 140)
    }
}

/// One terminal pane: header strip + the SwiftTerm-backed PTY view. The
/// header carries the cwd label, split + axis-toggle + close buttons, and
/// the existing Ctrl-C button. All split actions delegate to the parent
/// block so a single source of truth owns the session list.
private struct TerminalSinglePane: View {
    let block: WorkspaceBlock
    let session: TerminalSession
    @Environment(WorkspaceLayout.self) private var layout
    @Environment(CommandHistoryService.self) private var history
    /// Per-pane toggle: live PTY view (default) or a stack of cards
    /// rendered from the JSONL log filtered to this session. Local @State
    /// because flipping modes is a per-glance preference, not something
    /// worth persisting across launches.
    @State private var showCards: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if showCards {
                InlineCardsView(sessionID: session.id.uuidString)
                    .environment(history)
                    .environment(layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TerminalNSView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(red: 0.018, green: 0.022, blue: 0.026))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.46))
            Text(displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.middle)
            if !session.lastReportedTitle.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.3))
                Text(session.lastReportedTitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            controlButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.32))
        .overlay(Divider().overlay(Color.white.opacity(0.10)), alignment: .bottom)
    }

    @ViewBuilder
    private var controlButtons: some View {
        // Cards/Live toggle. Cards mode renders the recent commands for this
        // session as a vertical stack instead of the live PTY. Useful when
        // the user wants to skim what they did without scrolling raw output.
        Button {
            showCards.toggle()
        } label: {
            Image(systemName: showCards ? "terminal" : "list.bullet.rectangle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(showCards ? "Show live terminal" : "Show command cards")

        // Axis toggle only makes sense at 2 or 3 panes; at 1 it has no effect
        // and at 4 the layout is locked to a 2x2 quad.
        if (2...3).contains(block.terminalSessions.count) {
            Button {
                block.toggleTerminalSplitAxis()
            } label: {
                Image(systemName: block.terminalSplitAxis == .horizontal
                      ? "rectangle.split.1x2"
                      : "rectangle.split.2x1")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help(block.terminalSplitAxis == .horizontal
                  ? "Stack panes vertically"
                  : "Lay panes out horizontally")
        }

        if block.terminalSessions.count < WorkspaceBlock.maxTerminalPanes {
            Button {
                block.addTerminalPane(defaultCwd: layout.defaultCwd)
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Split — add a terminal pane to this block")
        }

        if block.terminalSessions.count > 1 {
            Button {
                block.removeTerminalPane(id: session.id)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Close this pane")
        }

        Button {
            session.sendInterrupt()
        } label: {
            Image(systemName: "stop.circle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("Send Ctrl-C")
    }

    private var displayPath: String {
        let path = session.cwd.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

struct TerminalNSView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LoomTerminalView {
        session.start()
        return session.terminalView
    }

    func updateNSView(_ nsView: LoomTerminalView, context: Context) {}
}

/// Renders the per-session slice of the JSONL command log as a stack of
/// cards. Lives inside the Terminal pane (not the standalone Commands
/// panel), filtered to the PTY's `LOOM_SESSION_ID`, so the user can flip
/// from raw scrollback to a structured "what did I just run here" view
/// without leaving the pane.
private struct InlineCardsView: View {
    let sessionID: String
    @Environment(CommandHistoryService.self) private var history
    @Environment(WorkspaceLayout.self) private var layout
    @State private var copiedID: String?

    var body: some View {
        let records = history.records.filter { $0.sessionID == sessionID }
        if records.isEmpty {
            empty
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(records) { record in
                        card(record)
                    }
                }
                .padding(8)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text("No commands captured yet for this session.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Text("Switch to the live terminal and run something. The card view will populate after the next prompt.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func card(_ record: CommandRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                statusBadge(for: record)
                Text(record.command)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Button {
                    copy(record)
                } label: {
                    Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Copy command")
                Button {
                    layout.firstTerminalSession()?.submit(record.command)
                } label: {
                    Image(systemName: "arrow.uturn.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Rerun in active terminal")
            }
            HStack(spacing: 6) {
                Text(displayCwd(record.cwd))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Text("·")
                    .foregroundStyle(.white.opacity(0.3))
                Text(record.started, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                if record.duration >= 1 {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Text("\(Int(record.duration))s")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if !record.succeeded {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Text("exit \(record.exitCode)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func statusBadge(for record: CommandRecord) -> some View {
        if record.succeeded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.46))
                .font(.system(size: 11))
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color(red: 0.95, green: 0.39, blue: 0.18))
                .font(.system(size: 11))
        }
    }

    private func displayCwd(_ raw: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if raw == home { return "~" }
        if raw.hasPrefix(home) { return "~" + raw.dropFirst(home.count) }
        return raw
    }

    private func copy(_ record: CommandRecord) {
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
