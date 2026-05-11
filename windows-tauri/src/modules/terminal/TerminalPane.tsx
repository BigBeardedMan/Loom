import { useEffect, useRef, useState } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";
import { ipc, on, type Workspace } from "../../lib/ipc";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { surface } from "../../lib/theme";

type Session = {
  id: string;
  term: Terminal;
  fit: FitAddon;
  title: string;
  cwd: string;
  unlistenData?: () => void;
  unlistenExit?: () => void;
};

type Props = { workspace: Workspace; blockId?: string };

const MAX_PANES = 4;

// Mirrors Loom/Terminal/TerminalPaneView.swift.
// 1 / 2-H / 2-V / 3-H / 3-V / 2x2 quad layouts. Each pane has its own
// header with cwd, OSC-0/2 title, Ctrl+C, axis-toggle, close buttons.
export function TerminalPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const layout = useApp((s) => s.layout);
  const updateBlock = useApp((s) => s.updateBlock);
  const block = layout?.blocks.find((b) => b.id === blockId);
  const targetCount = Math.max(1, Math.min(MAX_PANES, block?.terminalCount ?? 1));
  const axis: "h" | "v" = block?.terminalAxis ?? "h";

  const [sessions, setSessions] = useState<Session[]>([]);
  const [activeId, setActiveId] = useState<string | null>(null);
  const hostsRef = useRef<Map<string, HTMLDivElement>>(new Map());
  const sessionsRef = useRef<Session[]>([]);
  sessionsRef.current = sessions;

  // Reconcile session count with persisted target count.
  useEffect(() => {
    let cancelled = false;

    const reconcile = async () => {
      const current = sessionsRef.current.length;
      if (current === targetCount) return;
      if (current < targetCount) {
        for (let i = current; i < targetCount; i++) {
          if (cancelled) return;
          await spawnOne();
        }
      } else {
        const toClose = sessionsRef.current.slice(targetCount);
        for (const s of toClose) {
          if (cancelled) return;
          await closeOne(s.id, /* persist */ false);
        }
      }
    };
    reconcile();

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [targetCount, workspace.id]);

  // Cleanup on unmount.
  useEffect(() => {
    return () => {
      sessionsRef.current.forEach((s) => {
        s.unlistenData?.();
        s.unlistenExit?.();
        ipc.terminal.kill(s.id).catch(() => {});
        s.term.dispose();
      });
      if (blockId) setBlockStatus(blockId, "idle");
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.id]);

  // Foreground-command polling on active session.
  useEffect(() => {
    if (!blockId) return;
    if (!activeId) {
      setBlockStatus(blockId, "idle");
      return;
    }
    let cancelled = false;
    const tick = async () => {
      try {
        const cmd = await ipc.terminal.foregroundCommand(activeId);
        if (cancelled) return;
        setBlockStatus(blockId, cmd ? "active" : "idle");
      } catch {}
    };
    tick();
    const id = setInterval(tick, 2000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [activeId, blockId, setBlockStatus]);

  // Mount xterm into per-pane hosts and fit when sessions or layout change.
  useEffect(() => {
    sessions.forEach((s) => {
      const host = hostsRef.current.get(s.id);
      if (host && !host.contains(s.term.element ?? null)) {
        try {
          s.term.open(host);
          s.fit.fit();
        } catch {}
      }
    });
    // Re-fit on layout shape change.
    const t = setTimeout(() => {
      sessions.forEach((s) => {
        try {
          s.fit.fit();
        } catch {}
      });
    }, 30);
    return () => clearTimeout(t);
  }, [sessions, targetCount, axis]);

  // Window resize refits every pane.
  useEffect(() => {
    const onResize = () => {
      sessions.forEach((s) => {
        try {
          s.fit.fit();
        } catch {}
      });
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, [sessions]);

  const spawnOne = async () => {
    const term = new Terminal({
      fontFamily:
        '"SF Mono", "Cascadia Code", "JetBrains Mono", Menlo, monospace',
      fontSize: 13,
      cursorBlink: true,
      theme: {
        background: "#04050A",
        foreground: "#e0e0e0",
        cursor: "#2D80F5",
        selectionBackground: "rgba(45, 128, 245, 0.30)",
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
    term.onTitleChange((title) => {
      setSessions((prev) => prev.map((s) => (s.id === id ? { ...s, title } : s)));
    });

    const unlistenData = await on<number[]>(`terminal://${id}/data`, (bytes) => {
      try {
        term.write(new Uint8Array(bytes));
      } catch {}
    });
    const unlistenExit = await on<number>(`terminal://${id}/exit`, () => {
      term.write("\r\n\x1b[33m[process exited]\x1b[0m\r\n");
    });

    const next: Session = {
      id,
      term,
      fit,
      title: "",
      cwd: workspace.folderPath || "",
      unlistenData,
      unlistenExit,
    };
    setSessions((prev) => [...prev, next]);
    setActiveId((cur) => cur ?? id);
  };

  const closeOne = async (id: string, persist: boolean) => {
    const s = sessionsRef.current.find((x) => x.id === id);
    if (!s) return;
    s.unlistenData?.();
    s.unlistenExit?.();
    await ipc.terminal.kill(id).catch(() => {});
    s.term.dispose();
    setSessions((prev) => prev.filter((x) => x.id !== id));
    setActiveId((cur) => (cur === id ? null : cur));
    if (persist && blockId) {
      const remaining = sessionsRef.current.filter((x) => x.id !== id).length;
      await updateBlock(blockId, { terminalCount: Math.max(1, remaining) });
    }
  };

  const addPane = async () => {
    if (!blockId || sessions.length >= MAX_PANES) return;
    await updateBlock(blockId, { terminalCount: sessions.length + 1 });
  };

  const toggleAxis = async () => {
    if (!blockId) return;
    await updateBlock(blockId, { terminalAxis: axis === "h" ? "v" : "h" });
  };

  const sendCtrlC = (id: string) => {
    ipc.terminal.write(id, [0x03]).catch(() => {});
  };

  const gridStyle = computeGridStyle(sessions.length, axis);

  return (
    <div className="flex h-full flex-col" style={{ background: surface.terminal }}>
      <div
        className="flex items-center flex-none"
        style={{
          padding: "4px 8px",
          gap: 6,
          background: "rgba(0,0,0,0.25)",
          borderBottom: "1px solid rgba(255,255,255,0.06)",
          fontSize: 11,
          color: "rgba(255,255,255,0.55)",
        }}
      >
        <span style={{ fontWeight: 500 }}>
          {sessions.length} pane{sessions.length === 1 ? "" : "s"}
          {sessions.length >= 2 && axis === "h" && " · side-by-side"}
          {sessions.length >= 2 && axis === "v" && " · stacked"}
          {sessions.length === MAX_PANES && " · quad"}
        </span>
        <div className="ml-auto flex items-center gap-1">
          {sessions.length >= 2 && sessions.length < MAX_PANES && (
            <button
              onClick={toggleAxis}
              title="Toggle split axis"
              aria-label="Toggle split axis"
              style={{ padding: 3, color: "rgba(255,255,255,0.55)", borderRadius: 4 }}
            >
              {axis === "h" ? (
                <Icons.splitVertical size={11} strokeWidth={2} />
              ) : (
                <Icons.splitHorizontal size={11} strokeWidth={2} />
              )}
            </button>
          )}
          {sessions.length < MAX_PANES && (
            <button
              onClick={addPane}
              title="Split into another pane"
              aria-label="Add terminal pane"
              style={{ padding: 3, color: "rgba(255,255,255,0.55)", borderRadius: 4 }}
            >
              <Icons.plus size={12} strokeWidth={2.2} />
            </button>
          )}
        </div>
      </div>

      <div
        className="relative flex-1 min-h-0"
        style={{
          display: "grid",
          gap: 1,
          background: "rgba(255,255,255,0.06)",
          ...gridStyle,
        }}
      >
        {sessions.length === 0 && (
          <div
            className="flex h-full items-center justify-center"
            style={{ fontSize: 12, color: "rgba(255,255,255,0.55)" }}
          >
            Spawning shell…
          </div>
        )}
        {sessions.map((s) => (
          <PaneCell
            key={s.id}
            session={s}
            active={s.id === activeId}
            canClose={sessions.length > 1}
            onFocus={() => setActiveId(s.id)}
            onClose={() => closeOne(s.id, true)}
            onCtrlC={() => sendCtrlC(s.id)}
            hostRef={(el) => {
              if (el) hostsRef.current.set(s.id, el);
              else hostsRef.current.delete(s.id);
            }}
          />
        ))}
      </div>
    </div>
  );
}

function PaneCell({
  session,
  active,
  canClose,
  onFocus,
  onClose,
  onCtrlC,
  hostRef,
}: {
  session: Session;
  active: boolean;
  canClose: boolean;
  onFocus: () => void;
  onClose: () => void;
  onCtrlC: () => void;
  hostRef: (el: HTMLDivElement | null) => void;
}) {
  const label = session.title || displayCwd(session.cwd) || "shell";
  return (
    <div
      onClick={onFocus}
      style={{
        background: "#04050A",
        display: "flex",
        flexDirection: "column",
        minWidth: 0,
        minHeight: 0,
        outline: active ? "1px solid rgba(45,128,245,0.45)" : "none",
      }}
    >
      <div
        className="flex items-center gap-1.5 flex-none"
        style={{
          padding: "4px 8px",
          fontSize: 10,
          color: "rgba(255,255,255,0.6)",
          background: "rgba(0,0,0,0.32)",
          borderBottom: "1px solid rgba(255,255,255,0.04)",
        }}
      >
        <Icons.terminal
          size={10}
          strokeWidth={2}
          color={active ? "var(--color-ws-green)" : "rgba(255,255,255,0.5)"}
        />
        <span
          style={{
            fontFamily: "var(--font-mono)",
            overflow: "hidden",
            textOverflow: "ellipsis",
            whiteSpace: "nowrap",
            direction: "rtl",
            textAlign: "left",
            flex: 1,
          }}
          title={`${session.title ? session.title + " · " : ""}${session.cwd}`}
        >
          {label}
        </span>
        <button
          onClick={(e) => {
            e.stopPropagation();
            onCtrlC();
          }}
          title="Send Ctrl+C"
          aria-label="Send Ctrl+C"
          style={{
            padding: 2,
            color: "rgba(255,255,255,0.55)",
            borderRadius: 3,
          }}
        >
          <Icons.cancel size={9} strokeWidth={2.4} fill="currentColor" />
        </button>
        {canClose && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onClose();
            }}
            title="Close pane"
            aria-label="Close pane"
            style={{
              padding: 2,
              color: "rgba(255,255,255,0.55)",
              borderRadius: 3,
            }}
          >
            <Icons.close size={9} strokeWidth={2.5} />
          </button>
        )}
      </div>
      <div ref={hostRef} className="flex-1 min-h-0" />
    </div>
  );
}

function computeGridStyle(count: number, axis: "h" | "v"): React.CSSProperties {
  if (count <= 1) {
    return { gridTemplateColumns: "1fr", gridTemplateRows: "1fr" };
  }
  if (count === 4) {
    return { gridTemplateColumns: "1fr 1fr", gridTemplateRows: "1fr 1fr" };
  }
  // count === 2 or 3
  const tracks = `repeat(${count}, 1fr)`;
  if (axis === "h") {
    return { gridTemplateColumns: tracks, gridTemplateRows: "1fr" };
  }
  return { gridTemplateColumns: "1fr", gridTemplateRows: tracks };
}

function displayCwd(p: string): string {
  if (!p) return "";
  const parts = p.replace(/[\\/]$/, "").split(/[\\/]/);
  const tail = parts.slice(-2).join("/");
  return tail || p;
}
