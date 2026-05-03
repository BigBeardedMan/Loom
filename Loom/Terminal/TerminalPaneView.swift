import SwiftUI
import SwiftTerm

struct TerminalPaneView: View {
    let session: TerminalSession

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
            Button {
                session.sendInterrupt()
            } label: {
                Image(systemName: "stop.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Send Ctrl-C")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.32))
        .overlay(Divider().overlay(Color.white.opacity(0.10)), alignment: .bottom)
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
