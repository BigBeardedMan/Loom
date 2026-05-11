import { useEffect, useState } from "react";
import { X, Check, Loader2 } from "lucide-react";
import { useApp } from "../../lib/store";
import { ipc, type McpServer } from "../../lib/ipc";

type Tab = "providers" | "mcp" | "shell" | "about";

export function SettingsModal() {
  const isOpen = useApp((s) => s.isSettingsOpen);
  const close = useApp((s) => s.closeSettings);
  const [tab, setTab] = useState<Tab>("providers");

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-40 flex items-center justify-center bg-black/60"
      onClick={close}
    >
      <div
        className="flex h-[600px] w-[840px] max-w-[95vw] overflow-hidden rounded-xl border border-loom-border bg-loom-panel shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <aside className="w-44 border-r border-loom-border bg-loom-panel-elev p-2">
          <div className="mb-2 flex items-center justify-between px-2">
            <span className="text-xs font-medium uppercase tracking-wider text-loom-text-mute">
              Settings
            </span>
            <button
              onClick={close}
              className="rounded p-1 text-loom-text-mute hover:bg-loom-border hover:text-loom-text"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
          {(
            [
              ["providers", "AI Providers"],
              ["mcp", "MCP Servers"],
              ["shell", "Shell"],
              ["about", "About"],
            ] as [Tab, string][]
          ).map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`w-full rounded px-2 py-1 text-left text-sm ${
                tab === id
                  ? "bg-loom-panel text-loom-text"
                  : "text-loom-text-dim hover:bg-loom-panel hover:text-loom-text"
              }`}
            >
              {label}
            </button>
          ))}
        </aside>
        <main className="flex-1 overflow-y-auto scrollbar-thin p-6">
          {tab === "providers" && <ProvidersPanel />}
          {tab === "mcp" && <McpPanel />}
          {tab === "shell" && <ShellPanel />}
          {tab === "about" && <AboutPanel />}
        </main>
      </div>
    </div>
  );
}

function ProvidersPanel() {
  const [anthropic, setAnthropic] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    ipc.keychain
      .get("loom.anthropic", "default")
      .then((v) => {
        setAnthropic(v ?? "");
        setLoaded(true);
      })
      .catch(() => setLoaded(true));
  }, []);

  const save = async () => {
    setSaving(true);
    try {
      if (anthropic) {
        await ipc.keychain.set("loom.anthropic", "default", anthropic);
      } else {
        await ipc.keychain.delete("loom.anthropic", "default");
      }
      setSaved(true);
      setTimeout(() => setSaved(false), 1500);
    } finally {
      setSaving(false);
    }
  };

  if (!loaded) return <div className="text-sm text-loom-text-mute">Loading…</div>;

  return (
    <div className="space-y-4">
      <h2 className="text-base font-medium">AI Providers</h2>
      <p className="text-xs text-loom-text-mute">
        Keys are stored in Windows Credential Manager. Empty value removes the entry.
      </p>
      <div className="space-y-2">
        <label className="block text-xs text-loom-text-dim">Anthropic API key</label>
        <input
          type="password"
          value={anthropic}
          onChange={(e) => setAnthropic(e.target.value)}
          placeholder="sk-ant-…"
          className="w-full rounded-md border border-loom-border bg-loom-bg px-3 py-2 text-sm text-loom-text focus:border-loom-accent focus:outline-none"
        />
        <button
          onClick={save}
          disabled={saving}
          className="flex items-center gap-1.5 rounded-md bg-loom-accent px-3 py-1.5 text-sm text-white hover:opacity-90 disabled:opacity-50"
        >
          {saving ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : saved ? (
            <Check className="h-3.5 w-3.5" />
          ) : null}
          {saved ? "Saved" : "Save"}
        </button>
      </div>
    </div>
  );
}

function McpPanel() {
  const [servers, setServers] = useState<McpServer[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    ipc.agents
      .mcpList()
      .then(setServers)
      .catch((e) => setError(String(e)));
  }, []);

  return (
    <div className="space-y-3">
      <h2 className="text-base font-medium">MCP Servers</h2>
      <p className="text-xs text-loom-text-mute">
        Managed via the Claude CLI (`claude mcp list/add/remove`).
      </p>
      {error && (
        <div className="rounded border border-loom-border bg-red-500/10 px-3 py-2 text-xs text-red-300">
          {error}
        </div>
      )}
      {servers.length === 0 && !error && (
        <div className="rounded border border-dashed border-loom-border px-3 py-6 text-center text-xs text-loom-text-mute">
          No MCP servers configured.
        </div>
      )}
      <ul className="space-y-1">
        {servers.map((s) => (
          <li
            key={s.name}
            className="rounded border border-loom-border bg-loom-bg px-3 py-2 text-sm"
          >
            <div className="font-medium">{s.name}</div>
            <div className="font-mono text-xs text-loom-text-mute">
              {s.command} {s.args.join(" ")}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

function ShellPanel() {
  const [installed, setInstalled] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [path, setPath] = useState<string | null>(null);

  const install = async () => {
    setInstalling(true);
    try {
      const p = await ipc.shell.installIntegration();
      setPath(p);
      setInstalled(true);
    } finally {
      setInstalling(false);
    }
  };

  return (
    <div className="space-y-3">
      <h2 className="text-base font-medium">Shell Integration</h2>
      <p className="text-xs text-loom-text-mute">
        Installs a PowerShell profile hook that records every command to{" "}
        <code className="font-mono text-loom-text-dim">
          %LOCALAPPDATA%\Loom\history.jsonl
        </code>{" "}
        for the Commands pane and the agent.
      </p>
      <button
        onClick={install}
        disabled={installing}
        className="rounded-md bg-loom-accent px-3 py-1.5 text-sm text-white hover:opacity-90 disabled:opacity-50"
      >
        {installing ? "Installing…" : installed ? "Reinstall" : "Install"}
      </button>
      {path && (
        <div className="text-xs text-loom-text-mute">
          Wrote to <code className="font-mono">{path}</code>
        </div>
      )}
    </div>
  );
}

function AboutPanel() {
  const [version, setVersion] = useState("");
  useEffect(() => {
    ipc.appVersion().then(setVersion);
  }, []);
  return (
    <div className="space-y-3">
      <h2 className="text-base font-medium">About Loom</h2>
      <div className="text-sm text-loom-text-dim">
        Version <span className="font-mono">{version}</span>
      </div>
      <div className="text-xs text-loom-text-mute">
        Workspace cockpit for Windows. Built with Tauri + Rust + React.
      </div>
    </div>
  );
}
