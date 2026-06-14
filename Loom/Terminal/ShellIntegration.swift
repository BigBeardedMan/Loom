import Foundation

/// Loom's shell integration. We drop managed shell startup files into a
/// Loom-owned directory, then launch supported shells through those shims.
/// Each shim sources the user's real config (so nothing they had stops
/// working) and then appends a JSONL record per command.
///
/// The result: every shell command run inside a Loom terminal turns into
/// a structured record on disk (no scrollback parsing required), which the
/// Commands panel surfaces in the UI. Output is *not* captured here; that's
/// a future expansion that needs a `script`-style PTY tee, which can break
/// interactive TUIs.
enum ShellIntegration {
    enum ShellKind {
        case zsh
        case bash
        case unsupported
    }

    struct LaunchConfiguration {
        let executable: String
        let args: [String]
        let execName: String
        let kind: ShellKind
    }

    /// Top-level integration directory. Lives inside Application Support so
    /// it survives the app sandbox lifecycle and never touches iCloud.
    static let supportDirectory: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Loom Testing Edition", isDirectory: true)
            .appendingPathComponent("shell", isDirectory: true)
    }()

    /// Where the shim zshrc lives. Filename has to be `.zshrc` so zsh
    /// picks it up automatically when `ZDOTDIR` points at this dir.
    static var zshShimURL: URL {
        supportDirectory.appendingPathComponent(".zshrc", isDirectory: false)
    }

    /// Backwards-compatible name used by Settings and older docs.
    static var shimURL: URL { zshShimURL }

    /// Bash reads this through `--rcfile` for Loom terminals whose `$SHELL`
    /// points at bash.
    static var bashShimURL: URL {
        supportDirectory.appendingPathComponent(".bashrc", isDirectory: false)
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
        if (try? String(contentsOf: zshShimURL, encoding: .utf8)) != zshShim {
            try? zshShim.write(to: zshShimURL, atomically: true, encoding: .utf8)
        }
        if (try? String(contentsOf: bashShimURL, encoding: .utf8)) != bashShim {
            try? bashShim.write(to: bashShimURL, atomically: true, encoding: .utf8)
        }
    }

    static func kind(for shellPath: String) -> ShellKind {
        switch (shellPath as NSString).lastPathComponent.lowercased() {
        case "zsh":
            return .zsh
        case "bash":
            return .bash
        default:
            return .unsupported
        }
    }

    static func supportsCapture(for shellPath: String) -> Bool {
        switch kind(for: shellPath) {
        case .zsh, .bash:
            return true
        case .unsupported:
            return false
        }
    }

    static func launchConfiguration(for shellPath: String, integrationEnabled: Bool) -> LaunchConfiguration {
        let name = (shellPath as NSString).lastPathComponent
        let kind = kind(for: shellPath)
        if integrationEnabled, kind == .bash {
            // Bash ignores --rcfile for login shells, so the managed rcfile
            // sources the user's normal profile files itself.
            return LaunchConfiguration(
                executable: shellPath,
                args: ["--rcfile", bashShimURL.path, "-i"],
                execName: name,
                kind: kind
            )
        }
        return LaunchConfiguration(
            executable: shellPath,
            args: ["-l"],
            execName: "-" + name,
            kind: kind
        )
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

    __loom_should_skip_history() {
      local cmd="$1"
      local lower="${cmd:l}"
      case "$lower" in
        gh\\ auth*|npm\\ token*|ssh-add*|aws\\ configure*|docker\\ login*|gcloud\\ auth*|az\\ login*|security\\ find-generic-password*|security\\ add-generic-password*|pass\\ *)
          return 0
          ;;
      esac
      if [[ "$cmd" =~ '(^|[;&|[:space:]])(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)[A-Za-z0-9_]*=' ]]; then
        return 0
      fi
      if [[ "$lower" == *"--password"* || "$lower" == *"--token"* || "$lower" == *"--api-key"* || "$lower" == *"authorization: bearer"* ]]; then
        return 0
      fi
      return 1
    }

    __loom_redact_command() {
      print -r -- "$1" | /usr/bin/sed -E \\
        -e 's/(authorization:[[:space:]]*bearer[[:space:]]+)[^[:space:]]+/\\1[REDACTED]/Ig' \\
        -e 's/(--(api-key|token|password|secret)(=|[[:space:]]+))[^[:space:]]+/\\1[REDACTED]/Ig' \\
        -e 's/((api[_-]?key|token|secret|password|passwd|credential)[[:space:]]*[:=][[:space:]]*)[^[:space:]"'"'"'`]+/\\1[REDACTED]/Ig'
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
        if __loom_should_skip_history "$__loom_cmd"; then
          unset __loom_cmd __loom_cmd_start
          __loom_last_capture_path=""
          return
        fi
        local safe_cmd=$(__loom_redact_command "$__loom_cmd")
        local cmd_json=$(__loom_json_escape "$safe_cmd")
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

    /// Bash does not have zsh's preexec/precmd hooks, so this shim uses
    /// PROMPT_COMMAND to record the completed history entry after each
    /// command. Duration is stored as zero for hand-typed bash commands; UI
    /// reruns that go through `__loom_capture` still record a measured span.
    static let bashShim: String = """
    # Loom bash shell integration. Auto-managed: edits get overwritten on next launch.

    __loom_bash_self="${BASH_SOURCE[0]}"
    __loom_log_dir="$(cd "$(dirname "$__loom_bash_self")" >/dev/null 2>&1 && pwd)"
    __loom_log_file="$__loom_log_dir/history.jsonl"
    __loom_capture_dir="$__loom_log_dir/output"
    __loom_last_capture_path=""
    __loom_last_history_line=""
    __loom_prompt_ready=0
    __loom_in_prompt=0

    if [[ -z "${__LOOM_BASH_USER_CONFIG_SOURCED:-}" ]]; then
      export __LOOM_BASH_USER_CONFIG_SOURCED=1
      if [[ -f "$HOME/.bash_profile" ]]; then
        source "$HOME/.bash_profile"
      elif [[ -f "$HOME/.bash_login" ]]; then
        source "$HOME/.bash_login"
      elif [[ -f "$HOME/.profile" ]]; then
        source "$HOME/.profile"
      fi
      [[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
    fi

    __loom_json_escape() {
      local s="$1"
      s="${s//\\\\/\\\\\\\\}"
      s="${s//\\"/\\\\\\"}"
      s="${s//$'\\n'/\\\\n}"
      s="${s//$'\\t'/\\\\t}"
      s="${s//$'\\r'/\\\\r}"
      printf '"%s"' "$s"
    }

    __loom_should_skip_history() {
      local cmd="$1"
      local lower
      lower=$(printf '%s' "$cmd" | /usr/bin/tr '[:upper:]' '[:lower:]')
      case "$lower" in
        gh\\ auth*|npm\\ token*|ssh-add*|aws\\ configure*|docker\\ login*|gcloud\\ auth*|az\\ login*|security\\ find-generic-password*|security\\ add-generic-password*|pass\\ *)
          return 0
          ;;
      esac
      if [[ "$cmd" =~ (^|[\\;\\&\\|[:space:]])(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL)[A-Za-z0-9_]*= ]]; then
        return 0
      fi
      if [[ "$lower" == *"--password"* || "$lower" == *"--token"* || "$lower" == *"--api-key"* || "$lower" == *"authorization: bearer"* ]]; then
        return 0
      fi
      return 1
    }

    __loom_redact_command() {
      printf '%s\\n' "$1" | /usr/bin/sed -E \\
        -e 's/(authorization:[[:space:]]*bearer[[:space:]]+)[^[:space:]]+/\\1[REDACTED]/Ig' \\
        -e 's/(--(api-key|token|password|secret)(=|[[:space:]]+))[^[:space:]]+/\\1[REDACTED]/Ig' \\
        -e 's/((api[_-]?key|token|secret|password|passwd|credential)[[:space:]]*[:=][[:space:]]*)[^[:space:]"'"'"'`]+/\\1[REDACTED]/Ig'
    }

    __loom_history_command() {
      HISTTIMEFORMAT= history 1 2>/dev/null | /usr/bin/sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//'
    }

    __loom_append_history_record() {
      local cmd="$1"
      local started="$2"
      local ended="$3"
      local exit_code="$4"
      [[ -z "$cmd" ]] && return
      if __loom_should_skip_history "$cmd"; then
        return
      fi
      local safe_cmd=$(__loom_redact_command "$cmd")
      local cmd_json=$(__loom_json_escape "$safe_cmd")
      local cwd_json=$(__loom_json_escape "$PWD")
      local sess_json=$(__loom_json_escape "${LOOM_SESSION_ID:-unknown}")
      local output_field=""
      if [[ -n "$__loom_last_capture_path" ]]; then
        output_field=",\\"output\\":$(__loom_json_escape "$__loom_last_capture_path")"
        __loom_last_capture_path=""
      fi
      printf '{"started":%s,"ended":%s,"exit":%s,"cwd":%s,"command":%s,"session":%s%s}\\n' \\
        "$started" "$ended" "$exit_code" "$cwd_json" "$cmd_json" "$sess_json" "$output_field" \\
        >> "$__loom_log_file" 2>/dev/null
    }

    __loom_capture() {
      local cmd="$1"
      mkdir -p "$__loom_capture_dir" 2>/dev/null
      local stamp=$(/bin/date +%s)
      local out="$__loom_capture_dir/cap-${stamp}-$$-${RANDOM}.out"
      local start_ts=$(/bin/date +%s)
      __loom_last_capture_path="$out"
      local pipefail_was_on=0
      set -o | /usr/bin/grep -q '^pipefail[[:space:]]*on' && pipefail_was_on=1
      set -o pipefail
      eval "$cmd" 2>&1 | tee "$out"
      local exit_code=${PIPESTATUS[0]}
      if [[ "$pipefail_was_on" == "1" ]]; then
        set -o pipefail
      else
        set +o pipefail
      fi
      local end_ts=$(/bin/date +%s)
      __loom_append_history_record "$cmd" "$start_ts" "$end_ts" "$exit_code"
      __loom_last_history_line="$(HISTTIMEFORMAT= history 1 2>/dev/null)"
      return "$exit_code"
    }

    __loom_precmd() {
      local exit_code=$?
      __loom_in_prompt=1
      if [[ "$__loom_prompt_ready" != "1" ]]; then
        __loom_prompt_ready=1
        __loom_in_prompt=0
        return "$exit_code"
      fi
      local raw_line
      raw_line="$(HISTTIMEFORMAT= history 1 2>/dev/null)"
      if [[ -n "$raw_line" && "$raw_line" != "$__loom_last_history_line" ]]; then
        local end_ts=$(/bin/date +%s)
        local cmd=$(__loom_history_command)
        __loom_append_history_record "$cmd" "$end_ts" "$end_ts" "$exit_code"
        __loom_last_history_line="$raw_line"
      fi
      __loom_in_prompt=0
      return "$exit_code"
    }

    if [[ "${PROMPT_COMMAND:-}" != *__loom_precmd* ]]; then
      if [[ -n "${PROMPT_COMMAND:-}" ]]; then
        PROMPT_COMMAND="__loom_precmd; ${PROMPT_COMMAND}"
      else
        PROMPT_COMMAND="__loom_precmd"
      fi
    fi
    """
}
