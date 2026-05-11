import { useState } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc } from "../../lib/ipc";

const ONBOARDED_KEY = "loom.onboarded";

export function shouldShowOnboarding(workspaceCount: number): boolean {
  if (workspaceCount > 0) return false;
  return localStorage.getItem(ONBOARDED_KEY) !== "1";
}

export function markOnboarded() {
  localStorage.setItem(ONBOARDED_KEY, "1");
}

type Props = { onDone: () => void };

export function OnboardingModal({ onDone }: Props) {
  const createWorkspace = useApp((s) => s.createWorkspace);
  const openSettings = useApp((s) => s.openSettings);
  const [step, setStep] = useState<"welcome" | "workspace" | "extras">("welcome");
  const [name, setName] = useState("My Project");
  const [folder, setFolder] = useState("");
  const [installingShell, setInstallingShell] = useState(false);
  const [shellInstalled, setShellInstalled] = useState(false);
  const [busy, setBusy] = useState(false);

  const pickFolder = async () => {
    const f = await ipc.fs.pickFolder();
    if (f) setFolder(f as unknown as string);
  };

  const installShell = async () => {
    setInstallingShell(true);
    try {
      await ipc.shell.installIntegration();
      setShellInstalled(true);
    } catch {
      // Non-fatal: user can do it later from Settings.
    } finally {
      setInstallingShell(false);
    }
  };

  const finish = async () => {
    setBusy(true);
    try {
      if (name.trim() && folder.trim()) {
        await createWorkspace(name.trim(), folder.trim(), "blue", "code");
      }
      markOnboarded();
      onDone();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.55)", zIndex: 90 }}
    >
      <div
        style={{
          width: 480,
          background: "var(--color-loom-panel)",
          color: "var(--color-loom-text)",
          border: "1px solid var(--color-loom-hairline)",
          borderRadius: 14,
          padding: 22,
          boxShadow: "0 24px 50px rgba(0,0,0,0.45)",
        }}
      >
        <header className="flex items-center gap-2" style={{ marginBottom: 6 }}>
          <span
            style={{
              width: 22,
              height: 22,
              borderRadius: 6,
              background: "var(--color-loom-accent)",
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
              color: "white",
            }}
          >
            <Icons.sparkles size={12} strokeWidth={2.2} />
          </span>
          <h2 style={{ fontSize: 16, fontWeight: 600 }}>Welcome to Loom</h2>
        </header>
        {step === "welcome" && (
          <>
            <p style={{ fontSize: 13, color: "rgba(255,255,255,0.65)", marginBottom: 14 }}>
              Loom is your developer cockpit: terminal, editor, kanban, agents, notes, and preview
              side-by-side in one workspace. Each workspace points at a folder on disk.
            </p>
            <ul
              style={{
                fontSize: 12,
                color: "rgba(255,255,255,0.55)",
                paddingLeft: 16,
                listStyle: "disc",
                marginBottom: 16,
                lineHeight: 1.6,
              }}
            >
              <li>Add blocks via Ctrl+Shift+1..7 or the topbar + buttons.</li>
              <li>The agent pane talks to Claude, Codex, Gemini, Ollama, or any OpenAI-compat endpoint.</li>
              <li>Open Settings (Ctrl+K → "Open Settings") for API keys, providers, and shell integration.</li>
            </ul>
            <footer className="flex justify-end gap-2">
              <button
                onClick={() => {
                  markOnboarded();
                  onDone();
                }}
                style={btnStyle("ghost")}
              >
                Skip
              </button>
              <button onClick={() => setStep("workspace")} style={btnStyle("primary")}>
                Get started
              </button>
            </footer>
          </>
        )}
        {step === "workspace" && (
          <>
            <p style={{ fontSize: 13, color: "rgba(255,255,255,0.65)", marginBottom: 12 }}>
              Pick the first folder you want to work in. Loom drops a workspace pointing at it; the
              terminal block opens with that folder as cwd, the editor opens files from it, etc.
            </p>
            <label style={lblStyle}>Workspace name</label>
            <input
              autoFocus
              value={name}
              onChange={(e) => setName(e.target.value)}
              style={inputStyle}
              placeholder="My Project"
            />
            <label style={lblStyle}>Folder</label>
            <div className="flex gap-2">
              <input
                value={folder}
                readOnly
                placeholder="Click pick folder…"
                style={{ ...inputStyle, flex: 1, fontFamily: "var(--font-mono)" }}
              />
              <button onClick={pickFolder} style={btnStyle("ghost")}>
                Pick folder
              </button>
            </div>
            <footer className="flex justify-end gap-2" style={{ marginTop: 14 }}>
              <button onClick={() => setStep("welcome")} style={btnStyle("ghost")}>
                Back
              </button>
              <button
                onClick={() => setStep("extras")}
                disabled={!name.trim() || !folder}
                style={{ ...btnStyle("primary"), opacity: name.trim() && folder ? 1 : 0.5 }}
              >
                Next
              </button>
            </footer>
          </>
        )}
        {step === "extras" && (
          <>
            <p style={{ fontSize: 13, color: "rgba(255,255,255,0.65)", marginBottom: 12 }}>
              Two optional one-time steps. Skip if you'd rather do them later from Settings.
            </p>
            <div
              className="flex items-start gap-2"
              style={{
                padding: "10px 12px",
                background: "rgba(255,255,255,0.04)",
                border: "1px solid rgba(255,255,255,0.06)",
                borderRadius: 8,
                marginBottom: 8,
              }}
            >
              <div className="flex-1">
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 2 }}>
                  Shell integration
                </div>
                <div style={{ fontSize: 11, color: "rgba(255,255,255,0.55)" }}>
                  Logs every command run in Loom terminals so the Commands pane has data.
                </div>
              </div>
              <button
                onClick={installShell}
                disabled={installingShell || shellInstalled}
                style={btnStyle("ghost")}
              >
                {shellInstalled ? "Installed" : installingShell ? "Installing…" : "Install"}
              </button>
            </div>
            <div
              className="flex items-start gap-2"
              style={{
                padding: "10px 12px",
                background: "rgba(255,255,255,0.04)",
                border: "1px solid rgba(255,255,255,0.06)",
                borderRadius: 8,
                marginBottom: 14,
              }}
            >
              <div className="flex-1">
                <div style={{ fontSize: 13, fontWeight: 600, marginBottom: 2 }}>
                  AI providers
                </div>
                <div style={{ fontSize: 11, color: "rgba(255,255,255,0.55)" }}>
                  Anthropic API key + local endpoints (Ollama, OpenAI-compat). Settings → AI
                  Providers.
                </div>
              </div>
              <button
                onClick={() => {
                  openSettings();
                }}
                style={btnStyle("ghost")}
              >
                Open Settings
              </button>
            </div>
            <footer className="flex justify-end gap-2">
              <button onClick={() => setStep("workspace")} style={btnStyle("ghost")}>
                Back
              </button>
              <button
                onClick={finish}
                disabled={busy}
                style={{ ...btnStyle("primary"), opacity: busy ? 0.5 : 1 }}
              >
                {busy ? "Creating…" : "Create workspace"}
              </button>
            </footer>
          </>
        )}
      </div>
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: "100%",
  background: "var(--color-loom-bg-from)",
  border: "1px solid var(--color-loom-hairline)",
  borderRadius: 6,
  padding: "6px 10px",
  fontSize: 13,
  color: "var(--color-loom-text)",
  outline: "none",
  marginBottom: 10,
};

const lblStyle: React.CSSProperties = {
  display: "block",
  fontSize: 11,
  fontWeight: 500,
  color: "rgba(255,255,255,0.55)",
  marginBottom: 4,
};

function btnStyle(kind: "primary" | "ghost"): React.CSSProperties {
  if (kind === "primary") {
    return {
      padding: "6px 14px",
      fontSize: 12,
      fontWeight: 600,
      borderRadius: 8,
      background: "var(--color-loom-accent)",
      color: "white",
      border: 0,
    };
  }
  return {
    padding: "6px 14px",
    fontSize: 12,
    fontWeight: 500,
    borderRadius: 8,
    background: "rgba(255,255,255,0.06)",
    border: "1px solid var(--color-loom-hairline)",
    color: "var(--color-loom-text)",
  };
}
