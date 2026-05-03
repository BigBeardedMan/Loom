# project.yml

[`xcodegen`](https://github.com/yonaskolb/XcodeGen) source-of-truth for the Xcode project. Edit `project.yml`, run `xcodegen generate`, the `.xcodeproj` regenerates from scratch. The repo's `.xcodeproj` is committed for convenience but is treated as a build artifact — never edit it by hand.

## Header

```yaml
name: Loom
options:
  bundleIdPrefix: com.chasesims
  deploymentTarget:
    macOS: "14.0"
```

`macOS 14.0` is Sonoma. Lower would compile, but Loom uses SwiftData (`@Model`, `ModelContainer`) which is iOS 17 / macOS 14+, and `@Observable` which is the same.

## Base settings

```yaml
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.1.0"
    CURRENT_PROJECT_VERSION: "20"
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: YES
    SWIFT_STRICT_CONCURRENCY: complete
```

Notable:

- **`SWIFT_VERSION: "6.0"`** with **`SWIFT_STRICT_CONCURRENCY: complete`** — every type that crosses an actor boundary must be `Sendable`. New code should default to value types and `@MainActor` classes.
- **`CODE_SIGN_IDENTITY: "-"`** — ad-hoc. The DMG path expects this; flipping to a Developer ID identity also works.
- **`MARKETING_VERSION` is the source of truth for releases.** `bin/release.sh` parses it with `awk`. Bump both this and `CURRENT_PROJECT_VERSION` on every release.

## Packages

```yaml
packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    from: "1.2.0"
```

SwiftTerm is the only third-party dependency. It's pinned with a "from" range so patch updates flow in without manual intervention.

## Sources excludes

```yaml
sources:
  - path: Loom
    excludes:
      - "**/* 2.swift"
      - "**/* 3.swift"
      - "**/* 2.json"
      - "**/* 2.plist"
      - "**/* 2.entitlements"
```

These are iCloud's "shadow duplicates" — when iCloud Drive syncs a file mid-edit, it sometimes spits out `Foo 2.swift` next to `Foo.swift`. The excludes keep them out of the build target. The pre-build script also `find`s and deletes them defensively.

## Entitlements

```yaml
entitlements:
  path: Loom/Loom.entitlements
  properties:
    com.apple.security.app-sandbox: false
    com.apple.security.network.client: true
```

- **App Sandbox: off.** Loom needs to run subprocesses (`claude`, `zsh`), watch arbitrary directories (`~/.claude/tasks/`), and write to the user's working folders. The sandbox prevents all of that without a shopping list of entitlements that don't exist for personal apps.
- **Network client: on.** For the GitHub API poll, the Anthropic API, and local LLM HTTP traffic.

## Build phases

- **Pre-build: Sweep iCloud shadow duplicates.** `find ... -name "* 2.*" -o -name "* 3.*" -delete` — defensive cleanup before xcodegen sees the source list.
- **Post-build: Strip extended attributes.** `xattr -cr "$TARGET_BUILD_DIR/$WRAPPER_NAME"` — removes Finder/iCloud xattrs that confuse Gatekeeper on a fresh DMG.

## Regenerate

After editing `project.yml`:

```bash
xcodegen generate
```

If Xcode is open, close it first (Xcode caches the project model and the regenerate-while-open path occasionally chokes on schemes).
