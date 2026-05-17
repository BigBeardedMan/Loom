import { useEffect, useState } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, type LocalEndpoint, type McpServer } from "../../lib/ipc";
import { modal, radius, surface, text } from "../../lib/theme";

type Tab = "appearance" | "providers" | "mcp" | "shell" | "tasks" | "advanced" | "about";

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
              ["tasks", "Tasks"],
              ["advanced", "Advanced"],
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
          {tab === "tasks" && <TasksPanel />}
          {tab === "advanced" && <AdvancedPanel />}
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
  const mode = useApp((s) => s.theme);
  const setMode = useApp((s) => s.setTheme);

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
  const [endpoints, setEndpoints] = useState<LocalEndpoint[]>([]);
  const [editing, setEditing] = useState<EndpointDraft | null>(null);

  const refresh = () => ipc.endpoints.list().then(setEndpoints).catch(() => {});

  useEffect(() => {
    ipc.keychain
      .get("loom.anthropic", "default")
      .then((v) => {
        setAnthropic(v ?? "");
        setLoaded(true);
      })
      .catch(() => setLoaded(true));
    refresh();
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

  const deleteEndpoint = async (id: string, name: string) => {
    if (!confirm(`Delete endpoint "${name}"?`)) return;
    await ipc.endpoints.delete(id);
    await ipc.keychain.delete("loom.endpoint", id).catch(() => {});
    refresh();
  };

  if (!loaded) return <div style={{ fontSize: 12, color: text.muted }}>Loading…</div>;

  return (
    <div className="flex flex-col gap-5">
      <section>
        <H2>Anthropic API</H2>
        <Hint>Stored in Windows Credential Manager. Empty value removes the entry.</Hint>
        <label style={{ fontSize: 11, color: text.muted, display: "block", marginBottom: 6 }}>
          API key
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
            marginBottom: 10,
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
      </section>

      <section>
        <div className="flex items-center gap-2" style={{ marginBottom: 4 }}>
          <H2>Local endpoints</H2>
          <button
            onClick={() =>
              setEditing({
                name: "",
                baseUrl: "",
                kind: "ollama",
                defaultModel: "",
                requiresAuth: false,
                authToken: "",
              })
            }
            style={{
              marginLeft: "auto",
              padding: "4px 10px",
              fontSize: 11,
              borderRadius: 6,
              background: "var(--color-loom-accent)",
              color: "white",
              border: 0,
            }}
          >
            + Add endpoint
          </button>
        </div>
        <Hint>
          Add an Ollama (<code>http://localhost:11434</code>) or any OpenAI-compatible base URL.
          Auth tokens (if any) live in Credential Manager.
        </Hint>
        {endpoints.length === 0 ? (
          <div
            style={{
              padding: "10px 12px",
              border: `1px dashed ${surface.hairline}`,
              borderRadius: 8,
              fontSize: 12,
              color: text.muted,
              textAlign: "center",
            }}
          >
            No endpoints yet.
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {endpoints.map((e) => (
              <EndpointRow
                key={e.id}
                endpoint={e}
                onEdit={() =>
                  setEditing({
                    id: e.id,
                    name: e.name,
                    baseUrl: e.baseUrl,
                    kind: e.kind,
                    defaultModel: e.defaultModel,
                    requiresAuth: e.requiresAuth,
                    authToken: "",
                  })
                }
                onDelete={() => deleteEndpoint(e.id, e.name)}
              />
            ))}
          </div>
        )}
      </section>

      {editing && (
        <EndpointEditor
          draft={editing}
          onCancel={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            refresh();
          }}
        />
      )}
    </div>
  );
}

type EndpointDraft = {
  id?: string;
  name: string;
  baseUrl: string;
  kind: "ollama" | "openai-compat";
  defaultModel: string;
  requiresAuth: boolean;
  authToken: string;
};

function EndpointRow({
  endpoint,
  onEdit,
  onDelete,
}: {
  endpoint: LocalEndpoint;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const [testing, setTesting] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);

  const test = async () => {
    setTesting(true);
    setResult(null);
    try {
      const token = endpoint.requiresAuth
        ? (await ipc.keychain.get("loom.endpoint", endpoint.id).catch(() => null)) ?? undefined
        : undefined;
      const r = await ipc.endpoints.test(endpoint.id, token);
      setResult({ ok: r.ok, message: r.message });
    } catch (e) {
      setResult({ ok: false, message: String(e) });
    } finally {
      setTesting(false);
    }
  };

  return (
    <div
      style={{
        padding: "10px 12px",
        background: "rgba(255,255,255,0.04)",
        border: `1px solid ${surface.hairline}`,
        borderRadius: 8,
      }}
    >
      <div className="flex items-center gap-2">
        <span style={{ fontSize: 12, fontWeight: 600, color: text.primary }}>{endpoint.name}</span>
        <span
          style={{
            fontSize: 10,
            padding: "1px 6px",
            borderRadius: 999,
            background: surface.softPanel,
            color: text.muted,
            textTransform: "uppercase",
            letterSpacing: 0.4,
            fontWeight: 600,
          }}
        >
          {endpoint.kind}
        </span>
        <button
          onClick={test}
          disabled={testing}
          className="ml-auto"
          style={{
            padding: "3px 8px",
            fontSize: 10,
            borderRadius: 6,
            background: "rgba(255,255,255,0.06)",
            border: `1px solid ${surface.hairline}`,
            color: text.primary,
            opacity: testing ? 0.5 : 1,
          }}
        >
          {testing ? "Testing…" : "Test"}
        </button>
        <button
          onClick={onEdit}
          style={{
            padding: "3px 8px",
            fontSize: 10,
            borderRadius: 6,
            background: "rgba(255,255,255,0.06)",
            border: `1px solid ${surface.hairline}`,
            color: text.primary,
          }}
        >
          Edit
        </button>
        <button
          onClick={onDelete}
          aria-label="Delete endpoint"
          style={{
            padding: 4,
            borderRadius: 6,
            color: text.tertiary,
          }}
        >
          <Icons.trash size={11} strokeWidth={2} />
        </button>
      </div>
      <div
        style={{
          fontSize: 11,
          color: text.muted,
          fontFamily: "var(--font-mono)",
          marginTop: 4,
          wordBreak: "break-all",
        }}
      >
        {endpoint.baseUrl}
        {endpoint.defaultModel && ` · ${endpoint.defaultModel}`}
      </div>
      {result && (
        <div
          style={{
            marginTop: 6,
            fontSize: 11,
            color: result.ok ? "var(--color-ws-green)" : "rgb(242,99,46)",
          }}
        >
          {result.ok ? "✓ " : "✕ "}
          {result.message}
        </div>
      )}
    </div>
  );
}

function EndpointEditor({
  draft,
  onCancel,
  onSaved,
}: {
  draft: EndpointDraft;
  onCancel: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(draft.name);
  const [baseUrl, setBaseUrl] = useState(draft.baseUrl);
  const [kind, setKind] = useState<"ollama" | "openai-compat">(draft.kind);
  const [defaultModel, setDefaultModel] = useState(draft.defaultModel);
  const [requiresAuth, setRequiresAuth] = useState(draft.requiresAuth);
  const [authToken, setAuthToken] = useState(draft.authToken);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = async () => {
    if (!name.trim() || !baseUrl.trim()) {
      setError("Name and base URL are required.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const saved = await ipc.endpoints.upsert({
        id: draft.id,
        name: name.trim(),
        baseUrl: baseUrl.trim(),
        kind,
        defaultModel: defaultModel.trim(),
        requiresAuth,
      });
      if (requiresAuth && authToken) {
        await ipc.keychain.set("loom.endpoint", saved.id, authToken);
      } else if (!requiresAuth) {
        await ipc.keychain.delete("loom.endpoint", saved.id).catch(() => {});
      }
      onSaved();
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.45)", zIndex: 80 }}
      onClick={onCancel}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: 420,
          background: "var(--color-loom-panel)",
          color: "var(--color-loom-text)",
          border: `1px solid ${surface.hairline}`,
          borderRadius: 14,
          padding: 18,
          boxShadow: "0 20px 50px rgba(0,0,0,0.45)",
        }}
      >
        <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>
          {draft.id ? "Edit endpoint" : "New endpoint"}
        </h3>
        <div className="flex flex-col gap-2.5">
          <Field label="Name">
            <input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Local Ollama"
              style={fieldStyle}
            />
          </Field>
          <Field label="Kind">
            <div className="flex gap-1.5">
              {(["ollama", "openai-compat"] as const).map((k) => (
                <button
                  key={k}
                  onClick={() => setKind(k)}
                  style={{
                    flex: 1,
                    padding: "5px 8px",
                    fontSize: 11,
                    borderRadius: 6,
                    border: `1px solid ${
                      k === kind ? "var(--color-loom-accent)" : surface.hairline
                    }`,
                    background:
                      k === kind
                        ? "color-mix(in srgb, var(--color-loom-accent) 12%, transparent)"
                        : "transparent",
                    color: k === kind ? text.primary : text.muted,
                  }}
                >
                  {k === "ollama" ? "Ollama" : "OpenAI-compatible"}
                </button>
              ))}
            </div>
          </Field>
          <Field label="Base URL">
            <input
              value={baseUrl}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder={
                kind === "ollama" ? "http://localhost:11434" : "https://api.example.com"
              }
              style={fieldStyle}
            />
          </Field>
          <Field label="Default model (optional)">
            <input
              value={defaultModel}
              onChange={(e) => setDefaultModel(e.target.value)}
              placeholder={kind === "ollama" ? "llama3.2" : "gpt-4o-mini"}
              style={fieldStyle}
            />
          </Field>
          <label className="flex items-center gap-2" style={{ fontSize: 12, color: text.primary }}>
            <input
              type="checkbox"
              checked={requiresAuth}
              onChange={(e) => setRequiresAuth(e.target.checked)}
              style={{ accentColor: "var(--color-loom-accent)" }}
            />
            Requires bearer token
          </label>
          {requiresAuth && (
            <Field label="Token">
              <input
                type="password"
                value={authToken}
                onChange={(e) => setAuthToken(e.target.value)}
                placeholder="sk-…"
                style={{ ...fieldStyle, fontFamily: "var(--font-mono)" }}
              />
              {draft.id && (
                <div style={{ fontSize: 10, color: text.tertiary, marginTop: 4 }}>
                  Leave blank to keep the existing token.
                </div>
              )}
            </Field>
          )}
          {error && (
            <div
              style={{
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
        </div>
        <div className="flex justify-end gap-2" style={{ marginTop: 12 }}>
          <button
            onClick={onCancel}
            style={{
              padding: "6px 14px",
              fontSize: 12,
              borderRadius: 8,
              background: "rgba(255,255,255,0.06)",
              border: `1px solid ${surface.hairline}`,
              color: text.primary,
            }}
          >
            Cancel
          </button>
          <button
            onClick={save}
            disabled={busy}
            style={{
              padding: "6px 14px",
              fontSize: 12,
              fontWeight: 600,
              borderRadius: 8,
              background: "var(--color-loom-accent)",
              color: "white",
              border: 0,
              opacity: busy ? 0.5 : 1,
            }}
          >
            {busy ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}

const fieldStyle: React.CSSProperties = {
  width: "100%",
  background: "var(--color-loom-bg-from)",
  border: `1px solid var(--color-loom-hairline)`,
  borderRadius: 6,
  padding: "5px 8px",
  fontSize: 12,
  color: "var(--color-loom-text)",
  outline: "none",
};

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label
        style={{
          fontSize: 11,
          color: "var(--color-loom-text-muted, rgba(255,255,255,0.5))",
          display: "block",
          marginBottom: 4,
        }}
      >
        {label}
      </label>
      {children}
    </div>
  );
}

function McpPanel() {
  const [servers, setServers] = useState<McpServer[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);

  const refresh = () =>
    ipc.agents
      .mcpList()
      .then((s) => {
        setServers(s);
        setError(null);
      })
      .catch((e) => setError(String(e)));

  useEffect(() => {
    refresh();
  }, []);

  const remove = async (name: string) => {
    if (!confirm(`Remove MCP server "${name}"?`)) return;
    try {
      await ipc.agents.mcpRemove(name);
      refresh();
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <div>
      <div className="flex items-center gap-2" style={{ marginBottom: 4 }}>
        <H2>MCP Servers</H2>
        <button
          onClick={() => setAdding(true)}
          style={{
            marginLeft: "auto",
            padding: "4px 10px",
            fontSize: 11,
            borderRadius: 6,
            background: "var(--color-loom-accent)",
            color: "white",
            border: 0,
          }}
        >
          + Add server
        </button>
        <button
          onClick={refresh}
          aria-label="Refresh"
          style={{
            padding: 4,
            borderRadius: 6,
            color: text.muted,
          }}
        >
          <Icons.refresh size={12} strokeWidth={2} />
        </button>
      </div>
      <Hint>
        Loom delegates to <code>claude mcp</code>. Add / remove rounds-trip through the CLI so
        your other Claude Code clients see the same set.
      </Hint>
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
            className="flex items-center gap-2"
            style={{
              background: surface.inset,
              border: `1px solid ${surface.hairline}`,
              borderRadius: 8,
              padding: "8px 12px",
              fontSize: 12,
            }}
          >
            <div className="flex-1 min-w-0">
              <div style={{ fontWeight: 600, color: text.primary }}>{s.name}</div>
              <div
                style={{
                  fontFamily: "var(--font-mono)",
                  fontSize: 11,
                  color: text.muted,
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
              >
                {s.command} {s.args.join(" ")}
              </div>
            </div>
            <button
              onClick={() => remove(s.name)}
              aria-label="Remove server"
              style={{ padding: 4, borderRadius: 6, color: text.tertiary }}
            >
              <Icons.trash size={11} strokeWidth={2} />
            </button>
          </li>
        ))}
      </ul>
      {adding && (
        <McpAddModal
          onCancel={() => setAdding(false)}
          onAdded={() => {
            setAdding(false);
            refresh();
          }}
          onError={(e) => setError(e)}
        />
      )}
    </div>
  );
}

function McpAddModal({
  onCancel,
  onAdded,
  onError,
}: {
  onCancel: () => void;
  onAdded: () => void;
  onError: (msg: string) => void;
}) {
  const [name, setName] = useState("");
  const [command, setCommand] = useState("");
  const [argsText, setArgsText] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (!name.trim() || !command.trim()) {
      onError("Name and command are required.");
      return;
    }
    setBusy(true);
    try {
      const args = argsText
        .split(/\s+/)
        .map((s) => s.trim())
        .filter(Boolean);
      await ipc.agents.mcpAdd(name.trim(), command.trim(), args);
      onAdded();
    } catch (e) {
      onError(String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.45)", zIndex: 80 }}
      onClick={onCancel}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: 420,
          background: "var(--color-loom-panel)",
          color: "var(--color-loom-text)",
          border: `1px solid ${surface.hairline}`,
          borderRadius: 14,
          padding: 18,
        }}
      >
        <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Add MCP server</h3>
        <div className="flex flex-col gap-2.5">
          <Field label="Name">
            <input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="filesystem"
              style={fieldStyle}
            />
          </Field>
          <Field label="Command">
            <input
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              placeholder="npx"
              style={{ ...fieldStyle, fontFamily: "var(--font-mono)" }}
            />
          </Field>
          <Field label="Arguments (space-separated)">
            <input
              value={argsText}
              onChange={(e) => setArgsText(e.target.value)}
              placeholder="-y @modelcontextprotocol/server-filesystem ."
              style={{ ...fieldStyle, fontFamily: "var(--font-mono)" }}
            />
          </Field>
        </div>
        <div className="flex justify-end gap-2" style={{ marginTop: 12 }}>
          <button
            onClick={onCancel}
            style={{
              padding: "6px 14px",
              fontSize: 12,
              borderRadius: 8,
              background: "rgba(255,255,255,0.06)",
              border: `1px solid ${surface.hairline}`,
              color: text.primary,
            }}
          >
            Cancel
          </button>
          <button
            onClick={submit}
            disabled={busy}
            style={{
              padding: "6px 14px",
              fontSize: 12,
              fontWeight: 600,
              borderRadius: 8,
              background: "var(--color-loom-accent)",
              color: "white",
              border: 0,
              opacity: busy ? 0.5 : 1,
            }}
          >
            {busy ? "Adding…" : "Add"}
          </button>
        </div>
      </div>
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

const STALE_OPTIONS: { secs: number; label: string }[] = [
  { secs: 30 * 60, label: "30 minutes" },
  { secs: 60 * 60, label: "1 hour" },
  { secs: 4 * 60 * 60, label: "4 hours" },
  { secs: 12 * 60 * 60, label: "12 hours" },
  { secs: 24 * 60 * 60, label: "24 hours" },
  { secs: 0, label: "Never" },
];

function TasksPanel() {
  const initial = Number(localStorage.getItem("loom.tasks.staleSecs") ?? "3600") || 3600;
  const [staleSecs, setStaleSecs] = useState<number>(initial);

  useEffect(() => {
    const effective = staleSecs > 0 ? staleSecs : 365 * 24 * 60 * 60;
    ipc.liveTasks.setStaleness(effective).catch(() => {});
    localStorage.setItem("loom.tasks.staleSecs", String(staleSecs));
  }, [staleSecs]);

  return (
    <div>
      <H2>Tasks</H2>
      <Hint>
        Hide live agent sessions whose task files haven't moved in this much time. Mirrors
        macOS Settings → Tasks.
      </Hint>
      <label style={{ fontSize: 11, color: text.muted, display: "block", marginBottom: 6 }}>
        Stale window
      </label>
      <div className="flex flex-wrap gap-1.5">
        {STALE_OPTIONS.map((opt) => (
          <button
            key={opt.secs}
            onClick={() => setStaleSecs(opt.secs)}
            style={{
              padding: "5px 12px",
              fontSize: 11,
              borderRadius: 999,
              border: `1px solid ${
                staleSecs === opt.secs ? "var(--color-loom-accent)" : surface.hairline
              }`,
              background:
                staleSecs === opt.secs
                  ? "color-mix(in srgb, var(--color-loom-accent) 14%, transparent)"
                  : "transparent",
              color: staleSecs === opt.secs ? text.primary : text.muted,
            }}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function AdvancedPanel() {
  const [confirming, setConfirming] = useState(false);

  const resetAll = async () => {
    if (!confirming) {
      setConfirming(true);
      setTimeout(() => setConfirming(false), 3500);
      return;
    }
    const keysToKeep = ["loom.theme"];
    const all = Object.keys(localStorage);
    for (const k of all) {
      if (!keysToKeep.includes(k)) localStorage.removeItem(k);
    }
    location.reload();
  };

  const revealData = async () => {
    await ipc.shell.open("app-data").catch(() => {});
  };

  return (
    <div className="flex flex-col gap-4">
      <section>
        <H2>Advanced</H2>
        <Hint>
          Data lives in <code style={{ fontFamily: "var(--font-mono)" }}>%APPDATA%\com.chasesims.Loom\loom.db</code> (SQLite) and Windows
          Credential Manager (API keys). Logs in <code style={{ fontFamily: "var(--font-mono)" }}>%APPDATA%\com.chasesims.Loom\logs\</code>.
        </Hint>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={revealData}
            style={{
              background: "transparent",
              color: text.primary,
              border: `1px solid ${surface.hairline}`,
              borderRadius: 8,
              padding: "6px 14px",
              fontSize: 12,
              fontWeight: 500,
            }}
          >
            Reveal data folder
          </button>
          <button
            onClick={resetAll}
            style={{
              background: confirming ? "var(--color-ws-orange)" : "transparent",
              color: confirming ? "#fff" : text.muted,
              border: `1px solid ${confirming ? "var(--color-ws-orange)" : surface.hairline}`,
              borderRadius: 8,
              padding: "6px 14px",
              fontSize: 12,
              fontWeight: 500,
            }}
          >
            {confirming ? "Click again to confirm: clears local UI state" : "Reset local UI state"}
          </button>
        </div>
      </section>
      <section>
        <H2>Logs</H2>
        <Hint>
          Tracing output and crash dumps. Click to open the most recent log line-by-line.
        </Hint>
        <LogViewer />
      </section>
    </div>
  );
}

function LogViewer() {
  const [open, setOpen] = useState(false);
  const [body, setBody] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    setError(null);
    try {
      const { readDir, readTextFile, BaseDirectory } = await import(
        "@tauri-apps/plugin-fs"
      );
      const entries = await readDir("logs", { baseDir: BaseDirectory.AppData });
      const candidates = entries
        .filter((e) => e.name && /\.log$/.test(e.name))
        .sort((a, b) => (b.name ?? "").localeCompare(a.name ?? ""));
      if (candidates.length === 0) {
        setBody("(no log files yet)");
        return;
      }
      const target = candidates[0].name as string;
      const text = await readTextFile(`logs/${target}`, {
        baseDir: BaseDirectory.AppData,
      });
      const tail = text.split(/\r?\n/).slice(-400).join("\n");
      setBody(`${target}\n\n${tail}`);
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <>
      <button
        onClick={() => {
          setOpen(true);
          load();
        }}
        style={{
          background: "transparent",
          color: text.primary,
          border: `1px solid ${surface.hairline}`,
          borderRadius: 8,
          padding: "6px 14px",
          fontSize: 12,
          fontWeight: 500,
        }}
      >
        Open log viewer
      </button>
      {open && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 flex items-center justify-center"
          style={{ background: "rgba(0,0,0,0.55)", zIndex: 80 }}
          onClick={() => setOpen(false)}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              width: 640,
              maxHeight: "80vh",
              display: "flex",
              flexDirection: "column",
              background: "var(--color-loom-panel)",
              color: "var(--color-loom-text)",
              border: `1px solid ${surface.hairline}`,
              borderRadius: 14,
              padding: 18,
            }}
          >
            <header className="flex items-center gap-2" style={{ marginBottom: 8 }}>
              <h3 style={{ fontSize: 14, fontWeight: 600 }}>Loom logs</h3>
              <button
                onClick={load}
                style={{
                  marginLeft: "auto",
                  padding: 4,
                  borderRadius: 6,
                  color: text.muted,
                }}
                aria-label="Reload"
              >
                <Icons.refresh size={12} strokeWidth={2} />
              </button>
              <button
                onClick={() => setOpen(false)}
                style={{
                  padding: 4,
                  borderRadius: 6,
                  color: text.muted,
                }}
                aria-label="Close"
              >
                <Icons.close size={13} strokeWidth={2.2} />
              </button>
            </header>
            <pre
              className="scrollbar-thin"
              style={{
                flex: 1,
                overflow: "auto",
                fontSize: 11,
                fontFamily: "var(--font-mono)",
                color: "rgba(255,255,255,0.85)",
                background: "rgba(0,0,0,0.32)",
                border: "1px solid rgba(255,255,255,0.06)",
                borderRadius: 8,
                padding: "8px 10px",
                whiteSpace: "pre-wrap",
              }}
            >
              {error
                ? `Could not read log directory: ${error}`
                : body ?? "Loading…"}
            </pre>
          </div>
        </div>
      )}
    </>
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
