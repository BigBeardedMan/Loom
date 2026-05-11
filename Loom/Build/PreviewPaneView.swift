import SwiftUI
import WebKit
import Observation

@Observable
@MainActor
final class WebController: NSObject {
    let webView: WKWebView
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var currentURL: URL?
    var lastError: String?

    private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        attachObservers()
    }

    func load(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Enter a URL or path."
            return
        }

        let normalized = normalize(trimmed)
        guard let url = URL(string: normalized) else {
            lastError = "Invalid URL: \(trimmed)"
            return
        }
        lastError = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.url != nil {
            webView.reload()
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    private func attachObservers() {
        observers.append(webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
            Task { @MainActor in self?.canGoBack = webView.canGoBack }
        })
        observers.append(webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
            Task { @MainActor in self?.canGoForward = webView.canGoForward }
        })
        observers.append(webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
            Task { @MainActor in self?.isLoading = webView.isLoading }
        })
        observers.append(webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            Task { @MainActor in self?.currentURL = webView.url }
        })
    }

    private func normalize(_ raw: String) -> String {
        if raw.contains("://") { return raw }
        if raw.hasPrefix("/") || raw.hasPrefix("~") {
            let expanded = NSString(string: raw).expandingTildeInPath
            return URL(fileURLWithPath: expanded).absoluteString
        }
        if raw.hasPrefix("localhost") || raw.first?.isNumber == true {
            return "http://" + raw
        }
        return "https://" + raw
    }
}

extension WebController: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in self.lastError = nil }
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PreviewPaneView: View {
    let block: WorkspaceBlock
    @State private var urlInput: String = ""

    /// Pulled off the block so the WKWebView (and its loaded page) survive
    /// workspace switches. WorkspaceBlock.init creates one for `.preview`
    /// blocks; the fallback only fires if a future code path forgets to.
    private var controller: WebController {
        if let existing = block.webController { return existing }
        let made = WebController()
        block.webController = made
        return made
    }

    private var defaultURL: String { block.defaultPreviewURL }

    var body: some View {
        VStack(spacing: 0) {
            urlBar

            if controller.currentURL == nil {
                emptyState
            } else {
                ZStack {
                    WebViewContainer(webView: controller.webView)
                        .background(Color.white)

                    if controller.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(12)
                    }
                }
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }
        }
        .background(Color(red: 0.035, green: 0.04, blue: 0.045))
        .onAppear { ensurePreviewLoaded() }
        .onChange(of: block.id) { _, _ in ensurePreviewLoaded() }
        .onChange(of: block.effectivePreviewURL) { _, _ in ensurePreviewLoaded() }
    }

    private var urlBar: some View {
        HStack(spacing: 6) {
            Button { controller.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(!controller.canGoBack)
            .opacity(controller.canGoBack ? 1 : 0.35)

            Button { controller.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(!controller.canGoForward)
            .opacity(controller.canGoForward ? 1 : 0.35)

            Button { controller.reload() } label: {
                Image(systemName: controller.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)

            TextField(defaultURL, text: $urlInput, prompt: Text(defaultURL).foregroundColor(.white.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onSubmit { go() }

            Button("Go") { go() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.32))
        .overlay(Divider().overlay(Color.white.opacity(0.10)), alignment: .bottom)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Loading \(defaultURL)…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Edit the URL above to point at a different dev server.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.035, green: 0.04, blue: 0.045))
    }

    private func ensurePreviewLoaded() {
        let target = block.effectivePreviewURL
        urlInput = target
        // Skip the load when the WKWebView already has the right page —
        // workspace switches re-mount the SwiftUI view, but the controller is
        // pulled from the block so the existing page stays valid.
        if controller.currentURL?.absoluteString == target { return }
        controller.load(urlString: target)
    }

    private func go() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Treat "matches the auto default" as no override so the slot keeps
        // tracking its port if the user later renumbers preview blocks.
        block.previewURL = trimmed == defaultURL ? nil : trimmed
        controller.load(urlString: trimmed)
    }
}
