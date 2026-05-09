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

    var body: some View {
        VStack(spacing: 0) {
            header
            TerminalNSView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
