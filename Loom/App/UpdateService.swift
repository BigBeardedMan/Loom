import Foundation
import Observation
import AppKit
import os

private let updateLog = Logger(subsystem: "com.chasesims.LoomTestingEdition", category: "updates")

/// Side-channel updater for the Testing Edition. A staged
/// `Loom Testing Edition.app` sits at
/// `~/Library/Application Support/Loom Testing Edition/staging/`, with a
/// sibling `manifest.json` describing it. The running app polls the manifest;
/// when its build code differs from the running bundle's, the in-app "Update"
/// button lights up. Clicking it spawns a detached helper that waits for this
/// process to quit, swaps the staged bundle into
/// `/Applications/Loom Testing Edition.app`, and relaunches.
///
/// The whole point is to never `cp` over a live installed bundle. macOS
/// handles that poorly and crashes the running instance.
struct StagedUpdate: Equatable {
    var version: String
    var build: String
    var stagedAt: Date
    var bundlePath: String

    /// Human-readable version label, e.g. "0.10.1 (11)".
    var displayLabel: String { "\(version) (\(build))" }
}

@Observable
@MainActor
final class UpdateService {
    /// Latest staged build that's *newer* than the running app. Nil when nothing
    /// is staged or the staged build matches what's already running.
    var available: StagedUpdate?

    /// Set briefly after `applyAndRelaunch` is called. UI uses it to lock the
    /// button so the user can't fire the helper twice.
    var isApplying: Bool = false

    /// Set while `GitHubReleaseFetcher` is downloading + staging a release.
    /// UI doesn't show this directly today, but we keep it observable so a
    /// future indicator can hook in without a refactor.
    var isFetchingRemote: Bool = false

    /// Last error message from a remote check, surfaced through Help → Check
    /// for Updates so silent network/staging failures don't lie as "up to
    /// date." Cleared on a successful fetch.
    var lastRemoteError: String?

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 4.0

    private var remotePollTask: Task<Void, Never>?
    /// How often the background loop hits GitHub. 60s sits right at the
    /// unauthenticated rate limit (60 req/hr), so a manual Help → Check for
    /// Updates can briefly push over the limit; GitHub responds with 403 and
    /// we silently retry on the next tick.
    private let remotePollInterval: TimeInterval = 60
    /// Owner/repo for release polling. Public repo, no token required.
    /// Testing Edition lives in the same repo as main Loom but under
    /// `testing-<code>` tags marked as pre-release on GitHub, so the
    /// main app's `/releases/latest` query never sees them.
    static let remoteRepo = "BigBeardedMan/Loom"
    /// Tag prefix that marks a Testing Edition release. Anything not
    /// starting with this is ignored even if it's newer.
    static let testingTagPrefix = "testing-"
    /// Last release tag we've already pulled into staging. Prevents
    /// re-downloading the same .dmg every poll.
    private var lastFetchedTag: String?

