import SwiftUI
import AppKit

struct CrashReportSheet: View {
    let report: CrashReport
    let onDismiss: () -> Void

    @State private var copied = false

    private static let repo = "BigBeardedMan/Loom"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                Text("Loom crashed last time")
                    .font(.headline)
            }
            Text("A previous run ended unexpectedly. Details below. Please file an issue so I can fix it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(report.body)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(minHeight: 180, maxHeight: 320)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button(copied ? "Copied" : "Copy details") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(report.body, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }
                Button("Report on GitHub") {
                    if let url = buildIssueURL() {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Dismiss") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func buildIssueURL() -> URL? {
        let title = "Loom crashed: \(firstMessage(in: report.body))"
        let body = """
        **Version:** \(report.version)
        **Arch:** \(report.arch)
        **Captured:** \(report.timestamp)

        Steps to reproduce:
        1.
        2.
        3.

        ```
        \(truncate(report.body, 6000))
        ```
        """
        var comps = URLComponents(string: "https://github.com/\(Self.repo)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "crash,macos")
        ]
        return comps?.url
    }

    private func firstMessage(in body: String) -> String {
        for line in body.split(separator: "\n") {
            if line.hasPrefix("Message:") {
                return String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            }
        }
        return body.split(separator: "\n").first.map(String.init) ?? "unknown"
    }

    private func truncate(_ s: String, _ n: Int) -> String {
        if s.count <= n { return s }
        return String(s.prefix(n)) + "\n…[truncated]"
    }
}
