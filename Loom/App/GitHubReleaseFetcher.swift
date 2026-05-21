import CryptoKit
import Foundation

/// Pulls the latest release from a public GitHub repo and stages its .dmg
/// into Loom's existing staging directory. Once the bundle + manifest land,
/// `UpdateService`'s 4-second local poll surfaces the Update button.
///
/// We don't authenticate. Public-repo releases are open and the
/// unauthenticated rate limit (60 req/hr/IP) is well above what we need.
///
/// **Integrity:** Every release MUST publish a `<dmg-name>.sha256` asset
/// containing the SHA-256 of the DMG (hex, optionally followed by whitespace
/// and the filename — `shasum`/`sha256sum` output works as-is). The fetcher
/// downloads the DMG, computes its SHA-256, and refuses to mount if the
/// hash doesn't match or the checksum asset is missing. Without this, an
/// attacker who compromises the GitHub release (stolen PAT, MITM'd CDN)
/// could replace the DMG with arbitrary code and Loom would silently install
/// it at `/Applications/Loom Testing Edition.app`.
enum GitHubReleaseFetcher {
    struct Release {
        /// Tag as published. Main line uses `v1.0.0`; Testing Edition uses
        /// `testing-3.3.0` and similar.
        var tag: String
        /// Tag with the well-known prefix stripped. For `v1.0.0` this is
        /// `1.0.0`; for `testing-3.3.0` it's `3.3.0`. The result is what we
        /// compare against the running app's `CFBundleShortVersionString`.
        var versionTag: String {
            GitHubReleaseFetcher.releaseVersionTag(from: tag)
        }
        var assets: [Asset]

        /// First .dmg asset on the release (we publish exactly one per tag).
        var dmgAsset: Asset? {
            assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        }

        /// Checksum sidecar for the DMG, named `<dmg>.sha256`.
        func checksumAsset(for dmg: Asset) -> Asset? {
            let expected = (dmg.name + ".sha256").lowercased()
            return assets.first { $0.name.lowercased() == expected }
        }

        func signatureAsset(for checksum: Asset) -> Asset? {
            let expected = (checksum.name + ".sig").lowercased()
            return assets.first { $0.name.lowercased() == expected }
        }
    }

    struct Asset {
        var name: String
        /// Public download URL (browser_download_url).
        var url: URL
    }

