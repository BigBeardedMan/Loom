import AppKit
import Darwin
import Foundation
import Observation
import SwiftTerm
import UniformTypeIdentifiers

/// PTY-backed shell session. Hosts a long-running login shell so interactive
/// CLIs (claude, gemini, codex) can run their TUIs and OAuth handoffs the same
/// way they do in Warp/iTerm.
@Observable
@MainActor
final class TerminalSession: Identifiable {
    let id = UUID()
    var cwd: URL
    var lastReportedTitle: String = ""

    /// The SwiftTerm view is created up-front and owned by the session so it
    /// keeps its scrollback and child process across SwiftUI mount cycles.
    let terminalView: LoomTerminalView
    private let bridge: ProcessBridge
    private var hasStarted = false

    init(cwd: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.cwd = cwd
        self.terminalView = LoomTerminalView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 480)
        )
        self.bridge = ProcessBridge()
        configureAppearance()
        bridge.session = self
        terminalView.processDelegate = bridge
    }

    /// Spawn `$SHELL -l` on first mount. Idempotent.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let env = makeEnvironment()
        // Pass argv[0] as "-zsh" so the shell treats itself as a login shell
        // and runs zprofile/zshrc — that's where Homebrew's PATH lands.
        let execName = "-" + (shellPath as NSString).lastPathComponent
        terminalView.startProcess(
            executable: shellPath,
            args: ["-l"],
            environment: env,
            execName: execName,
            currentDirectory: cwd.path
        )
    }

    /// Send a command into the live shell as if the user typed it.
    /// When `capture` is true and shell integration is enabled, wraps
    /// the command in the shim's `__loom_capture` helper so its
    /// stdout+stderr lands in `output/<stamp>-<pid>.out` and the matching
    /// `CommandRecord` carries an `outputPath`. Off by default to keep
    /// the legacy "send to terminal" semantics intact for callers that
    /// don't care about capture.
    func submit(_ command: String, capture: Bool = false) {
        start()
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if capture && Self.shellIntegrationEnabled {
            // Single-quote the command for `eval` inside the shim, escaping
            // any embedded single quotes via `'\''` (the canonical zsh /
            // bash idiom for closing-then-reopening a quoted string).
            let escaped = trimmed.replacingOccurrences(of: "'", with: "'\\''")
            terminalView.send(txt: "__loom_capture '\(escaped)'\n")
        } else {
            terminalView.send(txt: trimmed + "\n")
        }
    }

    /// Send a Ctrl-C to whatever is running.
    func sendInterrupt() {
        terminalView.send(txt: "\u{03}")
    }

    func cleanup() {
        terminalView.terminate()
    }

    var tabLabel: String {
        let path = cwd.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home) {
            let suffix = String(path.dropFirst(home.count))
            if suffix.isEmpty { return "~/" }
            return "~" + (suffix.split(separator: "/").last.map { "/\($0)" } ?? suffix)
        }
        if let last = path.split(separator: "/").last { return "/\(last)" }
        return "/"
    }

    /// Lowercased command name of whatever owns the PTY's foreground process
    /// group right now (e.g. "claude", "codex", "zsh"). Nil before the shell
    /// has spawned or after it exits.
    ///
    /// Read by the workspace sidebar so the "active sessions" badge reflects
    /// each terminal whose CLI agent is currently in the foreground — the
    /// previous on-disk-log heuristic missed terminals that were idle between
    /// turns or hadn't flushed in the last 5 minutes.
    var foregroundCommand: String? {
        let fd = terminalView.process.childfd
        guard fd >= 0 else { return nil }
        let pgid = tcgetpgrp(fd)
        guard pgid > 0 else { return nil }
        return Self.processName(pid: pgid)?.lowercased()
    }

    /// True when a known CLI agent (claude/codex/gemini) is the foreground
    /// process on this PTY — i.e. this terminal counts toward "active
    /// sessions" in the Prompt-workspace badge.
    var isRunningCLIAgent: Bool {
        guard let cmd = foregroundCommand else { return false }
        return Self.knownCLIAgents.contains(cmd)
    }

    /// CLI agents whose foreground state we recognize. Drives both the
    /// "active session" badge above and the click-to-position cursor logic
    /// in `LoomTerminalView` below.
    static let knownCLIAgents: Set<String> = ["claude", "codex", "gemini", "lmstudio"]

    fileprivate static func processName(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = mib.withUnsafeMutableBufferPointer { ptr in
            sysctl(ptr.baseAddress, UInt32(ptr.count), &info, &size, nil, 0)
        }
        guard result == 0, size > 0 else { return nil }
        return withUnsafeBytes(of: &info.kp_proc.p_comm) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let name = String(cString: base.assumingMemoryBound(to: CChar.self))
            return name.isEmpty ? nil : name
        }
    }

    fileprivate func updateReportedCwd(_ raw: String) {
        let path: String
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            path = url.path
        } else {
            path = raw
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        let url = URL(fileURLWithPath: path).standardized
        if url != cwd { cwd = url }
    }

    private func configureAppearance() {
        let font = NSFont(name: "Menlo", size: 12)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.font = font
        terminalView.nativeBackgroundColor = NSColor(srgbRed: 0.018, green: 0.022, blue: 0.026, alpha: 1)
        terminalView.nativeForegroundColor = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    }

    private func makeEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        // Don't forward credential-shaped variables that may have been set in
        // the parent environment when Loom launched. The PTY shell will source
        // the user's profile and re-export anything they actually want; what
        // we strip here are leaks, not config — Loom reads its own keys from
        // Keychain, not from the environment.
        for key in env.keys where Self.isSecretEnvKey(key) {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        env["TERM_PROGRAM"] = "Loom"
        env["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        // Loom shell integration: point zsh at the shim dir so each command
        // lands in history.jsonl. The shim sources the user's normal config
        // first, so behavior matches a stock login shell. Honors the
        // Settings → Shell toggle: when off, we don't override ZDOTDIR or
        // export the session id.
        if Self.shellIntegrationEnabled {
            env["ZDOTDIR"] = ShellIntegration.supportDirectory.path
            env["LOOM_SESSION_ID"] = id.uuidString
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    /// Reads the user's shell-integration preference. Treats a missing key
    /// as enabled so existing installs keep capturing history without an
    /// explicit opt-in toggle. Settings → Shell flips
    /// `loom.shellIntegration` to `false` to disable.
    static var shellIntegrationEnabled: Bool {
        UserDefaults.standard.object(forKey: "loom.shellIntegration") as? Bool ?? true
    }

    /// Heuristic match for "this env var probably holds a secret." Conservative
    /// — we'd rather skip a few legitimate non-secret keys than forward a real
    /// API token into every subprocess the user runs.
    private static func isSecretEnvKey(_ key: String) -> Bool {
        let upper = key.uppercased()
        let exact: Set<String> = [
            "ANTHROPIC_API_KEY",
            "OPENAI_API_KEY",
            "OPENAI_ORG_ID",
            "GOOGLE_API_KEY",
            "GEMINI_API_KEY",
            "GROQ_API_KEY",
            "MISTRAL_API_KEY",
            "DEEPSEEK_API_KEY",
            "XAI_API_KEY",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_SESSION_TOKEN",
            "AZURE_OPENAI_API_KEY",
            "HUGGINGFACE_TOKEN",
            "HF_TOKEN",
            "GITHUB_TOKEN",
            "GH_TOKEN",
            "NPM_TOKEN",
            "STRIPE_SECRET_KEY"
        ]
        if exact.contains(upper) { return true }
        // Catch-all suffixes for keys like FOO_API_KEY / BAR_SECRET_TOKEN.
        let suffixes = ["_API_KEY", "_SECRET_KEY", "_ACCESS_TOKEN", "_AUTH_TOKEN"]
        return suffixes.contains { upper.hasSuffix($0) }
    }
}

/// SwiftUI's mount/unmount during workspace switches briefly hands the view a
/// near-zero frame. The base class would propagate that as `cols=1` to the
/// PTY and the running shell reflows its output to one character per line.
/// Drop those tiny frames and only forward real ones.
///
/// Also hosts the click-to-position-cursor gesture: when the user single-
/// clicks on the same row as the shell cursor we send ESC[C / ESC[D bytes
/// to walk the cursor to the clicked column — same UX as Warp/iTerm2 with
/// shell integration. Implemented as a gesture recognizer (not a mouseDown
/// override) because SwiftTerm's `mouseDown` isn't `open`.
final class LoomTerminalView: LocalProcessTerminalView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installClickToPosition()
        registerForDraggedTypes(Self.imageDragPasteboardTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard newSize.width >= 80, newSize.height >= 40 else { return }
        super.setFrameSize(newSize)
    }

    // MARK: - Pasteboard

    /// Send the clipboard's string contents straight into the PTY without
    /// SwiftTerm's bracketed-paste wrapping. Wired to the Edit menu's
    /// **Paste as Plain Text** (⇧⌘V) and reused by `paste(_:)` when the
    /// "Always paste as plain text" toggle is on. Bracketed paste tells
    /// readline-aware shells "this is one paste event"; bypassing it
    /// avoids the CSI 200~/201~ markers that some apps render literally
    /// when they don't recognize the sequence.
    @objc func pasteAsPlainText(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        if insertImageArgument(from: pasteboard, allowRawImage: false) {
            return
        }
        if let text = pasteboard.string(forType: .string) {
            send(txt: text)
            return
        }
        _ = insertImageArgument(from: pasteboard)
    }

    override func paste(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        if UserDefaults.standard.bool(forKey: "loom.terminal.pasteAsPlainText") {
            pasteAsPlainText(sender)
        } else if insertImageArgument(from: pasteboard, allowRawImage: false) {
            return
        } else if pasteboard.string(forType: .string) == nil,
                  insertImageArgument(from: pasteboard) {
            return
        } else {
            super.paste(sender)
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(pasteAsPlainText(_:)) {
            return Self.canPasteTerminalContent(from: NSPasteboard.general)
        }
        if item.action == #selector(NSText.paste(_:)),
           Self.canPasteTerminalContent(from: NSPasteboard.general) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    @discardableResult
    private func insertImageArgument(
        from pasteboard: NSPasteboard,
        allowRawImage: Bool = true
    ) -> Bool {
        switch Self.clipboardImageURL(from: pasteboard, allowRawImage: allowRawImage) {
        case .file(let url):
            let argument = "--image \(Self.zshSingleQuoted(url.path)) "
            send(txt: argument)
            return true
        case .noImage:
            return false
        case .unavailable:
            return true
        }
    }

    private static let imageDragPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.image")
    ]

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.pasteboardContainsImage(from: sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.pasteboardContainsImage(from: sender.draggingPasteboard) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.pasteboardContainsImage(from: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        insertImageArgument(from: sender.draggingPasteboard)
    }

    private static func canPasteTerminalContent(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.string(forType: .string) != nil || pasteboardContainsImage(from: pasteboard)
    }

    private enum ClipboardImageResolution {
        case file(URL)
        case noImage
        case unavailable
    }

    private static func clipboardImageURL(
        from pasteboard: NSPasteboard,
        allowRawImage: Bool
    ) -> ClipboardImageResolution {
        if let url = imageFileURL(from: pasteboard) {
            return .file(url.standardizedFileURL)
        }
        guard allowRawImage else { return .noImage }
        guard pasteboardContainsRawImage(from: pasteboard) else { return .noImage }
        guard let url = saveRawClipboardImage(from: pasteboard) else { return .unavailable }
        return .file(url)
    }

    private static func pasteboardContainsImage(from pasteboard: NSPasteboard) -> Bool {
        imageFileURL(from: pasteboard) != nil || pasteboardContainsRawImage(from: pasteboard)
    }

    private static func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        for item in pasteboard.pasteboardItems ?? [] {
            guard let data = item.data(forType: .fileURL),
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.isFileURL,
                  isImageFileURL(url) else {
                continue
            }
            return url
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        for object in objects {
            guard let url = object as? URL,
                  url.isFileURL,
                  isImageFileURL(url) else {
                continue
            }
            return url
        }

        return nil
    }

    private static func isImageFileURL(_ url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        if let type = UTType(filenameExtension: fileExtension),
           type.conforms(to: .image) {
            return true
        }
        let knownImageExtensions: Set<String> = [
            "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg",
            "jp2", "png", "psd", "svg", "tif", "tiff", "webp"
        ]
        return knownImageExtensions.contains(fileExtension)
    }

    private static func pasteboardContainsRawImage(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains { type in
            if type == .png || type == .tiff { return true }
            guard let uniformType = UTType(type.rawValue) else { return false }
            return uniformType.conforms(to: .image)
        } ?? false
    }

    private static func saveRawClipboardImage(from pasteboard: NSPasteboard) -> URL? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let directory = clipboardImagesDirectory()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let filename = "clipboard-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).png"
            let url = directory.appendingPathComponent(filename, isDirectory: false)
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func clipboardImagesDirectory() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Loom"
        return base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Clipboard Images", isDirectory: true)
    }

    private static func zshSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - Context menu

    /// Right-click context menu. SwiftTerm's `TerminalView` is an `NSView`
    /// subclass and ships no default menu, so without this override a
    /// secondary click on the pane is a no-op. The items target nil so AppKit
    /// dispatches each one through the responder chain — Copy/Paste land on
    /// SwiftTerm's `copy(_:)` / our overridden `paste(_:)`, Paste as Plain
    /// Text targets `pasteAsPlainText(_:)` on this class. `validateUserInter`
    /// `faceItem` keeps Copy disabled when there's no selection and Paste*
    /// disabled when the pasteboard is empty.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = .command
        menu.addItem(pasteItem)

        let pastePlainItem = NSMenuItem(
            title: "Paste as Plain Text",
            action: #selector(LoomTerminalView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pastePlainItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(pastePlainItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)

        return menu
    }

    // MARK: - Click-to-position

    private func installClickToPosition() {
        let recognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleSingleClick(_:))
        )
        recognizer.numberOfClicksRequired = 1
        recognizer.buttonMask = 0x1
        // Run alongside SwiftTerm's native mouse handling rather than holding
        // events back — SwiftTerm needs mouseDown for selection start, and
        // the recognizer only fires on a confirmed single-click anyway.
        recognizer.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(recognizer)
    }

    @objc private func handleSingleClick(_ recognizer: NSClickGestureRecognizer) {
        // Skip when the click had any modifier — those are reserved for
        // selection (shift), word lookup (command), etc.
        if let event = NSApp.currentEvent,
           !event.modifierFlags
                .intersection([.shift, .command, .option, .control])
                .isEmpty {
            return
        }
        sendCursorMove(toPoint: recognizer.location(in: self))
    }

    /// Maximum row distance from the PTY cursor we'll cover with up/down
    /// arrows. Bounds the blast radius if the user clicks somewhere that
    /// isn't an input box (scrollback, an assistant message, etc.).
    private static let verticalClickRadius = 10

    private func sendCursorMove(toPoint point: CGPoint) {
        guard let term = terminal else { return }
        let cell = estimatedCellSize()
        guard cell.width > 0, cell.height > 0 else { return }

        let clickedCol = Int(point.x / cell.width)
        // SwiftTerm doesn't flip its view, so the click y measures from the
        // bottom — convert to a top-relative viewport row.
        let viewportRow = Int((bounds.height - point.y) / cell.height)

        let cursorViewportRow = term.buffer.y - term.buffer.yDisp
        let rowDelta = viewportRow - cursorViewportRow
        let cursorCol = term.buffer.x
        let clampedCol = max(0, min(clickedCol, term.cols - 1))
        let colDelta = clampedCol - cursorCol

        // Same-row clicks stay safe for any prompt (shell, TUI). Cross-row
        // clicks only fire when a CLI agent owns the PTY — sending up/down
        // arrows into zsh would walk command history, not move the cursor.
        if rowDelta != 0 {
            guard abs(rowDelta) <= Self.verticalClickRadius,
                  isInteractiveTUIForeground else { return }
        }
        guard rowDelta != 0 || colDelta != 0 else { return }

        var sequence = ""
        if rowDelta > 0 {
            sequence += String(repeating: "\u{1B}[B", count: rowDelta)
        } else if rowDelta < 0 {
            sequence += String(repeating: "\u{1B}[A", count: -rowDelta)
        }
        if colDelta > 0 {
            sequence += String(repeating: "\u{1B}[C", count: colDelta)
        } else if colDelta < 0 {
            sequence += String(repeating: "\u{1B}[D", count: -colDelta)
        }
        send(txt: sequence)
    }

    /// True when a known CLI agent (claude/codex/gemini) is the foreground
    /// process — i.e. up/down arrows are safe to send as visual cursor moves
    /// rather than being interpreted as shell history navigation.
    private var isInteractiveTUIForeground: Bool {
        let fd = process.childfd
        guard fd >= 0 else { return false }
        let pgid = tcgetpgrp(fd)
        guard pgid > 0 else { return false }
        guard let name = TerminalSession.processName(pid: pgid)?.lowercased() else { return false }
        return TerminalSession.knownCLIAgents.contains(name)
    }

    /// Mirrors SwiftTerm's internal `computeFontDimensions`: cell width is the
    /// "W" advancement, cell height is ascent + descent + leading. Snapped to
    /// the pixel grid using the window's backing scale so the col/row
    /// arithmetic matches what SwiftTerm uses to lay out the buffer.
    private func estimatedCellSize() -> CGSize {
        let f = font
        let glyph = f.glyph(withName: "W")
        let width = f.advancement(forGlyph: glyph).width
        let ctFont = f as CTFont
        let height = ceil(
            CTFontGetAscent(ctFont)
            + CTFontGetDescent(ctFont)
            + CTFontGetLeading(ctFont)
        )
        let scale = window?.backingScaleFactor ?? 2.0
        return CGSize(
            width: ceil(width * scale) / scale,
            height: ceil(height * scale) / scale
        )
    }
}

/// Kept off the main actor so it can satisfy SwiftTerm's nonisolated delegate
/// requirements. We can't assume SwiftTerm always dispatches these on the
/// main thread — terminal data callbacks may arrive on its own queue — so
/// every hop into session state goes through `Task { @MainActor in }`.
private final class ProcessBridge: NSObject, LocalProcessTerminalViewDelegate {
    weak var session: TerminalSession?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let session = self.session
        Task { @MainActor in
            session?.lastReportedTitle = title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let session = self.session
        Task { @MainActor in
            session?.updateReportedCwd(directory)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {}
}
