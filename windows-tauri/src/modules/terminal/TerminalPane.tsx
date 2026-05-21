import { useEffect, useRef, useState, type ReactNode } from "react";
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import { WebLinksAddon } from "@xterm/addon-web-links";
import { readImage } from "@tauri-apps/plugin-clipboard-manager";
import { BaseDirectory, mkdir, writeFile } from "@tauri-apps/plugin-fs";
import { appLocalDataDir, join } from "@tauri-apps/api/path";
import { ipc, on, type CommandRecord, type TerminalTranscriptRestore, type Workspace } from "../../lib/ipc";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { surface } from "../../lib/theme";

type Session = {
  id: string;
  term: Terminal;
  fit: FitAddon;
  title: string;
  cwd: string;
  restoredTranscript?: TerminalTranscriptRestore;
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
          await spawnOne(i);
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

  const spawnOne = async (index: number) => {
    const restored =
      index === 0 && block?.restoredTranscript ? block.restoredTranscript : undefined;
    const title =
      restored?.title ||
      block?.customTitle?.trim() ||
      (index === 0 ? "Terminal" : `Terminal ${index + 1}`);
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
        sessionId: restored?.sessionId,
        workspaceId: workspace.id,
        workspaceName: workspace.name,
        title,
        cwd: restored?.cwd || workspace.folderPath || undefined,
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
      ipc.terminal.updateMetadata(id, { title }).catch(() => {});
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
      cwd: restored?.cwd || workspace.folderPath || "",
      restoredTranscript: restored,
      unlistenData,
      unlistenExit,
    };
    setSessions((prev) => [...prev, next]);
    setActiveId((cur) => cur ?? id);
    if (restored) {
      term.write(restoredTranscriptText(restored));
    }
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

  const writeTextToSession = (id: string, text: string) => {
    ipc.terminal.write(id, Array.from(new TextEncoder().encode(text))).catch(() => {});
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
            onInsertText={(text) => writeTextToSession(s.id, text)}
            workspacePath={workspace.folderPath}
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
  onInsertText,
  workspacePath,
  hostRef,
}: {
  session: Session;
  active: boolean;
  canClose: boolean;
  onFocus: () => void;
  onClose: () => void;
  onCtrlC: () => void;
  onInsertText: (text: string) => void;
  workspacePath: string;
  hostRef: (el: HTMLDivElement | null) => void;
}) {
  const hostElRef = useRef<HTMLDivElement | null>(null);
  const [showCards, setShowCards] = useState(false);
  const label = session.title || displayCwd(session.cwd) || "shell";
  const focusPane = () => {
    onFocus();
    session.term.focus();
  };
  const setHost = (el: HTMLDivElement | null) => {
    hostElRef.current = el;
    hostRef(el);
  };
  const onTerminalMouseDown = (event: React.MouseEvent<HTMLDivElement>) => {
    focusPane();
    moveCursorToClickedCell(session, hostElRef.current, event);
  };
  const insertImageArgument = async (path: string) => {
    if (!path) return;
    onInsertText(`--image ${shellSingleQuoted(path)} `);
  };
  const handlePaste = async (event: React.ClipboardEvent<HTMLDivElement>) => {
    const text = event.clipboardData.getData("text/plain");
    if (text) return;
    const file = Array.from(event.clipboardData.files).find(isImageFile);
    if (file) {
      event.preventDefault();
      const path = await imageFilePath(file);
      if (path) await insertImageArgument(path);
      return;
    }
    try {
      const image = await readImage();
      event.preventDefault();
      const path = await saveClipboardImage(image);
      if (path) await insertImageArgument(path);
    } catch {
      // No image content available through the native clipboard bridge.
    }
  };
  const handleDrop = async (event: React.DragEvent<HTMLDivElement>) => {
    const file = Array.from(event.dataTransfer.files).find(isImageFile);
    if (!file) return;
    event.preventDefault();
    const path = await imageFilePath(file);
    if (path) await insertImageArgument(path);
  };
  return (
    <div
      onClick={focusPane}
      onPaste={handlePaste}
      onDragOver={(e) => {
        if (Array.from(e.dataTransfer.items).some((item) => item.type.startsWith("image/"))) {
          e.preventDefault();
        }
      }}
      onDrop={handleDrop}
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
        <button
          onClick={(e) => {
            e.stopPropagation();
            setShowCards((v) => !v);
          }}
          title={showCards ? "Show live terminal" : "Show command cards"}
          aria-label={showCards ? "Show live terminal" : "Show command cards"}
          style={{
            padding: 2,
            color: "rgba(255,255,255,0.55)",
            borderRadius: 3,
          }}
        >
          {showCards ? (
            <Icons.terminal size={9} strokeWidth={2.3} />
          ) : (
            <Icons.listBulletRect size={9} strokeWidth={2.3} />
          )}
        </button>
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
      <div
        ref={setHost}
        className={showCards ? "hidden" : "flex-1 min-h-0"}
        onMouseDown={onTerminalMouseDown}
      />
      {showCards && (
        <InlineCardsView
          sessionId={session.id}
          workspacePath={workspacePath}
          onCaptureRerun={(command) => onInsertText(captureCommandText(command) + "\r")}
        />
      )}
    </div>
  );
}

