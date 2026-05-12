import Foundation
import Darwin
import Observation

@Observable
@MainActor
final class CrashService {
    var pendingReport: CrashReport?

    private static let logFileName = "panic.log"

    static let shared: CrashService = {
        let svc = CrashService()
        return svc
    }()

    private init() {}

    /// Wire up the uncaught exception + signal handlers and consume any
    /// crash log left by a prior run. Call once at app start, very early.
    func install() {
        CrashService.installHandlersOnce()
        consumePriorCrash()
    }

    private static var installed = false

    private static func installHandlersOnce() {
        guard !installed else { return }
        installed = true

        NSSetUncaughtExceptionHandler { exception in
            CrashService.writeCrash(
                kind: "NSException",
                message: "\(exception.name.rawValue): \(exception.reason ?? "")",
                callStack: exception.callStackSymbols
            )
        }

        for sig in [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGPIPE] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = CrashService.signalHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0
            sigaction(sig, &action, nil)
        }
    }

    private static let signalHandler: @convention(c) (Int32) -> Void = { sig in
        // Async-signal-safe path: stdlib calls only, no Swift heap allocs.
        // Write a minimal marker; the next-launch reader builds the rich
        // report from process info that survives the crash.
        if let path = CrashService.logPathCString() {
            let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
            if fd >= 0 {
                let prefix = "[signal] "
                _ = prefix.withCString { ptr in
                    write(fd, ptr, strlen(ptr))
                }
                if let name = strsignal(sig) {
                    _ = write(fd, name, strlen(name))
                }
                _ = "\n".withCString { ptr in
                    write(fd, ptr, strlen(ptr))
                }
                close(fd)
            }
        }
        // Re-raise default action so the OS still terminates the process
        // and the user sees a normal crash dialog if they had reports on.
        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// Build a path C-string outside the handler so the handler itself
    /// can be async-signal-safe (no Swift String allocations at signal
    /// time). We cache the result in a static immutable buffer.
    private static let logPathCStringHolder: UnsafePointer<CChar>? = {
        guard let url = CrashService.logURL() else { return nil }
        guard let cstr = strdup(url.path) else { return nil }
        return UnsafePointer(cstr)
    }()

    private static func logPathCString() -> UnsafePointer<CChar>? {
        return logPathCStringHolder
    }

    private static func writeCrash(kind: String, message: String, callStack: [String]) {
        guard let url = logURL() else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #else
        arch = "unknown"
        #endif
        let formatter = ISO8601DateFormatter()
        var body = ""
        body += "Loom crash at \(formatter.string(from: Date()))\n"
        body += "Version: \(version) (\(build))\n"
        body += "Arch: \(arch)\n"
        body += "Kind: \(kind)\n"
        body += "Message: \(message)\n\n"
        body += "Stack:\n"
        for frame in callStack {
            body += frame + "\n"
        }
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func logURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let logs = support.appendingPathComponent("Loom Testing Edition").appendingPathComponent("logs")
        return logs.appendingPathComponent(logFileName)
    }

    private func consumePriorCrash() {
        guard let url = CrashService.logURL(),
              FileManager.default.fileExists(atPath: url.path),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        let stamp = formatter.string(from: Date())
        let archive = url.deletingLastPathComponent()
            .appendingPathComponent("panic-\(stamp).log")
        try? FileManager.default.moveItem(at: url, to: archive)

        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #else
        arch = "unknown"
        #endif
        pendingReport = CrashReport(
            version: version,
            arch: arch,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            body: body
        )
    }

    func dismiss() {
        pendingReport = nil
    }
}

struct CrashReport: Identifiable, Equatable {
    let id = UUID()
    let version: String
    let arch: String
    let timestamp: String
    let body: String
}
