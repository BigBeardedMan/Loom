import SwiftUI
import SwiftData

@main
struct LoomApp: App {
    @State private var layout = WorkspaceLayout()
    @State private var liveAgentTasks = LiveAgentTasksService()
    @State private var agentRegistry = AgentRegistry()
    @State private var usageService = UsageService()
    @State private var updateService = UpdateService()
    @State private var localEndpoints = LocalEndpointStore()
    @State private var workspaceContext = WorkspaceContext()
    @State private var mcpService = MCPService()
    @State private var commandHistory = CommandHistoryService()
    @State private var crashService = CrashService.shared

    init() {
        CrashService.shared.install()
    }

    let container: ModelContainer = {
        let schema = Schema([
            Workspace.self,
            KanbanBoard.self,
            KanbanColumn.self,
            KanbanCard.self,
            IdeaNote.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup("Loom Testing Edition") {
            WorkspaceView()
                .frame(minWidth: 1024, minHeight: 640)
                .environment(layout)
                .environment(liveAgentTasks)
                .environment(agentRegistry)
                .environment(usageService)
                .environment(updateService)
                .environment(localEndpoints)
                .environment(workspaceContext)
                .environment(commandHistory)
                .task {
                    ShellIntegration.install()
                    layout.prefetchAllKinds()
                    liveAgentTasks.start()
                    usageService.start()
                    updateService.start()
                    commandHistory.start()
                    layout.startLiveAgentPolling()
                    await agentRegistry.refresh(localEndpoints: localEndpoints.endpoints)
                }
                // 8.0.16: trigger an extra remote-update check when Loom
                // comes back to the foreground. The 60s background poll
                // still runs, but this hook means a user who just shipped
                // a new release (or switched back from a browser after
                // reading a release note) sees the pill within seconds
                // instead of within a minute.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    Task { await updateService.checkRemote() }
                }
                .onOpenURL { url in
                    URLSchemeHandler.handle(url)
                }
                .sheet(item: Binding(
                    get: { crashService.pendingReport },
                    set: { newValue in
                        if newValue == nil { crashService.dismiss() }
                    }
                )) { report in
                    CrashReportSheet(report: report) {
                        crashService.dismiss()
                    }
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Loom Testing Edition") { showAboutPanel() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Workspace…") { /* surfaced via sidebar */ }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            // Standard Edit-menu pasteboard items. These go through the
            // responder chain via NSApp.sendAction(_, to: nil, …) so the
            // active first responder handles them — SwiftTerm's
            // LoomTerminalView for terminal panes, NSTextField for the
            // command palette, etc. Paste as Plain Text (⇧⌘V) targets
            // LoomTerminalView's pasteAsPlainText(_:) which bypasses
            // bracketed-paste wrapping.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: [.command])

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: [.command])

                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: [.command])

                Button("Paste as Plain Text") {
                    NSApp.sendAction(#selector(LoomTerminalView.pasteAsPlainText(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Divider()

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: [.command])
            }
            CommandMenu("Add Block") {
                ForEach(layout.currentKind.availablePanels) { panel in
                    Button("Add \(panel.label)") {
                        layout.addBlock(panel)
                    }
                    .keyboardShortcut(shortcutKey(for: panel), modifiers: [.command, .shift])
                }
            }

            CommandMenu("Layout") {
                Button("Pin Left") { pinFocused(.left) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Pin Right") { pinFocused(.right) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Pin Top") { pinFocused(.top) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Pin Bottom") { pinFocused(.bottom) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("Toggle Full Row") { toggleFullRowFocused() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Unpin") { pinFocused(nil) }
                    .keyboardShortcut("u", modifiers: [.command, .option])
            }
            CommandMenu("Navigate") {
                Button("Command Palette…") {
                    NotificationCenter.default.post(name: .loomOpenPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Divider()
                Button("Switch to Previous Workspace") {
                    quickFlipWorkspace()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(layout.previousWorkspaceID == nil)
            }

            CommandGroup(replacing: .help) {
                Button("Loom Testing Edition Help") {
                    if let url = URL(string: "https://github.com/BigBeardedMan/Loom/blob/main/GUIDE.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: [.command])
                Button("Loom Documentation Site") {
                    if let url = URL(string: "https://bigbeardedman.github.io/Loom/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Check for Updates…") {
                    Task { await updateService.checkRemoteAndAnnounce() }
                }
                .disabled(updateService.isFetchingRemote)
            }

            #if DEBUG
            CommandMenu("Loom Dev") {
                Button("Export App Icon Set") { exportAppIconSet() }
            }
            #endif
        }

        Settings {
            SettingsView()
                .environment(localEndpoints)
                .environment(agentRegistry)
                .environment(mcpService)
        }
    }

    private func shortcutKey(for panel: PanelKind) -> KeyEquivalent {
        let panels = layout.currentKind.availablePanels
        let index = panels.firstIndex(of: panel) ?? 0
        let digit = String(min(index + 1, 9))
        return KeyEquivalent(Character(digit))
    }

    private func pinFocused(_ pin: BlockPin?) {
        guard let target = layout.commandTargetBlock else { return }
        layout.setPin(target.id, to: pin)
    }

    private func toggleFullRowFocused() {
        guard let target = layout.commandTargetBlock else { return }
        layout.toggleSpan(target.id)
    }

    private func quickFlipWorkspace() {
        guard let prev = layout.previousWorkspaceID else { return }
        layout.selectedWorkspaceID = prev
    }

    @MainActor
    private func showAboutPanel() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""

        let credits = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: 11)
        let secondaryColor = NSColor.secondaryLabelColor

        let header = NSAttributedString(
            string: "Native macOS workspace app for terminals, editor, AI agents, and task state.\n\n",
            attributes: [
                .font: baseFont,
                .foregroundColor: secondaryColor
            ]
        )
        credits.append(header)

        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.linkColor
        ]
        let pairs: [(label: String, url: String)] = [
            ("GitHub", "https://github.com/BigBeardedMan/Loom"),
            ("Guide", "https://github.com/BigBeardedMan/Loom/blob/main/GUIDE.md"),
            ("Documentation", "https://bigbeardedman.github.io/Loom/")
        ]
        for (i, pair) in pairs.enumerated() {
            let link = NSMutableAttributedString(string: pair.label, attributes: linkAttrs)
            link.addAttribute(.link, value: pair.url, range: NSRange(location: 0, length: link.length))
            credits.append(link)
            if i < pairs.count - 1 {
                credits.append(NSAttributedString(
                    string: "   ·   ",
                    attributes: [.font: baseFont, .foregroundColor: secondaryColor]
                ))
            }
        }

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Loom Testing Edition",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyright
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func exportAppIconSet() {
        let alert = NSAlert()
        if let target = AppIconExporter.defaultAssetURL() {
            do {
                try AppIconExporter.export(to: target)
                alert.messageText = "App icons exported"
                alert.informativeText = """
                Wrote \(AppIconExporter.pixelSizes.count) PNGs to:
                \(target.path)

                Clean Build Folder (⌘⇧K) and rebuild to refresh the Dock icon.
                """
            } catch {
                alert.messageText = "Failed to export"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
            }
        } else {
            alert.messageText = "AppIcon.appiconset not found"
            alert.informativeText = "Expected at ~/Documents/XCode/Loom/Loom/Resources/Assets.xcassets/AppIcon.appiconset"
            alert.alertStyle = .warning
        }
        alert.runModal()
    }
}
