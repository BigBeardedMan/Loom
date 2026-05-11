import { useEffect, useRef, useState } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, on, type Workspace } from "../../lib/ipc";

type Vendor = "claude" | "codex" | "gemini" | "ollama" | "anthropic";

type Turn = {
  id: string;
  role: "user" | "assistant" | "system";
  text: string;
  streaming?: boolean;
  vendor?: Vendor;
};

const VENDORS: { value: Vendor; label: string }[] = [
  { value: "claude", label: "Claude CLI" },
  { value: "codex", label: "Codex" },
  { value: "gemini", label: "Gemini" },
  { value: "ollama", label: "Ollama" },
  { value: "anthropic", label: "Anthropic API" },
];

type Props = { workspace: Workspace; blockId?: string };

// Mirrors Loom/Agents/AgentPaneView.swift.
// Vendor picker, model field, transcript, input bar. Block title bar lives in BlockTitleBar.
export function AgentPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [vendor, setVendor] = useState<Vendor>(
    () => (localStorage.getItem(`loom.agent.vendor.${workspace.id}`) as Vendor) || "claude"
  );
  const [model, setModel] = useState(
    () =>
      localStorage.getItem(`loom.agent.model.${workspace.id}`) ||
      "claude-sonnet-4-6"
  );
  const [turns, setTurns] = useState<Turn[]>([]);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const cleanupRef = useRef<(() => void) | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    localStorage.setItem(`loom.agent.vendor.${workspace.id}`, vendor);
  }, [vendor, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.agent.model.${workspace.id}`, model);
  }, [model, workspace.id]);

  useEffect(() => {
    if (!blockId) return;
    setBlockStatus(blockId, busy ? "active" : "idle");
  }, [busy, blockId, setBlockStatus]);

  useEffect(() => () => cleanupRef.current?.(), []);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 99999, behavior: "smooth" });
  }, [turns]);

  const submit = async () => {
    const prompt = draft.trim();
    if (!prompt || busy) return;
    setDraft("");
    const userTurn: Turn = { id: crypto.randomUUID(), role: "user", text: prompt };
    const asstId = crypto.randomUUID();
    const asstTurn: Turn = {
      id: asstId,
      role: "assistant",
      text: "",
      streaming: true,
      vendor,
    };
    setTurns((prev) => [...prev, userTurn, asstTurn]);
    setBusy(true);

    try {
      if (vendor === "anthropic") await runAnthropic(prompt, asstId);
      else await runCli(prompt, asstId);
    } catch (e) {
      setTurns((prev) =>
        prev.map((t) =>
          t.id === asstId
            ? { ...t, text: `${t.text}\n[error] ${String(e)}`, streaming: false }
            : t
        )
      );
      setBusy(false);
    }
  };

  const runCli = async (prompt: string, asstId: string) => {
    const streamId = await ipc.agents.cliSend({
      vendor: vendor as Exclude<Vendor, "anthropic">,
      prompt,
      cwd: workspace.folderPath || ".",
    });
    const off1 = await on<string>(`agent://${streamId}/chunk`, (line) => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, text: t.text + line + "\n" } : t))
      );
    });
    const off2 = await on<number>(`agent://${streamId}/done`, () => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, streaming: false } : t))
      );
      setBusy(false);
      off1();
      off2();
      cleanupRef.current = null;
    });
    cleanupRef.current = () => {
      off1();
      off2();
    };
  };

  const runAnthropic = async (prompt: string, asstId: string) => {
    const apiKey = await ipc.keychain.get("loom.anthropic", "default");
    if (!apiKey) throw new Error("Anthropic API key not set. Open Settings to add one.");
    const messages = [{ role: "user", content: prompt }];
    const streamId = await ipc.agents.httpSend({
      apiKey,
      model,
      messages,
      maxTokens: 4096,
    });
    const off1 = await on<{ kind: string; data: unknown }>(
      `agent://${streamId}/event`,
      (ev) => {
        if (ev.kind === "content_block_delta") {
          const t = (ev.data as { delta?: { text?: string } }).delta?.text || "";
          if (t)
            setTurns((prev) =>
              prev.map((x) => (x.id === asstId ? { ...x, text: x.text + t } : x))
            );
        }
      }
    );
    const off2 = await on<number>(`agent://${streamId}/done`, () => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, streaming: false } : t))
      );
      setBusy(false);
      off1();
      off2();
      cleanupRef.current = null;
    });
    cleanupRef.current = () => {
      off1();
      off2();
    };
  };

  const cancel = () => {
    cleanupRef.current?.();
    cleanupRef.current = null;
    setTurns((prev) => prev.map((t) => (t.streaming ? { ...t, streaming: false } : t)));
    setBusy(false);
  };

  return (
    <div className="flex h-full flex-col" style={{ background: "#04050A" }}>
      <div
        className="flex items-center gap-2 flex-none"
        style={{
          padding: "6px 12px",
          background: "rgba(0, 0, 0, 0.25)",
          borderBottom: "1px solid rgba(255, 255, 255, 0.10)",
        }}
      >
        <select
          value={vendor}
          onChange={(e) => setVendor(e.target.value as Vendor)}
          className="focus:outline-none"
          style={{
            background: "rgba(255, 255, 255, 0.06)",
            border: "1px solid rgba(255, 255, 255, 0.10)",
            borderRadius: 4,
            padding: "3px 8px",
            fontSize: 11,
            color: "rgba(255, 255, 255, 0.9)",
          }}
        >
          {VENDORS.map((v) => (
            <option key={v.value} value={v.value}>
              {v.label}
            </option>
          ))}
        </select>
        {vendor === "anthropic" && (
          <input
            value={model}
            onChange={(e) => setModel(e.target.value)}
            placeholder="model"
            className="focus:outline-none"
            style={{
              background: "rgba(255, 255, 255, 0.06)",
              border: "1px solid rgba(255, 255, 255, 0.10)",
              borderRadius: 4,
              padding: "3px 8px",
              fontSize: 11,
              width: 160,
              color: "rgba(255, 255, 255, 0.9)",
              fontFamily: "var(--font-mono)",
            }}
          />
        )}
      </div>

      <div
        ref={scrollRef}
        className="scrollbar-thin flex-1 overflow-y-auto"
        style={{ padding: "12px 16px" }}
      >
        {turns.length === 0 && (
          <div
            className="flex h-full items-center justify-center"
            style={{ color: "rgba(255, 255, 255, 0.35)", fontSize: 12 }}
          >
            Ask the agent anything about this workspace.
          </div>
        )}
        {turns.map((t, i) => (
          <div
            key={t.id}
            className="flex flex-col gap-1"
            style={{
              marginBottom: 14,
              background:
                t.role === "user" ? "rgba(255, 255, 255, 0.04)" : "transparent",
              borderRadius: 8,
              padding: t.role === "user" ? "8px 10px" : 0,
            }}
          >
            <span
              className="uppercase"
              style={{
                fontSize: 10,
                fontWeight: 600,
                letterSpacing: 0.6,
                color: "rgba(255, 255, 255, 0.45)",
              }}
            >
              {t.role === "user" ? "You" : t.vendor ?? "Agent"}
              {t.streaming && (
                <Icons.spinner
                  size={10}
                  strokeWidth={2}
                  className="ml-1 inline-block animate-spin"
                  style={{ verticalAlign: -1 }}
                />
              )}
            </span>
            <pre
              className="whitespace-pre-wrap break-words"
              style={{
                fontSize: 13,
                fontFamily: t.role === "user" ? "var(--font-sans)" : "var(--font-mono)",
                color: "rgba(255, 255, 255, 0.92)",
                lineHeight: 1.5,
                margin: 0,
              }}
            >
              {t.text}
            </pre>
            {i < turns.length - 1 && i % 2 === 1 && (
              <hr
                style={{
                  border: "none",
                  borderTop: "1px solid rgba(255, 255, 255, 0.06)",
                  margin: "8px 0 0",
                }}
              />
            )}
          </div>
        ))}
      </div>

      <div
        className="flex items-end gap-2 flex-none"
        style={{
          padding: 10,
          background: "rgba(0, 0, 0, 0.24)",
          borderTop: "1px solid rgba(255, 255, 255, 0.10)",
        }}
      >
        <textarea
          rows={2}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              submit();
            }
          }}
          placeholder="Message the agent…"
          className="scrollbar-thin flex-1 resize-none focus:outline-none"
          style={{
            background: "rgba(255, 255, 255, 0.06)",
            border: "1px solid rgba(255, 255, 255, 0.10)",
            borderRadius: 8,
            padding: "8px 10px",
            fontSize: 13,
            fontFamily: "var(--font-mono)",
            color: "rgba(255, 255, 255, 0.92)",
            minHeight: 38,
          }}
        />
        {busy ? (
          <button
            onClick={cancel}
            aria-label="Cancel"
            style={{
              background: "rgba(242, 70, 32, 0.85)",
              color: "white",
              borderRadius: 999,
              padding: 8,
              border: "none",
            }}
          >
            <Icons.cancel size={14} strokeWidth={2.4} fill="currentColor" />
          </button>
        ) : (
          <button
            onClick={submit}
            disabled={!draft.trim()}
            aria-label="Send"
            style={{
              background: draft.trim()
                ? "var(--color-loom-accent)"
                : "rgba(255, 255, 255, 0.10)",
              color: "white",
              borderRadius: 999,
              padding: 8,
              border: "none",
              opacity: draft.trim() ? 1 : 0.5,
            }}
          >
            <Icons.send size={14} strokeWidth={2.2} />
          </button>
        )}
      </div>
    </div>
  );
}
