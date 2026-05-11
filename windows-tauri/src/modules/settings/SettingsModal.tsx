import { useEffect, useState } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, type McpServer } from "../../lib/ipc";
import { modal, radius, surface, text } from "../../lib/theme";

type Tab = "appearance" | "providers" | "mcp" | "shell" | "about";

// Mirrors Loom/Settings/SettingsScene.swift.
// 620x460 sheet, blurred backdrop, tab rail at 140px on the left.
export function SettingsModal() {
  const isOpen = useApp((s) => s.isSettingsOpen);
  const close = useApp((s) => s.closeSettings);
  const [tab, setTab] = useState<Tab>("providers");

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-40 flex items-center justify-center"
      style={{
        background: "rgba(0, 0, 0, 0.40)",
        backdropFilter: "blur(20px) saturate(180%)",
        WebkitBackdropFilter: "blur(20px) saturate(180%)",
      }}
      onClick={close}
    >
      <div
        className="flex overflow-hidden"
        style={{
          width: modal.settings.width,
          height: modal.settings.height,
          background: surface.panel,
          border: `1px solid ${surface.hairline}`,
          borderRadius: radius.panel,
          boxShadow: "0 24px 48px rgba(0, 0, 0, 0.45)",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <aside
          className="flex flex-col flex-none"
          style={{
            width: 140,
            padding: 8,
            background: surface.inset,
            borderRight: `1px solid ${surface.hairline}`,
          }}
        >
          <div
            className="flex items-center justify-between"
            style={{ padding: "4px 6px 8px" }}
          >
            <span className="section-header">Settings</span>
            <button
              onClick={close}
              className="rounded p-0.5"
              style={{ color: text.muted }}
              aria-label="Close"
            >
              <Icons.close size={12} strokeWidth={2} />
            </button>
          </div>
          {(
            [
              ["appearance", "Appearance"],
              ["providers", "AI Providers"],
              ["mcp", "MCP Servers"],
              ["shell", "Shell"],
              ["about", "About"],
            ] as [Tab, string][]
          ).map(([id, label]) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className="w-full text-left transition-colors"
              style={{
                padding: "6px 10px",
                borderRadius: 6,
                fontSize: 12,
                fontWeight: 500,
                color: tab === id ? text.primary : text.muted,
                background:
                  tab === id
                    ? "color-mix(in srgb, var(--color-loom-accent) 16%, transparent)"
                    : "transparent",
              }}
            >
              {label}
            </button>
          ))}
        </aside>
        <main className="flex-1 overflow-y-auto scrollbar-thin" style={{ padding: 24 }}>
          {tab === "appearance" && <AppearancePanel />}
          {tab === "providers" && <ProvidersPanel />}
          {tab === "mcp" && <McpPanel />}
          {tab === "shell" && <ShellPanel />}
          {tab === "about" && <AboutPanel />}
        </main>
      </div>
    </div>
  );
}

function H2({ children }: { children: React.ReactNode }) {
  return (
    <h2
      style={{
        fontSize: 14,
        fontWeight: 600,
        color: text.primary,
        marginBottom: 6,
      }}
    >
      {children}
    </h2>
  );
}

function Hint({ children }: { children: React.ReactNode }) {
  return (
    <p style={{ fontSize: 11, color: text.muted, marginBottom: 12, lineHeight: 1.5 }}>
      {children}
    </p>
  );
}

