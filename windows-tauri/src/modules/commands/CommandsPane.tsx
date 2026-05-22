import { useEffect, useState } from "react";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, type CommandRecord, type SessionInfo, type Workspace } from "../../lib/ipc";

type Props = { workspace: Workspace; blockId?: string };

const POLL_MS = 2000;

// Mirrors Loom/Terminal/CommandHistoryPaneView.swift.
// Surfaces the JSONL log Loom's PowerShell shim writes. Each row is one
// command: command text, cwd, duration, exit-code badge. Buttons copy or
// send back to the active terminal in the same workspace.
export function CommandsPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [records, setRecords] = useState<CommandRecord[]>([]);
  const [filterToWorkspace, setFilterToWorkspace] = useState(true);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [outputCache, setOutputCache] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    try {
      const cwd = filterToWorkspace ? workspace.folderPath || undefined : undefined;
      const list = await ipc.commandHistory.list(cwd);
      setRecords(list);
      setError(null);
    } catch (e) {
      setError(String(e));
    }
  };

  useEffect(() => {
    let alive = true;
    let timer: ReturnType<typeof setInterval> | null = null;
    const tick = async () => {
      if (!alive) return;
      await load();
    };
    tick();
    timer = setInterval(tick, POLL_MS);
    return () => {
      alive = false;
      if (timer) clearInterval(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.id, filterToWorkspace]);

  useEffect(() => {
    if (!blockId) return;
    setBlockStatus(blockId, "idle");
  }, [blockId, setBlockStatus]);

  const copyCommand = async (record: CommandRecord) => {
    try {
      await writeText(record.command);
      setCopiedId(record.id);
      setTimeout(() => setCopiedId((id) => (id === record.id ? null : id)), 1500);
    } catch {}
  };

  const sendToTerminal = async (record: CommandRecord) => {
    try {
      const sessions = (await ipc.terminal.list()) as SessionInfo[];
      const target = sessions.find((s) => {
        const cwd = (s.cwd ?? "").toLowerCase();
        const ws = (workspace.folderPath ?? "").toLowerCase();
        if (!ws) return true;
        return cwd === ws || cwd.startsWith(ws + "\\") || cwd.startsWith(ws + "/");
      });
      const sid = target?.id ?? sessions[0]?.id;
      if (!sid) return;
      const bytes = Array.from(new TextEncoder().encode(captureCommandText(record.command) + "\r"));
      await ipc.terminal.write(sid, bytes);
    } catch (e) {
      setError(String(e));
    }
  };

  const toggleExpand = async (record: CommandRecord) => {
    if (expandedId === record.id) {
      setExpandedId(null);
      return;
    }
    if (record.outputPath && outputCache[record.id] == null) {
      const body = await ipc.commandHistory.readOutput(record.outputPath).catch((e) => String(e));
      setOutputCache((prev) => ({ ...prev, [record.id]: body }));
    }
    setExpandedId(record.id);
  };

  return (
    <div
      className="flex h-full flex-col"
      style={{ background: "var(--color-loom-panel)" }}
    >
      <header
        className="flex items-center gap-2 flex-none"
        style={{
          padding: "7px 12px",
          background: "rgba(0,0,0,0.18)",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
        }}
      >
        <Icons.listBulletRect
          size={11}
          strokeWidth={2.4}
          style={{ color: "var(--color-ws-green)" }}
        />
        <span style={{ fontSize: 11, fontWeight: 600 }}>Recent Commands</span>
        {filterToWorkspace && workspace.folderPath && (
          <span
            style={{
              fontSize: 10,
              color: "rgba(255,255,255,0.45)",
              fontFamily: "var(--font-mono)",
              marginLeft: 2,
            }}
          >
            · {lastSegment(workspace.folderPath)}
          </span>
        )}
        <label className="ml-auto flex items-center gap-1.5" style={{ fontSize: 10, color: "rgba(255,255,255,0.7)" }}>
          <input
            type="checkbox"
            checked={filterToWorkspace}
            onChange={(e) => setFilterToWorkspace(e.target.checked)}
            style={{ accentColor: "var(--color-ws-green)" }}
          />
          Workspace only
        </label>
        <button
          onClick={load}
          aria-label="Refresh"
          title="Refresh now"
          style={{
            padding: 4,
            borderRadius: 4,
            color: "rgba(255,255,255,0.6)",
          }}
        >
          <Icons.refresh size={11} strokeWidth={2} />
        </button>
      </header>

      {error && (
        <div
          style={{
            margin: 8,
            padding: "6px 10px",
            background: "rgba(242,70,32,0.15)",
            border: "1px solid rgba(242,70,32,0.4)",
            borderRadius: 6,
            fontSize: 11,
            color: "rgba(255,160,140,0.9)",
          }}
        >
          {error}
        </div>
      )}

      {records.length === 0 ? (
        <div
          className="flex flex-1 flex-col items-center justify-center"
          style={{
            padding: 24,
            textAlign: "center",
            color: "rgba(255,255,255,0.45)",
          }}
        >
          <Icons.listBulletRect size={28} strokeWidth={1.2} />
          <div style={{ fontSize: 11, marginTop: 8, color: "rgba(255,255,255,0.7)" }}>
            {filterToWorkspace
              ? "No commands logged for this workspace yet."
              : "No commands logged yet."}
          </div>
          <div style={{ fontSize: 10, color: "rgba(255,255,255,0.35)", marginTop: 4, maxWidth: 280 }}>
            Install shell integration (Settings → Shell) and run something in a Loom terminal pane.
          </div>
        </div>
      ) : (
        <div className="scrollbar-thin flex-1 overflow-y-auto" style={{ padding: 8 }}>
          <div className="flex flex-col gap-1.5">
            {records.map((r) => (
              <Row
                key={r.id}
                record={r}
                copiedId={copiedId}
                onCopy={() => copyCommand(r)}
                onSend={() => sendToTerminal(r)}
                expanded={expandedId === r.id}
                output={outputCache[r.id]}
                onToggleExpand={() => toggleExpand(r)}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function Row({
  record,
  copiedId,
  onCopy,
  onSend,
  expanded,
  output,
  onToggleExpand,
}: {
  record: CommandRecord;
  copiedId: string | null;
  onCopy: () => void;
  onSend: () => void;
  expanded: boolean;
  output?: string;
  onToggleExpand: () => void;
}) {
  const succeeded = record.exitCode === 0;
  return (
    <div
      style={{
        padding: "6px 10px",
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.06)",
        borderRadius: 6,
      }}
    >
      <div className="flex items-start gap-1.5">
        <span
          title={succeeded ? "Exit 0" : `Exit ${record.exitCode}`}
          style={{
            display: "inline-flex",
            color: succeeded ? "var(--color-ws-green)" : "rgb(242,99,46)",
            marginTop: 1,
          }}
        >
          {succeeded ? (
            <Icons.checkCircle size={11} strokeWidth={2.2} />
          ) : (
            <Icons.failedCircle size={11} strokeWidth={2.2} />
          )}
        </span>
        <span
          style={{
            flex: 1,
            fontSize: 12,
            fontFamily: "var(--font-mono)",
            color: "rgba(255,255,255,0.92)",
            wordBreak: "break-word",
            lineHeight: 1.35,
            overflow: "hidden",
            textOverflow: "ellipsis",
            display: "-webkit-box",
            WebkitLineClamp: 2,
            WebkitBoxOrient: "vertical",
          }}
        >
          {record.command}
        </span>
        <button
          onClick={onCopy}
          aria-label="Copy command"
          title="Copy command to clipboard"
          style={{ padding: 3, color: "rgba(255,255,255,0.55)", borderRadius: 4 }}
        >
          {copiedId === record.id ? (
            <Icons.check size={10} strokeWidth={2.4} />
          ) : (
            <Icons.copy size={10} strokeWidth={2} />
          )}
        </button>
        <button
          onClick={onSend}
          aria-label="Send to terminal"
          title="Send to active terminal"
          style={{ padding: 3, color: "rgba(255,255,255,0.55)", borderRadius: 4 }}
        >
          <Icons.rerunReverse size={10} strokeWidth={2} />
        </button>
        {record.outputPath && (
          <button
            onClick={onToggleExpand}
            aria-label={expanded ? "Hide captured output" : "Show captured output"}
            title={expanded ? "Hide captured output" : "Show captured output"}
            style={{ padding: 3, color: "rgba(255,255,255,0.55)", borderRadius: 4 }}
          >
            {expanded ? (
              <Icons.chevronUp size={10} strokeWidth={2} />
            ) : (
              <Icons.chevronDown size={10} strokeWidth={2} />
            )}
          </button>
        )}
      </div>
      <div
        className="flex items-center gap-1.5"
        style={{
          marginTop: 2,
          fontSize: 10,
          color: "rgba(255,255,255,0.45)",
        }}
      >
        <span style={{ fontFamily: "var(--font-mono)" }}>{displayCwd(record.cwd)}</span>
        <span style={{ color: "rgba(255,255,255,0.25)" }}>·</span>
        <span>{relativeTime(record.startedAt)}</span>
        {record.durationMs >= 1000 && (
          <>
            <span style={{ color: "rgba(255,255,255,0.25)" }}>·</span>
            <span>{Math.floor(record.durationMs / 1000)}s</span>
          </>
        )}
      </div>
      {expanded && (
        <pre
          className="scrollbar-thin overflow-auto whitespace-pre-wrap"
          style={{
            marginTop: 6,
            maxHeight: 240,
            padding: 8,
            background: "rgba(0,0,0,0.18)",
            border: "1px solid rgba(255,255,255,0.08)",
            borderRadius: 4,
            fontSize: 11,
            color: "rgba(255,255,255,0.85)",
            fontFamily: "var(--font-mono)",
          }}
        >
          {output || "(empty)"}
        </pre>
      )}
    </div>
  );
}

function captureCommandText(command: string): string {
  return `Invoke-LoomCapture -Command '${command.replace(/'/g, "''")}'`;
}

function lastSegment(p: string): string {
  const parts = p.replace(/[\\/]$/, "").split(/[\\/]/);
  return parts[parts.length - 1] || p;
}

function displayCwd(p: string): string {
  if (!p) return "";
  const home = (
    (window as unknown as { __LOOM_HOME__?: string }).__LOOM_HOME__ ?? ""
  ).replace(/[\\/]$/, "");
  if (home && p.toLowerCase() === home.toLowerCase()) return "~";
  if (home && p.toLowerCase().startsWith(home.toLowerCase() + "\\")) {
    return "~" + p.slice(home.length);
  }
  return p;
}

function relativeTime(ms: number): string {
  if (!ms) return "";
  const diff = Date.now() - ms;
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}