function InlineCardsView({
  sessionId,
  workspacePath,
  onCaptureRerun,
}: {
  sessionId: string;
  workspacePath: string;
  onCaptureRerun: (command: string) => void;
}) {
  const [records, setRecords] = useState<CommandRecord[]>([]);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [output, setOutput] = useState<Record<string, string>>({});

  const load = async () => {
    const all = await ipc.commandHistory.list(workspacePath || undefined).catch(() => []);
    setRecords(all.filter((r) => r.sessionId === sessionId));
  };

  useEffect(() => {
    load();
    const id = setInterval(load, 2000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId, workspacePath]);

  const copy = async (record: CommandRecord) => {
    const mod = await import("@tauri-apps/plugin-clipboard-manager");
    await mod.writeText(record.command);
    setCopiedId(record.id);
    setTimeout(() => setCopiedId((cur) => (cur === record.id ? null : cur)), 1500);
  };

  const toggle = async (record: CommandRecord) => {
    if (expandedId === record.id) {
      setExpandedId(null);
      return;
    }
    if (record.outputPath && output[record.id] == null) {
      const body = await ipc.commandHistory.readOutput(record.outputPath).catch((e) => String(e));
      setOutput((prev) => ({ ...prev, [record.id]: body }));
    }
    setExpandedId(record.id);
  };

  if (records.length === 0) {
    return (
      <div
        className="flex flex-1 flex-col items-center justify-center"
        style={{ padding: 24, color: "rgba(255,255,255,0.45)", textAlign: "center" }}
      >
        <Icons.listBulletRect size={28} strokeWidth={1.2} />
        <div style={{ fontSize: 11, marginTop: 8, color: "rgba(255,255,255,0.65)" }}>
          No commands captured yet for this session.
        </div>
        <div style={{ fontSize: 10, marginTop: 4, maxWidth: 280 }}>
          Switch to the live terminal and run something. Cards populate after the next prompt.
        </div>
      </div>
    );
  }

  return (
    <div className="scrollbar-thin flex-1 overflow-y-auto" style={{ padding: 8 }}>
      <div className="flex flex-col gap-1.5">
        {records.map((record) => {
          const succeeded = record.exitCode === 0;
          const expanded = expandedId === record.id;
          return (
            <div
              key={record.id}
              style={{
                padding: "7px 10px",
                background: "rgba(255,255,255,0.04)",
                border: "1px solid rgba(255,255,255,0.10)",
                borderRadius: 6,
              }}
            >
              <div className="flex items-start gap-1.5">
                <span
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
                  }}
                >
                  {record.command}
                </span>
                <IconButton title="Copy command" onClick={() => copy(record)}>
                  {copiedId === record.id ? (
                    <Icons.check size={10} strokeWidth={2.4} />
                  ) : (
                    <Icons.copy size={10} strokeWidth={2} />
                  )}
                </IconButton>
                <IconButton title="Rerun in active terminal" onClick={() => onCaptureRerun(record.command)}>
                  <Icons.rerunReverse size={10} strokeWidth={2} />
                </IconButton>
                {record.outputPath && (
                  <IconButton title={expanded ? "Hide output" : "Show captured output"} onClick={() => toggle(record)}>
                    {expanded ? (
                      <Icons.chevronUp size={10} strokeWidth={2} />
                    ) : (
                      <Icons.chevronDown size={10} strokeWidth={2} />
                    )}
                  </IconButton>
                )}
              </div>
              <div
                className="flex items-center gap-1.5"
                style={{ marginTop: 3, fontSize: 10, color: "rgba(255,255,255,0.45)" }}
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
                {!succeeded && (
                  <>
                    <span style={{ color: "rgba(255,255,255,0.25)" }}>·</span>
                    <span style={{ color: "rgb(242,99,46)", fontWeight: 650 }}>exit {record.exitCode}</span>
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
                    background: "rgba(0,0,0,0.30)",
                    border: "1px solid rgba(255,255,255,0.08)",
                    borderRadius: 4,
                    fontSize: 11,
                    color: "rgba(255,255,255,0.85)",
                    fontFamily: "var(--font-mono)",
                  }}
                >
                  {output[record.id] || "(empty)"}
                </pre>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function IconButton({
  title,
  onClick,
  children,
}: {
  title: string;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      aria-label={title}
      title={title}
      style={{ padding: 3, color: "rgba(255,255,255,0.55)", borderRadius: 4 }}
    >
      {children}
    </button>
  );
}

function restoredTranscriptText(restore: TerminalTranscriptRestore): string {
  const title = restore.title.trim() || "Terminal Session";
  const header = `\x1b[2m--- Restored ${title} from Recently Closed ---\x1b[0m\r\n`;
  const trimNotice = restore.wasTruncated
    ? `\x1b[2m--- Imported latest ${fmtBytes(restore.importedByteLimit)} of ${fmtBytes(
        restore.transcriptByteCount
      )}. Open transcript preview for the saved file. ---\x1b[0m\r\n`
    : "";
  const body = (restore.transcriptText || "(empty transcript)")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n")
    .join("\r\n");
  const footer = "\r\n\x1b[2m--- Fresh shell starts below. Reconnect or relaunch commands when ready. ---\x1b[0m\r\n";
  return header + trimNotice + body + footer;
}

function captureCommandText(command: string): string {
  return `Invoke-LoomCapture -Command ${shellSingleQuoted(command)}`;
}

function shellSingleQuoted(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

function isImageFile(file: File): boolean {
  if (file.type.startsWith("image/")) return true;
  return /\.(avif|bmp|gif|heic|heif|ico|jpe?g|jp2|png|psd|svg|tiff?|webp)$/i.test(file.name);
}

async function imageFilePath(file: File): Promise<string | null> {
  const path = (file as File & { path?: string }).path;
  if (path) return path;
  const bytes = new Uint8Array(await file.arrayBuffer());
  const ext = imageExtension(file);
  return saveClipboardBytes(bytes, ext);
}

function imageExtension(file: File): string {
  const fromName = file.name.match(/\.([A-Za-z0-9]+)$/)?.[1];
  if (fromName) return fromName.toLowerCase();
  if (file.type === "image/jpeg") return "jpg";
  if (file.type === "image/svg+xml") return "svg";
  if (file.type === "image/webp") return "webp";
  return "png";
}

async function saveClipboardImage(image: Awaited<ReturnType<typeof readImage>>): Promise<string | null> {
  const size = await image.size();
  const rgba = await image.rgba();
  const png = await rgbaToPng(rgba, size.width, size.height);
  return saveClipboardBytes(png, "png");
}

async function rgbaToPng(rgba: Uint8Array, width: number, height: number): Promise<Uint8Array> {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas context unavailable");
  ctx.putImageData(new ImageData(new Uint8ClampedArray(rgba), width, height), 0, 0);
  const blob = await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob((value) => (value ? resolve(value) : reject(new Error("PNG encode failed"))), "image/png")
  );
  return new Uint8Array(await blob.arrayBuffer());
}

async function saveClipboardBytes(bytes: Uint8Array, ext: string): Promise<string | null> {
  const dir = "Clipboard Images";
  await mkdir(dir, { baseDir: BaseDirectory.AppLocalData, recursive: true }).catch(() => {});
  const filename = `clipboard-${Date.now()}-${crypto.randomUUID()}.${ext || "png"}`;
  const relative = `${dir}/${filename}`;
  await writeFile(relative, bytes, { baseDir: BaseDirectory.AppLocalData });
  return join(await appLocalDataDir(), relative);
}

function moveCursorToClickedCell(
  session: Session,
  host: HTMLDivElement | null,
  event: React.MouseEvent<HTMLDivElement>
) {
  if (event.button !== 0 || event.altKey || event.metaKey || event.ctrlKey) return;
  const rowsEl = host?.querySelector(".xterm-rows") as HTMLElement | null;
  if (!rowsEl) return;
  const rect = rowsEl.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return;
  const colWidth = rect.width / Math.max(1, session.term.cols);
  const rowHeight = rect.height / Math.max(1, session.term.rows);
  const col = Math.max(
    0,
    Math.min(session.term.cols - 1, Math.floor((event.clientX - rect.left) / colWidth))
  );
  const row = Math.max(
    0,
    Math.min(session.term.rows - 1, Math.floor((event.clientY - rect.top) / rowHeight))
  );
  const cursorRow = session.term.buffer.active.cursorY;
  if (row !== cursorRow) return;
  const delta = col - session.term.buffer.active.cursorX;
  if (delta === 0) return;
  event.preventDefault();
  const distance = Math.min(Math.abs(delta), session.term.cols);
  const sequence = delta > 0 ? `\x1b[${distance}C` : `\x1b[${distance}D`;
  const bytes = Array.from(new TextEncoder().encode(sequence));
  ipc.terminal.write(session.id, bytes).catch(() => {});
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

function relativeTime(ms: number): string {
  if (!ms) return "";
  const diff = Date.now() - ms;
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

function fmtBytes(bytes: number): string {
  if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(1)} GB`;
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}