function AppearancePanel() {
  const [mode, setMode] = useState<"system" | "light" | "dark">(() => {
    const saved = localStorage.getItem("loom.theme");
    if (saved === "light" || saved === "dark" || saved === "system") return saved;
    return "system";
  });

  useEffect(() => {
    localStorage.setItem("loom.theme", mode);
    const root = document.documentElement;
    if (mode === "system") {
      root.removeAttribute("data-theme");
    } else {
      root.setAttribute("data-theme", mode);
    }
  }, [mode]);

  const opts: { value: typeof mode; label: string; icon: keyof typeof Icons }[] = [
    { value: "system", label: "System", icon: "appearanceSystem" },
    { value: "light", label: "Light", icon: "appearanceLight" },
    { value: "dark", label: "Dark", icon: "appearanceDark" },
  ];

  return (
    <div>
      <H2>Appearance</H2>
      <Hint>Match system preference, or pick a fixed theme. Mirrors AppearanceSetting on macOS.</Hint>
      <div
        className="flex gap-1 flex-none"
        style={{
          padding: 4,
          background: surface.inset,
          borderRadius: 8,
          width: "fit-content",
        }}
      >
        {opts.map((o) => {
          const Icon = Icons[o.icon];
          const active = mode === o.value;
          return (
            <button
              key={o.value}
              onClick={() => setMode(o.value)}
              className="flex items-center gap-1.5"
              style={{
                padding: "6px 12px",
                borderRadius: 6,
                fontSize: 12,
                fontWeight: 500,
                color: active ? text.primary : text.muted,
                background: active ? surface.panel : "transparent",
                boxShadow: active ? "0 1px 2px rgba(0, 0, 0, 0.15)" : "none",
              }}
            >
              <Icon size={13} strokeWidth={1.8} />
              {o.label}
            </button>
          );
        })}
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
      if (anthropic) await ipc.keychain.set("loom.anthropic", "default", anthropic);
      else await ipc.keychain.delete("loom.anthropic", "default");
      setSaved(true);
      setTimeout(() => setSaved(false), 1400);
    } finally {
      setSaving(false);
    }
  };

  if (!loaded) return <div style={{ fontSize: 12, color: text.muted }}>Loading…</div>;

  return (
    <div>
      <H2>AI Providers</H2>
      <Hint>
        Keys stored in Windows Credential Manager. Empty value removes the entry.
      </Hint>
      <label style={{ fontSize: 11, color: text.muted, display: "block", marginBottom: 6 }}>
        Anthropic API key
      </label>
      <input
        type="password"
        value={anthropic}
        onChange={(e) => setAnthropic(e.target.value)}
        placeholder="sk-ant-…"
        className="w-full focus:outline-none"
        style={{
          background: "var(--color-loom-bg-from)",
          border: `1px solid ${surface.hairline}`,
          borderRadius: 8,
          padding: "8px 12px",
          fontSize: 13,
          color: text.primary,
          fontFamily: "var(--font-mono)",
          marginBottom: 12,
        }}
      />
      <button
        onClick={save}
        disabled={saving}
        className="flex items-center gap-1.5"
        style={{
          background: "var(--color-loom-accent)",
          color: "white",
          borderRadius: 8,
          padding: "6px 14px",
          fontSize: 12,
          fontWeight: 500,
          border: "none",
          opacity: saving ? 0.5 : 1,
        }}
      >
        {saving && <Icons.spinner size={12} className="animate-spin" />}
        {saved && <Icons.check size={12} strokeWidth={2.4} />}
        {saved ? "Saved" : "Save"}
      </button>
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
    <div>
      <H2>MCP Servers</H2>
      <Hint>Managed via the Claude CLI (`claude mcp list/add/remove`).</Hint>
      {error && (
        <div
          style={{
            background: "rgba(242, 70, 32, 0.10)",
            border: `1px solid ${surface.hairline}`,
            borderRadius: 8,
            padding: 10,
            fontSize: 11,
            color: "var(--color-ws-orange)",
            marginBottom: 12,
          }}
        >
          {error}
        </div>
      )}
      {servers.length === 0 && !error && (
        <div
          style={{
            border: `1px dashed ${surface.hairline}`,
            borderRadius: 8,
            padding: 20,
            textAlign: "center",
            fontSize: 11,
            color: text.tertiary,
          }}
        >
          No MCP servers configured.
        </div>
      )}
      <ul style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        {servers.map((s) => (
          <li
            key={s.name}
            style={{
              background: surface.inset,
              border: `1px solid ${surface.hairline}`,
              borderRadius: 8,
              padding: "8px 12px",
              fontSize: 12,
            }}
          >
            <div style={{ fontWeight: 600, color: text.primary }}>{s.name}</div>
            <div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: text.muted }}>
              {s.command} {s.args.join(" ")}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

function ShellPanel() {
  const [path, setPath] = useState<string | null>(null);
  const [installing, setInstalling] = useState(false);

  const install = async () => {
    setInstalling(true);
    try {
      const p = await ipc.shell.installIntegration();
      setPath(p);
    } finally {
      setInstalling(false);
    }
  };

  return (
    <div>
      <H2>Shell Integration</H2>
      <Hint>
        Installs a PowerShell profile hook recording every command to{" "}
        <code style={{ fontFamily: "var(--font-mono)" }}>%LOCALAPPDATA%\Loom\history.jsonl</code>{" "}
        for the Commands pane and the agent.
      </Hint>
      <button
        onClick={install}
        disabled={installing}
        style={{
          background: "var(--color-loom-accent)",
          color: "white",
          borderRadius: 8,
          padding: "6px 14px",
          fontSize: 12,
          fontWeight: 500,
          border: "none",
          opacity: installing ? 0.5 : 1,
        }}
      >
        {installing ? "Installing…" : path ? "Reinstall" : "Install"}
      </button>
      {path && (
        <div style={{ marginTop: 10, fontSize: 11, color: text.tertiary }}>
          Wrote to <code style={{ fontFamily: "var(--font-mono)" }}>{path}</code>
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
    <div>
      <H2>About Loom</H2>
      <div style={{ fontSize: 13, color: text.muted, marginBottom: 8 }}>
        Version <span style={{ fontFamily: "var(--font-mono)", color: text.primary }}>{version}</span>
      </div>
      <Hint>
        Workspace cockpit for Windows. Built with Tauri + Rust + React. Mirrors the macOS Loom feature surface.
      </Hint>
    </div>
  );
}
