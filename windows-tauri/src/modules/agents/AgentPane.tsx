import { useEffect, useRef, useState } from "react";
import { Send, Square, Sparkles } from "lucide-react";
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

export function AgentPane({ workspace }: { workspace: Workspace }) {
  const [vendor, setVendor] = useState<Vendor>("claude");
  const [model, setModel] = useState<string>("claude-sonnet-4-6");
  const [turns, setTurns] = useState<Turn[]>([]);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const cleanupRef = useRef<(() => void) | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    return () => {
      cleanupRef.current?.();
    };
  }, []);

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
      if (vendor === "anthropic") {
        await runAnthropic(prompt, asstId);
      } else {
        await runCli(prompt, asstId);
      }
    } catch (e) {
      setTurns((prev) =>
        prev.map((t) =>
          t.id === asstId ? { ...t, text: `${t.text}\n[error] ${String(e)}`, streaming: false } : t
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
    if (!apiKey) {
      throw new Error("Anthropic API key not set. Add it in Settings.");
    }
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
          const text = ((ev.data as { delta?: { text?: string } }).delta?.text) || "";
          if (text) {
            setTurns((prev) =>
              prev.map((t) =>
                t.id === asstId ? { ...t, text: t.text + text } : t
              )
            );
          }
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
    setTurns((prev) =>
      prev.map((t) => (t.streaming ? { ...t, streaming: false } : t))
    );
    setBusy(false);
  };

  return (
    <div className="flex h-full flex-col bg-loom-bg">
      <div className="flex items-center justify-between border-b border-loom-border bg-loom-panel px-3 py-1.5 text-xs">
        <div className="flex items-center gap-1.5">
          <Sparkles className="h-3.5 w-3.5 text-loom-accent" />
          <span className="font-medium uppercase tracking-wider text-loom-text-mute">
            Agent
          </span>
        </div>
        <div className="flex items-center gap-1">
          <select
            value={vendor}
            onChange={(e) => setVendor(e.target.value as Vendor)}
            className="rounded border border-loom-border bg-loom-bg px-1.5 py-0.5 text-xs text-loom-text focus:border-loom-accent focus:outline-none"
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
              className="w-32 rounded border border-loom-border bg-loom-bg px-1.5 py-0.5 text-xs text-loom-text focus:border-loom-accent focus:outline-none"
            />
          )}
        </div>
      </div>

      <div
        ref={scrollRef}
        className="scrollbar-thin flex-1 overflow-y-auto px-3 py-2"
      >
        {turns.length === 0 && (
          <div className="flex h-full items-center justify-center text-sm text-loom-text-mute">
            Ask the agent anything about this workspace.
          </div>
        )}
        {turns.map((t) => (
          <div key={t.id} className="mb-3 text-sm">
            <div className="mb-0.5 text-[10px] uppercase tracking-wider text-loom-text-mute">
              {t.role === "user" ? "You" : t.vendor ?? "Agent"}
              {t.streaming && " · streaming…"}
            </div>
            <pre className="whitespace-pre-wrap break-words font-mono text-xs leading-relaxed text-loom-text">
              {t.text}
            </pre>
          </div>
        ))}
      </div>

      <div className="flex items-end gap-1 border-t border-loom-border bg-loom-panel p-2">
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
          className="scrollbar-thin flex-1 resize-none rounded-md border border-loom-border bg-loom-bg px-2 py-1.5 text-sm text-loom-text outline-none focus:border-loom-accent"
        />
        {busy ? (
          <button
            onClick={cancel}
            className="rounded-md bg-red-500/80 px-2 py-1.5 text-white hover:bg-red-500"
            aria-label="Cancel"
          >
            <Square className="h-4 w-4" />
          </button>
        ) : (
          <button
            onClick={submit}
            disabled={!draft.trim()}
            className="rounded-md bg-loom-accent px-2 py-1.5 text-white hover:opacity-90 disabled:opacity-50"
            aria-label="Send"
          >
            <Send className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
}
