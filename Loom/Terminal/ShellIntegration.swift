import Foundation

/// Loom's zsh shell integration. We drop a stub `.zshrc` into a Loom-owned
/// directory, then point the terminal session at that directory via
/// `ZDOTDIR` so zsh sources our shim *first*. The shim sources the user's
/// real config (so nothing they had stops working) and then registers
/// `precmd` / `preexec` hooks that append a JSONL record per command.
///
/// The result: every shell command run inside a Loom terminal turns into
/// a structured record on disk (no scrollback parsing required), which the
/// Commands panel surfaces in the UI. Output is *not* captured here; that's
/// a future expansion that needs a `script`-style PTY tee, which can break
/// interactive TUIs.
enum ShellIntegration {
    /// Top-level integration directory. Lives inside Application Support so
    /// it survives the app sandbox lifecycle and never touches iCloud.
    static let supportDirectory: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Loom", isDirectory: true)
            .appendingPathComponent("shell", isDirectory: true)
    }()

    /// Where the shim zshrc lives. Filename has to be `.zshrc` so zsh
    /// picks it up automatically when `ZDOTDIR` points at this dir.
    static var shimURL: URL {
        supportDirectory.appendingPathComponent(".zshrc", isDirectory: false)
    }

    /// JSONL log every command appends to. Each line is one record:
    /// `{"started":..,"ended":..,"exit":..,"cwd":..,"command":..,"session":..,"output":..?}`
    static var historyLogURL: URL {
        supportDirectory.appendingPathComponent("history.jsonl", isDirectory: false)
    }

    /// Directory where Loom's `__loom_capture` shim writes stdout+stderr
    /// of opt-in commands. One file per captured command.
    static var captureDirectory: URL {
        supportDirectory.appendingPathComponent("output", isDirectory: true)
    }

    /// Write the shim zshrc to disk if missing or out of date. Idempotent;
    /// rewrites only when the on-disk content differs from the canonical
    /// payload, so subsequent launches are cheap.
    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        if let existing = try? String(contentsOf: shimURL, encoding: .utf8),
           existing == zshShim {
            return
        }
        try? zshShim.write(to: shimURL, atomically: true, encoding: .utf8)
    }

    /// The full payload Loom writes to ~/Library/Application Support/Loom/shell/.zshrc.
    /// Sources the user's real zsh config first so nothing they expect to
    /// load goes missing, then layers Loom's history hooks on top.
    static let zshShim: String = """
    # Loom shell integration. Auto-managed: edits get overwritten on next launch.

    __loom_zdotdir_self="${ZDOTDIR:-$HOME}"

    # Bounce ZDOTDIR back to the user's normal home so subsequent sourcing
    # of the user's own config files (which may reference $ZDOTDIR) finds
    # the right place. We only need ZDOTDIR=loom for the initial bootstrap.
    ZDOTDIR="$HOME"

    [[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
    [[ -f "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
    [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
    [[ -f "$HOME/.zlogin" ]] && source "$HOME/.zlogin"

    __loom_log_dir="$__loom_zdotdir_self"
    __loom_log_file="$__loom_log_dir/history.jsonl"
    __loom_capture_dir="$__loom_log_dir/output"
    typeset -g __loom_last_capture_path=""

    __loom_json_escape() {
      local s="$1"
      s="${s//\\\\/\\\\\\\\}"
      s="${s//\\"/\\\\\\"}"
      s="${s//$'\\n'/\\\\n}"
      s="${s//$'\\t'/\\\\t}"
      s="${s//$'\\r'/\\\\r}"
      print -r -- "\\"$s\\""
    }

    # Loom-internal: wrap a single command so its stdout+stderr is also
    # tee'd to a per-command file under output/. Loom's submit() API
    # invokes this for programmatic sends so the cards can show output;
    # hand-typed commands skip this path entirely so interactive TUIs
    # like vim/top/ssh keep working unchanged.
    __loom_capture() {
      local cmd="$1"
      mkdir -p "$__loom_capture_dir" 2>/dev/null
      # Timestamp + PID + $RANDOM gives a unique filename without depending
      # on mktemp's template-suffix handling (BSD mktemp on macOS leaves
      # XXXXXX literal when there's an extension after it).
      local stamp=$(/bin/date +%s)
      local out="$__loom_capture_dir/cap-${stamp}-$$-${RANDOM}.out"
      __loom_last_capture_path="$out"
      setopt local_options pipefail
      eval "$cmd" 2>&1 | tee "$out"
      return ${pipestatus[1]}
    }

    __loom_preexec() {
      __loom_cmd="$1"
      __loom_cmd_start=$(/bin/date +%s)
    }

    __loom_precmd() {
      local exit_code=$?
      if [[ -n "$__loom_cmd" ]]; then
        local end_ts=$(/bin/date +%s)
        local cmd_json=$(__loom_json_escape "$__loom_cmd")
        local cwd_json=$(__loom_json_escape "$PWD")
        local sess_json=$(__loom_json_escape "${LOOM_SESSION_ID:-unknown}")
        local output_field=""
        if [[ -n "$__loom_last_capture_path" ]]; then
          output_field=",\\"output\\":$(__loom_json_escape "$__loom_last_capture_path")"
          __loom_last_capture_path=""
        fi
        printf '{"started":%s,"ended":%s,"exit":%s,"cwd":%s,"command":%s,"session":%s%s}\\n' \\
          "$__loom_cmd_start" "$end_ts" "$exit_code" "$cwd_json" "$cmd_json" "$sess_json" "$output_field" \\
          >> "$__loom_log_file" 2>/dev/null
        unset __loom_cmd __loom_cmd_start
      fi
    }

    typeset -ga precmd_functions preexec_functions
    if (( ! ${precmd_functions[(I)__loom_precmd]} )); then
      precmd_functions+=(__loom_precmd)
    fi
    if (( ! ${preexec_functions[(I)__loom_preexec]} )); then
      preexec_functions+=(__loom_preexec)
    fi
    """
}