    /// `~/Library/Application Support/Loom Testing Edition`. Separate from
    /// main Loom's data folder so the two editions can coexist with their
    /// own workspaces, settings, and staging dirs.
    static let appSupportRoot: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Loom Testing Edition", isDirectory: true)
    }()

    static var stagingRoot: URL {
        appSupportRoot.appendingPathComponent("staging", isDirectory: true)
    }

    static var manifestURL: URL {
        stagingRoot.appendingPathComponent("manifest.json")
    }

    static var stagedBundleURL: URL {
        stagingRoot.appendingPathComponent("Loom Testing Edition.app")
    }

    /// Where the user expects to launch from. We swap the staged bundle into
    /// this location.
    static let installedBundleURL = URL(fileURLWithPath: "/Applications/Loom Testing Edition.app")

    func start() {
        guard pollTimer == nil else { return }
        try? FileManager.default.createDirectory(at: Self.appSupportRoot, withIntermediateDirectories: true)
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        startRemotePolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        remotePollTask?.cancel()
        remotePollTask = nil
    }

    private func startRemotePolling() {
        guard remotePollTask == nil else { return }
        remotePollTask = Task { [weak self] in
            // First check happens on app launch; subsequent checks every
            // remotePollInterval. Sleep failures (cancellation) end the loop.
            while !Task.isCancelled {
                await self?.checkRemote()
                try? await Task.sleep(nanoseconds: UInt64((self?.remotePollInterval ?? 1800) * 1_000_000_000))
            }
        }
    }

    /// User-initiated remote check (Help → Check for Updates). Forces a
    /// re-stage even if `lastFetchedTag` matches, so the user has a way to
    /// recover when a previous stage attempt corrupted the staging dir or
    /// the manifest got cleared underneath us. Surfaces real errors.
    func checkRemoteAndAnnounce() async {
        await checkRemote(forceRestage: true)
        // checkRemote may have written a new manifest; force the local poll
        // to read it now instead of waiting up to 4s.
        refresh()

        let alert = NSAlert()
        if let staged = available {
            alert.messageText = "Update available"
            alert.informativeText = "Loom \(staged.displayLabel) is ready. Click Update in the top bar to install and relaunch."
            alert.alertStyle = .informational
        } else if let err = lastRemoteError {
            alert.messageText = "Update check failed"
            alert.informativeText = err
            alert.alertStyle = .warning
        } else {
            let running = Self.runningVersionTriple()
            alert.messageText = "Loom is up to date"
            alert.informativeText = "You're running \(running.version) (\(running.build))."
            alert.alertStyle = .informational
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Hits GitHub Releases. If the latest tag is newer than the running app
    /// AND we haven't already fetched it, downloads the .dmg, mounts it, and
    /// copies Loom.app into the local staging dir. The 4-second local poll
    /// then surfaces the Update button via the existing path.
    ///
    /// Pass `forceRestage: true` from a user-initiated check to bypass the
    /// in-memory `lastFetchedTag` short-circuit — that flag is meant to keep
    /// the *background* poll from re-downloading the same DMG every minute,
    /// not to lock the user out of retrying after a failure.
    /// Wrap GitHubReleaseFetcher.fetchLatestPrerelease in a one-shot
    /// retry for transient network errors (-1001 timed out,
    /// -1009 not connected, -1004 cannot connect to host). Other errors
    /// propagate immediately. Adds at most one 3s backoff before retry.
    private func fetchLatestPrereleaseWithRetry(repo: String,
                                                  tagPrefix: String) async throws
        -> GitHubReleaseFetcher.Release? {
        do {
            return try await GitHubReleaseFetcher.fetchLatestPrerelease(
                repo: repo, tagPrefix: tagPrefix
            )
        } catch let error as URLError where
            error.code == .timedOut
            || error.code == .notConnectedToInternet
            || error.code == .cannotConnectToHost
            || error.code == .networkConnectionLost {
            // Wait 3s, then try one more time. The 30s per-request
            // timeout still applies on the retry.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return try await GitHubReleaseFetcher.fetchLatestPrerelease(
                repo: repo, tagPrefix: tagPrefix
            )
        }
    }

    func checkRemote(forceRestage: Bool = false) async {
        // Set the guard flag *before* the first await — otherwise two callers
        // can both pass the `!isFetchingRemote` check during the network round
        // trip and end up racing to write the same DMG into staging.
        guard !isFetchingRemote else { return }
        isFetchingRemote = true
        defer { isFetchingRemote = false }

        do {
            // Testing Edition: walk recent releases (including pre-releases)
            // and pick the newest one whose tag starts with `testing-`. Tags
            // are semver (e.g. `testing-3.3.0`) and we offer the update only
            // when the published version is strictly newer than what's
            // running. Main-line `v*.*.*` releases are skipped entirely.
            //
            // 8.0.18: retry once on transient network errors. The user's
            // logs showed repeated -1001 timeouts that resolved on a
            // retry; without this, an unlucky moment costs a full
            // 60-second poll cycle before another attempt.
            let release = try await fetchLatestPrereleaseWithRetry(
                repo: Self.remoteRepo,
                tagPrefix: Self.testingTagPrefix
            )
            guard let release else {
                lastRemoteError = nil
                return
            }
            let runningVersion = Self.runningVersionTriple().version
            guard GitHubReleaseFetcher.isNewer(tag: release.versionTag, than: runningVersion) else {
                lastRemoteError = nil
                return
            }
            if !forceRestage, release.versionTag == lastFetchedTag {
                lastRemoteError = nil
                return
            }
            guard let dmgAsset = release.dmgAsset else {
                let msg = "Release \(release.tag) has no .dmg asset attached."
                updateLog.error("\(msg, privacy: .public)")
                lastRemoteError = msg
                return
            }
            updateLog.info("Staging \(release.tag, privacy: .public) from \(dmgAsset.url.absoluteString, privacy: .public)")
            try await GitHubReleaseFetcher.stage(
                release: release,
                dmgAsset: dmgAsset,
                stagingRoot: Self.stagingRoot
            )
            lastFetchedTag = release.versionTag
            lastRemoteError = nil
            updateLog.info("Staged \(release.tag, privacy: .public) successfully")
        } catch {
            let msg = "\(error)"
            updateLog.error("Update check failed: \(msg, privacy: .public)")
            lastRemoteError = msg
        }
    }

    func refresh() {
        let manifest = Self.readManifest()
        guard let manifest else {
            if available != nil { available = nil }
            return
        }
        // Only surface staged builds that are actually different from what's
        // running. Otherwise re-launching after an update would keep showing
        // the button until the manifest is cleared.
        let running = Self.runningVersionTriple()
        let stagedTriple = (manifest.version, manifest.build)
        let isNewer = stagedTriple != (running.version, running.build)
        let next: StagedUpdate? = isNewer ? manifest : nil
        if next != available { available = next }
    }

    /// Drop the staged manifest. Called after a successful relaunch handoff.
    static func clearManifest() {
        try? FileManager.default.removeItem(at: manifestURL)
    }

    /// Spawn the detached helper, then quit ourselves so the swap is uncontested.
    ///
    /// **Note:** the apply script body is passed inline via `zsh -c "..."`.
    /// We deliberately do **not** write a script file to a user-writable
    /// directory and re-execute it — any other process running as the user
    /// could swap the file's contents in the window between write and
    /// execute. Inline `-c` puts the script content on the new process's
    /// argv, which can't be tampered with after launch.
    func applyAndRelaunch() {
        guard let staged = available, !isApplying else { return }
        isApplying = true

        let pid = ProcessInfo.processInfo.processIdentifier
        let body = Self.applyScriptBody(
            stagedPath: staged.bundlePath,
            installedPath: Self.installedBundleURL.path,
            manifestPath: Self.manifestURL.path,
            waitForPID: pid
        )

        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/zsh")
            task.arguments = ["-c", body]
            // Detach so the child outlives us. Don't pipe stdio — the script
            // logs to a file we can read after the fact.
            task.standardInput = nil
            task.standardOutput = nil
            task.standardError = nil
            try task.run()
        } catch {
            isApplying = false
            updateLog.error("applyAndRelaunch: failed to launch helper: \(error.localizedDescription, privacy: .public)")
            lastRemoteError = "Failed to launch updater: \(error.localizedDescription)"
            return
        }

        // Give the helper a beat to start tailing our PID, then quit. The
        // helper is the one that opens the new app once the swap completes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Manifest

    private struct ManifestPayload: Decodable {
        let version: String
        let build: String
        let stagedAt: String
    }

    /// Reads the staged manifest. **Always** uses `stagedBundleURL` for the
    /// bundle path. The manifest used to allow a `bundlePath` override; that
    /// field is now ignored. A user-writable manifest pointing the path
    /// outside the staging dir was a path-traversal vector — the apply
    /// script would happily `cp -R` whatever was there into `/Applications`.
    static func readManifest() -> StagedUpdate? {
        let url = manifestURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let payload = try? JSONDecoder().decode(ManifestPayload.self, from: data) else { return nil }
        let bundleURL = stagedBundleURL
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return nil }
        let date = ISO8601DateFormatter().date(from: payload.stagedAt) ?? .now
        return StagedUpdate(
            version: payload.version,
            build: payload.build,
            stagedAt: date,
            bundlePath: bundleURL.path
        )
    }

    // MARK: - Running version

    static func runningVersionTriple() -> (version: String, build: String) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return (version, build)
    }

    // MARK: - Helper script

    /// Returns the inline zsh script body that waits for the parent PID to
    /// exit, swaps the staged bundle into `/Applications`, and re-launches
    /// Loom. Run via `zsh -c <body>` so the body lives only in the helper's
    /// argv — never on disk where it could be tampered with. Logs land in
    /// `~/Library/Application Support/Loom/staging/last-apply.log`.
    private static func applyScriptBody(
        stagedPath: String,
        installedPath: String,
        manifestPath: String,
        waitForPID pid: Int32
    ) -> String {
        let logPath = stagingRoot.appendingPathComponent("last-apply.log").path

        // Single-quote-wrap every path that ends up in the script body. The
        // user's home dir + Loom's own staging root are the only paths we
        // emit; they don't usually contain single quotes, but quoting is the
        // safe default regardless.
        let qStaged = shellQuote(stagedPath)
        let qInstalled = shellQuote(installedPath)
        let qManifest = shellQuote(manifestPath)
        let qLog = shellQuote(logPath)

        return """
        set -u
        exec >>\(qLog) 2>&1
        echo "[$(date -u +%FT%TZ)] apply-update start pid=\(pid) staged=\(qStaged) installed=\(qInstalled)"

        # Wait for the parent (current Loom) to exit. kill -0 returns 0 while
        # the process exists; cap waiting at ~10 seconds so we don't spin.
        for i in $(seq 1 50); do
          /bin/kill -0 \(pid) 2>/dev/null || break
          /bin/sleep 0.2
        done

        if /bin/kill -0 \(pid) 2>/dev/null; then
          echo "warning: parent pid still alive after 10s — forcing TERM"
          /bin/kill -TERM \(pid) 2>/dev/null || true
          /bin/sleep 0.5
        fi

        if [[ -d \(qInstalled) ]]; then
          /bin/rm -rf \(qInstalled) || { echo "rm installed failed"; exit 1; }
        fi

        /bin/cp -R \(qStaged) \(qInstalled) || { echo "cp failed"; exit 1; }
        /bin/rm -f \(qManifest) || true

        /usr/bin/open \(qInstalled) || { echo "open failed"; exit 1; }
        echo "[$(date -u +%FT%TZ)] apply-update done"
        """
    }

    /// Single-quote a string for safe inclusion in a zsh script.
    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
