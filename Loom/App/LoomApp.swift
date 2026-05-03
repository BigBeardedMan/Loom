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
        WindowGroup("Loom") {
            WorkspaceView()
                .frame(minWidth: 1024, minHeight: 640)
                .environment(layout)
                .environment(liveAgentTasks)
                .environment(agentRegistry)
                .environment(usageService)
                .environment(updateService)
                .environment(localEndpoints)
                .environment(workspaceContext)
                .task {
                    layout.prefetchAllKinds()
                    liveAgentTasks.start()
                    usageService.start()
                    updateService.start()
                    layout.startLiveAgentPolling()
                    await agentRegistry.refresh(localEndpoints: localEndpoints.endpoints)
                }
        }
        .modelContainer(container)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace…") { /* surfaced via sidebar */ }
                    .keyboardShortcut("n", modifiers: [.command])
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
                Button("Switch to Previous Workspace") {
                    quickFlipWorkspace()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(layout.previousWorkspaceID == nil)
            }

            CommandGroup(after: .help) {
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
