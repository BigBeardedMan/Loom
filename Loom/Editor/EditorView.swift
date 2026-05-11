import SwiftUI
import AppKit

/// NSViewRepresentable around NSTextView that applies regex-based
/// syntax highlighting on every edit. Used by EditorPaneView when a
/// file is open; falls back to plain rendering for unknown extensions.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.86)
        textView.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.04, blue: 0.045, alpha: 1)
        textView.drawsBackground = true
        textView.insertionPointColor = NSColor.white.withAlphaComponent(0.85)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.language = language
        context.coordinator.applyHighlight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.language = language
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected
            context.coordinator.applyHighlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var language: SyntaxLanguage = .plain
        private var pendingHighlight: DispatchWorkItem?

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text = textView.string
            // Debounce the highlight pass so fast typing stays smooth.
            pendingHighlight?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.applyHighlight()
            }
            pendingHighlight = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
        }

        func applyHighlight() {
            guard let textView, let storage = textView.textStorage else { return }
            let selected = textView.selectedRanges
            SyntaxHighlighter.shared.highlight(storage, language: language)
            textView.selectedRanges = selected
        }
    }
}