    enum FetcherError: LocalizedError {
        case badStatus(Int)
        case malformedPayload
        case missingAsset
        case missingChecksum
        case missingSignature
        case signatureMismatch
        case checksumMismatch(expected: String, actual: String)
        case mountFailed(String)
        case copyFailed(String)
        case invalidBundle(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let c):              return "GitHub returned HTTP \(c)."
            case .malformedPayload:              return "GitHub release payload was malformed."
            case .missingAsset:                  return "Release is missing the Loom.app bundle."
            case .missingChecksum:               return "Release is missing the .sha256 checksum sidecar — refusing to install."
            case .missingSignature:              return "Release is missing a valid .sha256.sig signature — refusing to install."
            case .signatureMismatch:             return "Release signature verification failed — refusing to install."
            case .checksumMismatch(let e, let a): return "DMG checksum mismatch (expected \(e.prefix(12))…, got \(a.prefix(12))…) — refusing to install."
            case .mountFailed(let s):            return "Failed to mount DMG: \(s)"
            case .copyFailed(let s):             return "Failed to copy bundle: \(s)"
            case .invalidBundle(let s):           return "Downloaded app bundle failed validation: \(s)"
            }
        }
    }

    // MARK: - Latest release

    static func fetchLatest(repo: String) async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Loom-Updater", forHTTPHeaderField: "User-Agent")
        // 8.0.18: 30s timeout (was 10s). The previous 10s budget timed
        // out on slower networks and DNS-laggy connections; the user's
        // logs showed NSURLErrorDomain -1001 hitting repeatedly even
        // though the API itself was up. 30s is conservative enough for
        // typical home internet variability while still letting us
        // surface real outages within a minute.
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetcherError.malformedPayload
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetcherError.badStatus(http.statusCode)
        }

        let payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
        return release(from: payload)
    }

    /// Walks the most recent 30 releases (including pre-releases, which is
    /// what `/releases/latest` deliberately excludes) and returns the highest
    /// semver whose tag starts with `tagPrefix`. GitHub's release list is not
    /// always ordered by publish time after release edits/reuses, so trusting
    /// the first matching `testing-*` tag can strand clients on an older
    /// release. Returns nil when no matching release exists.
    static func fetchLatestPrerelease(repo: String, tagPrefix: String) async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Loom-Updater", forHTTPHeaderField: "User-Agent")
        // 8.0.18: 30s (was 10s). See note on fetchLatest above.
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetcherError.malformedPayload
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetcherError.badStatus(http.statusCode)
        }

        let payloads = try JSONDecoder().decode([LatestReleasePayload].self, from: data)
        let matchingPayloads = payloads.filter { $0.tag_name.hasPrefix(tagPrefix) }
        guard let payload = matchingPayloads.max(by: { lhs, rhs in
            isNewer(
                tag: releaseVersionTag(from: rhs.tag_name),
                than: releaseVersionTag(from: lhs.tag_name)
            )
        }) else {
            return nil
        }
        return release(from: payload)
    }

    private static func release(from payload: LatestReleasePayload) -> Release {
        let assets = payload.assets.compactMap { asset -> Asset? in
            guard let url = URL(string: asset.browser_download_url) else { return nil }
            return Asset(name: asset.name, url: url)
        }
        return Release(tag: payload.tag_name, assets: assets)
    }

    // MARK: - Version compare

    /// True when `tag` is a strictly higher semver than `running`. Any
    /// non-numeric tail makes us defer to a literal "is different" check —
    /// pre-release tags (e.g., "1.0.0-rc1") shouldn't shadow a real release.
    static func isNewer(tag: String, than running: String) -> Bool {
        let lhs = parseSemver(tag)
        let rhs = parseSemver(running)
        for i in 0..<max(lhs.count, rhs.count) {
            let a = i < lhs.count ? lhs[i] : 0
            let b = i < rhs.count ? rhs[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func parseSemver(_ s: String) -> [Int] {
        // Strip pre-release / build suffix; we only care about the numeric prefix.
        let core = s.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? s
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    private static func releaseVersionTag(from tag: String) -> String {
        var stripped = tag
        if stripped.hasPrefix("testing-") {
            stripped = String(stripped.dropFirst("testing-".count))
        }
        if stripped.hasPrefix("v") {
            stripped = String(stripped.dropFirst())
        }
        return stripped
    }

    // MARK: - Stage

    /// Downloads the release .dmg, **verifies its SHA-256 against the .sha256
    /// sidecar asset**, mounts it, copies the inner Loom.app into
    /// `stagingRoot/Loom.app`, and writes manifest.json next to it. The DMG
    /// is detached and the temp file removed before returning. Throws
    /// `FetcherError.missingChecksum` or `.checksumMismatch` if the integrity
    /// check fails — we never mount or install an unverified DMG.
    static func stage(release: Release, dmgAsset: Asset, stagingRoot: URL) async throws {
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        // 1. Download the DMG.
        let (tempURL, response) = try await URLSession.shared.download(from: dmgAsset.url)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetcherError.badStatus(http.statusCode)
        }

        // 2. Verify SHA-256 against the published sidecar. Fail closed.
        guard let checksumAsset = release.checksumAsset(for: dmgAsset) else {
            throw FetcherError.missingChecksum
        }
        guard let signatureAsset = release.signatureAsset(for: checksumAsset) else {
            throw FetcherError.missingSignature
        }
        let checksumBody = try await fetchChecksumBody(at: checksumAsset.url)
        try await verifySignature(signatureURL: signatureAsset.url, signedData: checksumBody)
        let expectedHex = try parseExpectedChecksum(from: checksumBody)
        let actualHex = try sha256Hex(of: tempURL)
        guard expectedHex.caseInsensitiveCompare(actualHex) == .orderedSame else {
            throw FetcherError.checksumMismatch(expected: expectedHex, actual: actualHex)
        }

        // 3. Mount the DMG read-only at a private mountpoint.
        let mountpoint = stagingRoot
            .appendingPathComponent("mnt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountpoint, withIntermediateDirectories: true)

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = [
            "attach", tempURL.path,
            "-readonly", "-nobrowse", "-noautoopen",
            "-mountpoint", mountpoint.path
        ]
        let attachErr = Pipe()
        attach.standardError = attachErr
        attach.standardOutput = Pipe()
        try attach.run()
        attach.waitUntilExit()
        if attach.terminationStatus != 0 {
            let stderr = String(data: attachErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FetcherError.mountFailed(stderr)
        }

        // Always detach, even if the copy fails.
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountpoint.path, "-force"]
            detach.standardError = Pipe()
            detach.standardOutput = Pipe()
            try? detach.run()
            detach.waitUntilExit()
            try? FileManager.default.removeItem(at: mountpoint)
        }

        // 4. Find Loom Testing Edition.app in the mounted volume.
        let mountedApp = mountpoint.appendingPathComponent("Loom Testing Edition.app")
        guard FileManager.default.fileExists(atPath: mountedApp.path) else {
            throw FetcherError.missingAsset
        }
        try validateBundle(at: mountedApp, expectedVersion: release.versionTag)

        // 5. Replace the staged bundle.
        let stagedApp = stagingRoot.appendingPathComponent("Loom Testing Edition.app")
        if FileManager.default.fileExists(atPath: stagedApp.path) {
            try FileManager.default.removeItem(at: stagedApp)
        }
        try FileManager.default.copyItem(at: mountedApp, to: stagedApp)
        try validateBundle(at: stagedApp, expectedVersion: release.versionTag)

        // Strip iCloud xattrs on the staged copy so the in-app swap doesn't
        // trip iCloud "uploading…" rename behavior. We deliberately do NOT
        // strip quarantine — the user grants Gatekeeper exception once at
        // first launch by right-clicking → Open; subsequent launches are fine.
        // The previous unconditional `xattr -cr` made an MITM'd DMG launch
        // silently, which was the bigger problem than a one-time prompt.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "com.apple.fileprovider.fpfs#P", stagedApp.path]
        xattr.standardError = Pipe()
        xattr.standardOutput = Pipe()
        try? xattr.run()
        xattr.waitUntilExit()

        // 6. Write manifest. Pull version/build from the staged Info.plist
        // so we don't have to trust the tag formatting.
        let infoURL = stagedApp.appendingPathComponent("Contents/Info.plist")
        let info = (try? PropertyListSerialization.propertyList(
            from: try Data(contentsOf: infoURL),
            format: nil
        )) as? [String: Any] ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? release.versionTag
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        let stagedAt = ISO8601DateFormatter().string(from: .now)

        let manifestURL = stagingRoot.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "version": version,
            "build": build,
            "stagedAt": stagedAt,
            "source": "github:\(release.tag)"
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted]
        )
        try manifestData.write(to: manifestURL, options: .atomic)
    }

    private static func validateBundle(at appURL: URL, expectedVersion: String) throws {
        guard appURL.lastPathComponent == "Loom Testing Edition.app" else {
            throw FetcherError.invalidBundle("unexpected app name \(appURL.lastPathComponent)")
        }
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw FetcherError.invalidBundle("missing Info.plist")
        }
        guard info["CFBundleIdentifier"] as? String == "com.chasesims.LoomTestingEdition" else {
            throw FetcherError.invalidBundle("wrong bundle identifier")
        }
        guard info["CFBundleName"] as? String == "Loom Testing Edition",
              info["CFBundleDisplayName"] as? String == "Loom Testing Edition" else {
            throw FetcherError.invalidBundle("wrong display name")
        }
        guard info["CFBundleExecutable"] as? String == "Loom Testing Edition" else {
            throw FetcherError.invalidBundle("wrong executable name")
        }
        let executable = appURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("Loom Testing Edition")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw FetcherError.invalidBundle("missing executable")
        }
        guard info["CFBundleShortVersionString"] as? String == expectedVersion else {
            throw FetcherError.invalidBundle("version does not match release tag")
        }
    }

    // MARK: - Checksum helpers

    private static var releaseSignaturePublicKeyBase64: String {
        Bundle.main.object(forInfoDictionaryKey: "LoomReleaseSignaturePublicKeyBase64") as? String ?? ""
    }

    private static func verifySignature(signatureURL: URL, signedData: Data) async throws {
        guard let publicKey = Data(base64Encoded: releaseSignaturePublicKeyBase64),
              !publicKey.isEmpty else {
            throw FetcherError.missingSignature
        }
        var request = URLRequest(url: signatureURL)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetcherError.badStatus(http.statusCode)
        }
        let body = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let signature = Data(base64Encoded: body) ?? data
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        guard key.isValidSignature(signature, for: signedData) else {
            throw FetcherError.signatureMismatch
        }
    }

    /// Fetches the published `.sha256` sidecar and extracts the hex digest.
    /// `shasum` / `sha256sum` output is "<hex>  <filename>"; we accept either
    /// the full line or just the hex (some publishers emit only the digest).
    private static func fetchChecksumBody(at url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // 8.0.18: 30s (was 10s). See note on fetchLatest above.
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetcherError.badStatus(http.statusCode)
        }
        return data
    }

    private static func parseExpectedChecksum(from data: Data) throws -> String {
        let body = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Take the first whitespace-separated token; either "<hex>" alone
        // or "<hex>  <filename>" both yield the digest.
        let token = body.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let hex = token.lowercased()
        // Sanity-check: SHA-256 hex is exactly 64 chars of [0-9a-f].
        let isValid = hex.count == 64 && hex.allSatisfy { $0.isHexDigit }
        guard isValid else {
            throw FetcherError.malformedPayload
        }
        return hex
    }

    /// Streams `url` through SHA256 in 256 KB chunks so we don't load a
    /// hundred-MB DMG into memory.
    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - GitHub payload

    private struct LatestReleasePayload: Decodable {
        let tag_name: String
        let assets: [AssetPayload]
    }

    private struct AssetPayload: Decodable {
        let name: String
        let browser_download_url: String
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
