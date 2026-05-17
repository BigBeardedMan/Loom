import SwiftUI

struct TerminalTranscriptDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TerminalTranscriptStore.self) private var store

    let session: TerminalTranscriptSession
    let onStartFreshShell: () -> Void

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
        .frame(width: 860, height: 620)
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
                onStartFreshShell()
            } label: {
                Label("Start Fresh Shell Here", systemImage: "plus.rectangle.on.rectangle")
            }
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }
}
