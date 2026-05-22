import SwiftUI

struct TerminalTranscriptDetailView: View {
    @Environment(TerminalTranscriptStore.self) private var store

    let session: TerminalTranscriptSession
    let primaryActionTitle: String
    let primaryActionSystemImage: String
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    @State private var transcriptText: String = "Loading transcript..."

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(LoomTheme.hairline)
            ScrollView(.vertical, showsIndicators: true) {
                Text(transcriptText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LoomTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(red: 0.018, green: 0.022, blue: 0.026))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LoomTheme.panel)
        .task {
            transcriptText = store.readTranscriptText(for: session)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(LoomTheme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Text(session.displayCwd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LoomTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                store.revealTranscript(session)
            } label: {
                Label("Reveal File", systemImage: "doc.text.magnifyingglass")
            }
            .help("Reveal the saved transcript file in Finder")
            .accessibilityLabel("Reveal transcript file in Finder")

            Button {
                onPrimaryAction()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionSystemImage)
            }
            .help(primaryActionTitle)
            .accessibilityLabel(primaryActionTitle)

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close transcript preview")
        }
        .padding(14)
    }
}
