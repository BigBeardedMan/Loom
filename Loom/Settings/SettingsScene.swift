import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .padding(20)

            TasksSettings()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .padding(20)

            ProvidersSettings()
                .tabItem { Label("Providers", systemImage: "server.rack") }
                .padding(20)

            MCPSettings()
                .tabItem { Label("MCP", systemImage: "powerplug") }
                .padding(20)

            ShellSettings()
                .tabItem { Label("Shell", systemImage: "terminal") }
                .padding(20)

            AdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .padding(20)
        }
        .frame(width: 620, height: 460)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage("loom.appearance") private var raw: String = AppearanceSetting.dark.rawValue

    private var binding: Binding<AppearanceSetting> {
        Binding(
            get: { AppearanceSetting(rawValue: raw) ?? .dark },
            set: { raw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: binding) {
                    ForEach(AppearanceSetting.allCases) { setting in
                        Label(setting.label, systemImage: setting.systemImage)
                            .tag(setting)
                    }
                }
                .pickerStyle(.segmented)

                Text("Affects every Loom window. Choose Match System to follow macOS's appearance, or pin to Light or Dark.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tasks

private struct TasksSettings: View {
    @AppStorage("loom.tasks.staleHours") private var staleHours: Double = 1.0

    var body: some View {
        Form {
            Section("Live Agent Tasks") {
                Picker("Stale window", selection: $staleHours) {
                    Text("30 minutes").tag(0.5)
                    Text("1 hour").tag(1.0)
                    Text("4 hours").tag(4.0)
                    Text("12 hours").tag(12.0)
                    Text("24 hours").tag(24.0)
                    Text("Never (always show)").tag(8760.0)
                }
                .pickerStyle(.menu)

                Text("CLI sessions untouched longer than this are treated as dead — their tasks won't appear in the pane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Providers (local LLM endpoints)

private struct ProvidersSettings: View {
    @Environment(LocalEndpointStore.self) private var store
    @Environment(AgentRegistry.self) private var registry
    @State private var editing: LocalEndpoint?
    @State private var presentEditor: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local Providers")
                    .font(.headline)
                Spacer()
                Button {
                    editing = nil
                    presentEditor = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if store.endpoints.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.endpoints) { endpoint in
                        endpointRow(endpoint)
                    }
                }
                .listStyle(.bordered)
            }

            Text("Endpoints reachable on localhost or your LAN. Ollama auto-discovers models via /api/tags; OpenAI-compatible servers (LM Studio, llama.cpp, Jan, vLLM) use the model id you set here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $presentEditor, onDismiss: refreshAgents) {
            EndpointEditor(initial: editing) { saved in
                store.upsert(saved.endpoint)
                if let token = saved.authToken {
                    store.setAuthToken(token, for: saved.endpoint)
                }
                presentEditor = false
            } onCancel: {
                presentEditor = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No local providers configured.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Click Add to point Loom at Ollama, LM Studio, llama.cpp, Jan, or any OpenAI-compatible server.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func endpointRow(_ endpoint: LocalEndpoint) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: endpoint.kind == .ollama ? "cube.box" : "network")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(endpoint.kind.label) · \(endpoint.baseURL)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit") {
                editing = endpoint
                presentEditor = true
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                store.remove(endpoint)
                refreshAgents()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
        .padding(.vertical, 4)
    }

    private func refreshAgents() {
        Task { await registry.refresh(localEndpoints: store.endpoints) }
    }
}

private struct EndpointEditor: View {
    struct Saved {
        let endpoint: LocalEndpoint
        let authToken: String?
    }

    let initial: LocalEndpoint?
    let onSave: (Saved) -> Void
    let onCancel: () -> Void

    @State private var displayName: String = ""
    @State private var kind: LocalEndpoint.Kind = .ollama
    @State private var baseURL: String = LocalEndpoint.Kind.ollama.defaultBaseURL
    @State private var defaultModel: String = ""
    @State private var requiresAuth: Bool = false
    @State private var authToken: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var testMessage: String = ""

    enum TestStatus { case idle, running, ok, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(initial == nil ? "Add Local Provider" : "Edit Local Provider")
                .font(.headline)

            Form {
                TextField("Display name", text: $displayName, prompt: Text("My Ollama box"))
                Picker("Kind", selection: $kind) {
                    ForEach(LocalEndpoint.Kind.allCases) { k in
                        Text(k.label).tag(k)
                    }
                }
                .onChange(of: kind) { _, newKind in
                    if baseURL.isEmpty || isDefaultBaseURL(for: oppositeKind(newKind)) {
                        baseURL = newKind.defaultBaseURL
                    }
                }

                TextField("Base URL", text: $baseURL, prompt: Text(kind.defaultBaseURL))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                TextField(modelFieldLabel, text: $defaultModel, prompt: Text(modelFieldHint))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Toggle("Requires auth token", isOn: $requiresAuth)
                if requiresAuth {
                    SecureField("Bearer token", text: $authToken)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button {
                    Task { await runTest() }
                } label: {
                    if testStatus == .running {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Test connection")
                    }
                }
                .disabled(testStatus == .running || baseURL.isEmpty)

                statusBadge
                Spacer()
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: prefill)
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelFieldLabel: String {
        kind == .ollama ? "Default model (optional)" : "Model"
    }

    private var modelFieldHint: String {
        kind == .ollama ? "llama3.2:3b — only used if /api/tags fails" : "lmstudio-community/Llama-3.1-8B-Instruct"
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .running:
            Text("Testing…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ok:
            Label(testMessage.isEmpty ? "Reachable" : testMessage, systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label(testMessage.isEmpty ? "Failed" : testMessage, systemImage: "xmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func prefill() {
        guard let initial else { return }
        displayName = initial.displayName
        kind = initial.kind
        baseURL = initial.baseURL
        defaultModel = initial.defaultModel
        requiresAuth = initial.requiresAuth
        authToken = KeychainStore.load(account: initial.keychainAccount) ?? ""
    }

    private func save() {
        let endpoint = LocalEndpoint(
            id: initial?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultModel: defaultModel.trimmingCharacters(in: .whitespacesAndNewlines),
            requiresAuth: requiresAuth
        )
        onSave(Saved(
            endpoint: endpoint,
            authToken: requiresAuth ? authToken : ""
        ))
    }

    private func oppositeKind(_ k: LocalEndpoint.Kind) -> LocalEndpoint.Kind {
        k == .ollama ? .openAICompatible : .ollama
    }

    private func isDefaultBaseURL(for k: LocalEndpoint.Kind) -> Bool {
        baseURL.trimmingCharacters(in: .whitespaces) == k.defaultBaseURL
    }

    private func runTest() async {
        testStatus = .running
        testMessage = ""
        let endpoint = LocalEndpoint(
            displayName: "test",
            kind: kind,
            baseURL: baseURL,
            defaultModel: defaultModel,
            requiresAuth: requiresAuth
        )
        guard let url = endpoint.resolvedBaseURL else {
            testStatus = .failed
            testMessage = "Invalid URL"
            return
        }

        let result: TestResult
        switch kind {
        case .ollama:
            result = await testOllama(url: url)
        case .openAICompatible:
            result = await testOpenAI(url: url, token: requiresAuth ? authToken : nil)
        }

        switch result {
        case .ok(let summary):
            testStatus = .ok
            testMessage = summary
        case .failure(let message):
            testStatus = .failed
            testMessage = message
        }
    }

    private enum TestResult {
        case ok(String)
        case failure(String)
    }

    private func testOllama(url: URL) async -> TestResult {
        let models = await OllamaProvider.fetchModels(baseURL: url)
        if models.isEmpty {
            return .failure("No models / unreachable")
        }
        return .ok("\(models.count) model\(models.count == 1 ? "" : "s")")
    }

    private func testOpenAI(url: URL, token: String?) async -> TestResult {
        var request = URLRequest(url: url.appendingPathComponent("models"))
        request.timeoutInterval = 4
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("Non-HTTP response")
            }
            if (200..<300).contains(http.statusCode) {
                return .ok("Reachable")
            }
            return .failure("HTTP \(http.statusCode)")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

// MARK: - Shell

private struct ShellSettings: View {
    @AppStorage("loom.shellIntegration") private var integrationEnabled: Bool = true
    @AppStorage("loom.terminal.pasteAsPlainText") private var pasteAsPlainText: Bool = false

    var body: some View {
        Form {
            Section("Shell Integration") {
                Toggle("Capture commands from Loom terminals", isOn: $integrationEnabled)

                Text("Loom installs a small zsh shim that sources your normal config, then logs every command (start, end, exit, cwd) to a JSONL file the Commands panel reads. Turn this off to launch terminals with stock `$ZDOTDIR`; existing entries in the log stay put either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Applies to terminals opened after the change. Currently-running terminals keep whichever mode they started with.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Pasting") {
                Toggle("Always paste as plain text", isOn: $pasteAsPlainText)

                Text("⌘V skips SwiftTerm's bracketed-paste wrapping (CSI 200~/201~) and sends the clipboard string straight to the PTY. Use Edit → Paste as Plain Text (⇧⌘V) to do this once without flipping the toggle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Files") {
                LabeledContent("Shim") {
                    Text(ShellIntegration.shimURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("History log") {
                    Text(ShellIntegration.historyLogURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        ShellIntegration.shimURL,
                        ShellIntegration.historyLogURL
                    ])
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - MCP

private struct MCPSettings: View {
    @Environment(MCPService.self) private var service
    @State private var presentEditor: Bool = false
    @State private var draftName: String = ""
    @State private var draftCommand: String = ""
    @State private var draftArgs: String = ""
    @State private var saveError: String?
    @State private var isSaving: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MCP Servers")
                    .font(.headline)
                if service.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                }
                Spacer()
                Button {
                    Task { await service.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(service.isRefreshing)
                Button {
                    resetDraft()
                    presentEditor = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }

            if service.servers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(service.servers) { server in
                        serverRow(server)
                    }
                }
                .listStyle(.bordered)
            }

            if let error = service.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Loom reads this list from `claude mcp list`. Adds and removes call the same CLI, so the source of truth stays inside Claude Code's own registry.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            if service.servers.isEmpty {
                await service.refresh()
            }
        }
        .sheet(isPresented: $presentEditor) {
            editorSheet
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "powerplug")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No MCP servers configured.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Click Add to register a stdio command, or run `claude mcp add` from a terminal.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func serverRow(_ server: MCPServer) -> some View {
        HStack(alignment: .center, spacing: 10) {
            statusDot(for: server.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(server.transportLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(server.target)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLabel(for: server.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await service.remove(name: server.name) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove server (`claude mcp remove`)")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusDot(for status: MCPServer.Status) -> some View {
        Circle()
            .fill(statusTint(for: status))
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func statusLabel(for status: MCPServer.Status) -> some View {
        switch status {
        case .connected:
            Text("Connected")
        case .needsAuth:
            Text("Needs authentication")
        case .failed(let raw):
            Text(raw)
        case .unknown:
            Text("Status unknown")
        }
    }

    private func statusTint(for status: MCPServer.Status) -> Color {
        switch status {
        case .connected: return .green
        case .needsAuth: return .orange
        case .failed:    return .red
        case .unknown:   return .gray
        }
    }

    private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add MCP Server")
                .font(.headline)

            Form {
                TextField("Name", text: $draftName, prompt: Text("filesystem"))
                    .textFieldStyle(.roundedBorder)
                TextField("Command", text: $draftCommand, prompt: Text("npx"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("Args (space-separated)", text: $draftArgs, prompt: Text("-y @modelcontextprotocol/server-filesystem ~/projects"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            .formStyle(.grouped)

            if let error = saveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    presentEditor = false
                    saveError = nil
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || draftName.isEmpty || draftCommand.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func save() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = draftCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = draftArgs
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        isSaving = true
        let ok = await service.add(name: name, command: command, args: args)
        isSaving = false
        if ok {
            presentEditor = false
            resetDraft()
        } else {
            saveError = service.lastError ?? "Failed to add server"
        }
    }

    private func resetDraft() {
        draftName = ""
        draftCommand = ""
        draftArgs = ""
        saveError = nil
    }
}

// MARK: - Advanced

private struct AdvancedSettings: View {
    @State private var apiKey: String = KeychainStore.load(account: KeychainKey.anthropicAPIKey) ?? ""
    @State private var saved: Bool = false

    var body: some View {
        Form {
            Section("Anthropic API Key (optional)") {
                SecureField("API key", text: $apiKey, prompt: Text("sk-ant-…"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                    Button("Clear") { clear() }
                        .disabled(apiKey.isEmpty)
                    Spacer()
                    if saved {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text("Loom's Agent block uses Claude Code's OAuth login — no key required. This is kept for future API-direct features. Stored in macOS Keychain (service `com.chasesims.Loom`).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: KeychainKey.anthropicAPIKey)
        } else {
            KeychainStore.save(account: KeychainKey.anthropicAPIKey, value: trimmed)
        }
        apiKey = trimmed
        saved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { saved = false }
        }
    }

    private func clear() {
        apiKey = ""
        KeychainStore.delete(account: KeychainKey.anthropicAPIKey)
    }
}
