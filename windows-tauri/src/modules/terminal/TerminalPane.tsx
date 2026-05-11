import { useEffect, useRef, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";
import { ipc, on, type Workspace } from "../../lib/ipc";
import { Plus, X } from "lucide-react";

type Session = {
  id: string;
  term: Terminal;
  fit: FitAddon;
  unlistenData?: () => void;
  unlistenExit?: () => void;
};

export function TerminalPane({ workspace }: { workspace: Workspace }) {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const hostsRef = useRef<Map<string, HTMLDivElement>>(new Map());

  useEffect(() => {
    spawn();
    return () => {
      sessions.forEach((s) => {
        s.unlistenData?.();
        s.unlistenExit?.();
        ipc.terminal.kill(s.id).catch(() => {});
        s.term.dispose();
      });
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.id]);

  const spawn = async () => {
    const term = new Terminal({
      fontFamily: 'ui-monospace, "Cascadia Code", Menlo, monospace',
      fontSize: 13,
      cursorBlink: true,
      theme: {
        background: "#1a1a1a",
        foreground: "#e0e0e0",
        cursor: "#4a90ff",
        selectionBackground: "rgba(74,144,255,0.3)",
      },
      allowProposedApi: true,
      scrollback: 5000,
      convertEol: true,
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.loadAddon(new WebLinksAddon());

    let id: string;
    try {
      id = await ipc.terminal.spawn({
        workspaceId: workspace.id,
        cwd: workspace.folderPath || undefined,
        cols: term.cols || 80,
        rows: term.rows || 24,
      });
    } catch (e) {
      console.error(e);
      term.write(`\r\n\x1b[31mFailed to spawn shell: ${String(e)}\x1b[0m\r\n`);
      return;
    }

    const enc = new TextEncoder();
    term.onData((data) => {
      ipc.terminal.write(id, Array.from(enc.encode(data))).catch(() => {});
    });
    term.onResize(({ cols, rows }) => {
      ipc.terminal.resize(id, cols, rows).catch(() => {});
    });

    const unlistenData = await on<number[]>(`terminal://${id}/data`, (bytes) => {
      try {
        term.write(new Uint8Array(bytes));
      } catch {}
    });
    const unlistenExit = await on<number>(`terminal://${id}/exit`, () => {
      term.write("\r\n\x1b[33m[process exited]\x1b[0m\r\n");
    });

    setSessions((prev) => [
      ...prev,
      { id, term, fit, unlistenData, unlistenExit },
    ]);
    setActiveId(id);
  };

  const closeSession = async (id: string) => {
    const s = sessions.find((x) => x.id === id);
    if (!s) return;
    s.unlistenData?.();
    s.unlistenExit?.();
    await ipc.terminal.kill(id).catch(() => {});
    s.term.dispose();
    setSessions((prev) => {
      const next = prev.filter((x) => x.id !== id);
      if (activeId === id) {
        setActiveId(next[0]?.id ?? null);
      }
      return next;
    });
  };

  useEffect(() => {
    sessions.forEach((s) => {
      const host = hostsRef.current.get(s.id);
      if (host && !host.contains(s.term.element ?? null)) {
        s.term.open(host);
        s.fit.fit();
      } else if (s.id === activeId) {
        try {
          s.fit.fit();
        } catch {}
      }
    });
  }, [sessions, activeId]);

  useEffect(() => {
    const onResize = () => {
      const s = sessions.find((x) => x.id === activeId);
      if (s) {
        try {
          s.fit.fit();
        } catch {}
      }
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [sessions, activeId]);

  return (
    <div className="flex h-full flex-col bg-loom-bg">
      <div className="flex items-center border-b border-loom-border bg-loom-panel">
        <div className="scrollbar-thin flex-1 overflow-x-auto">
          <div className="flex">
            {sessions.map((s, i) => (
              <button
                key={s.id}
                onClick={() => setActiveId(s.id)}
                className={`group flex items-center gap-1.5 border-r border-loom-border px-3 py-1.5 text-xs ${
                  activeId === s.id
                    ? "bg-loom-bg text-loom-text"
                    : "text-loom-text-dim hover:bg-loom-panel-elev"
                }`}
              >
                <span>Terminal {i + 1}</span>
                <span
                  className="invisible rounded p-0.5 text-loom-text-mute hover:bg-loom-border hover:text-loom-text group-hover:visible"
                  onClick={(e) => {
                    e.stopPropagation();
                    closeSession(s.id);
                  }}
                >
                  <X className="h-3 w-3" />
                </span>
              </button>
            ))}
          </div>
        </div>
        <button
          onClick={spawn}
          className="px-3 py-1.5 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text"
          aria-label="New terminal"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="relative flex-1 min-h-0">
        {sessions.map((s) => (
          <div
            key={s.id}
            ref={(el) => {
              if (el) hostsRef.current.set(s.id, el);
              else hostsRef.current.delete(s.id);
            }}
            className="absolute inset-0"
            style={{ display: s.id === activeId ? "block" : "none" }}
          />
        ))}
      </div>
    </div>
  );
}
