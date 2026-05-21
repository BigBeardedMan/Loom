import { useEffect, useState, type ReactNode } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import {
  ipc,
  type CliToolUsage,
  type IdeaNote,
  type SessionInfo,
  type TerminalTranscriptSession,
  type Workspace,
  type WorkspaceKind as IpcKind,
} from "../../lib/ipc";
import {
  radius,
  sidebar,
  surface,
  text,
  workspaceColorVar,
  type WorkspaceColor,
} from "../../lib/theme";
import { toolBrandColor, toolLabel, type Tool } from "../../lib/usage";
import type { Block } from "./LayoutPersistence";

const USAGE_TOOLS: Tool[] = ["claude", "codex", "lmstudio"];

export function WorkspaceSidebar() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const layout = useApp((s) => s.layout);
  const removeBlock = useApp((s) => s.removeBlock);
  const updateBlock = useApp((s) => s.updateBlock);
  const restoreTerminalBlock = useApp((s) => s.restoreTerminalBlock);
  const selectedUsageTool = useApp((s) => s.selectedUsageTool);
  const setUsageTool = useApp((s) => s.setUsageTool);
  const timeframe = useApp((s) => s.usageTimeframe);
  const [sessions, setSessions] = useState<SessionInfo[]>([]);
  const [usage, setUsage] = useState<Partial<Record<Tool, CliToolUsage>>>({});
  const [usageLoading, setUsageLoading] = useState(false);
  const [notes, setNotes] = useState<IdeaNote[]>([]);
  const [closed, setClosed] = useState<TerminalTranscriptSession[]>([]);
  const [deleted, setDeleted] = useState<TerminalTranscriptSession[]>([]);
  const [showDeleted, setShowDeleted] = useState(false);
  const [renamingBlock, setRenamingBlock] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [preview, setPreview] = useState<TerminalTranscriptSession | null>(null);
  const workspace = workspaces.find((w) => w.id === selectedId) ?? null;
  const terminalBlocks = (layout?.blocks ?? []).filter((b) => b.kind === "terminal");

  useEffect(() => {
    const tick = () => {
      ipc.terminal.list().then(setSessions).catch(() => {});
    };
    tick();
    const id = setInterval(tick, 2000);
    return () => clearInterval(id);
  }, []);

  const refreshUsage = async () => {
    setUsageLoading(true);
    try {
      const entries = await Promise.all(
        USAGE_TOOLS.map(async (tool) => [tool, await ipc.usage.read(tool, timeframe)] as const)
      );
      setUsage(Object.fromEntries(entries) as Partial<Record<Tool, CliToolUsage>>);
    } catch {
      // Individual CLIs can be absent; the full dashboard shows detailed errors.
    } finally {
      setUsageLoading(false);
    }
  };

  useEffect(() => {
    refreshUsage();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [timeframe]);

  const refreshSidebarData = async () => {
    if (!workspace) return;
    if (workspace.kindRaw === "ideas") {
      ipc.notes.list(workspace.id).then(setNotes).catch(() => setNotes([]));
    }
    const [recentClosed, recentDeleted] = await Promise.all([
      ipc.terminalTranscripts.recent("closed", workspace.id, 5).catch(() => []),
      ipc.terminalTranscripts.recent("deleted", workspace.id, 0).catch(() => []),
    ]);
    setClosed(recentClosed);
    setDeleted(recentDeleted);
  };

  useEffect(() => {
    refreshSidebarData();
    const id = setInterval(refreshSidebarData, 2500);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace?.id, workspace?.kindRaw]);

  const restoreTranscript = async (session: TerminalTranscriptSession) => {
    const restore = await ipc.terminalTranscripts.restore(
      session.id,
      workspace?.folderPath || session.cwd
    );
    if (!restore) {
      setPreview(session);
      return;
    }
    await restoreTerminalBlock(restore);
    await refreshSidebarData();
  };

  const closeAllTerminals = async () => {
    if (!confirm("Close all terminals?")) return;
    for (const block of terminalBlocks) {
      await removeBlock(block.id);
    }
  };

  const clearIdeas = async () => {
    if (!confirm("Delete all ideas in this workspace?")) return;
    for (const note of notes) {
      await ipc.notes.delete(note.id).catch(() => {});
    }
    await refreshSidebarData();
  };

  return (
    <aside
      className="flex h-full flex-col"
      style={{
        padding: sidebar.paddingV,
        background: "transparent",
      }}
    >
      <div className="flex min-h-0 flex-1 flex-col">
        <SectionHeader title="Workspaces" />
        <div className="flex flex-col gap-1">
          {workspaces.length === 0 ? (
            <EmptyHint label="Preparing Prompt, Ideas, and Review." />
          ) : (
            workspaces.map((ws) => (
              <WorkspaceRow
                key={ws.id}
                workspace={ws}
                selected={ws.id === selectedId && !selectedUsageTool}
                sessionCount={countSessions(sessions, ws.folderPath)}
                onSelect={() => selectWorkspace(ws.id)}
              />
            ))
          )}
        </div>

        <div style={{ height: 14 }} />

        <SectionHeader
          title="Usage"
          trailing={
            <button
              onClick={refreshUsage}
              aria-label="Refresh usage"
              title="Refresh usage"
              style={{
                padding: 3,
                borderRadius: 5,
                color: text.muted,
              }}
            >
              {usageLoading ? (
                <Icons.spinner size={12} className="animate-spin" />
              ) : (
                <Icons.refresh size={12} strokeWidth={2} />
              )}
            </button>
          }
        />
        <div className="flex flex-col gap-1">
          {USAGE_TOOLS.map((tool) => (
            <UsageRow
              key={tool}
              tool={tool}
              data={usage[tool]}
              selected={selectedUsageTool === tool}
              onSelect={() => setUsageTool(selectedUsageTool === tool ? null : tool)}
            />
          ))}
        </div>

        <div style={{ height: 14 }} />

        {workspace?.kindRaw === "ideas" ? (
          <div className="flex min-h-0 flex-1 flex-col">
            <SectionHeader
              title="Ideas"
              trailing={
                <div className="flex items-center gap-1">
                  <CountBadge value={notes.length} color="var(--color-ws-pink)" />
                  {notes.length > 0 && (
                    <TinyIconButton title="Delete all ideas" onClick={clearIdeas}>
                      <Icons.trash size={11} strokeWidth={2} />
                    </TinyIconButton>
                  )}
                </div>
              }
            />
            {notes.length === 0 ? (
              <EmptyHint label="No ideas yet. Open the Notes block and capture one." />
            ) : (
              <div className="scrollbar-thin flex min-h-0 flex-col gap-1 overflow-y-auto">
                {notes.map((note) => (
                  <IdeaRow key={note.id} note={note} onDeleted={refreshSidebarData} />
                ))}
              </div>
            )}
          </div>
        ) : workspace?.kindRaw === "review" || workspace?.kindRaw === "build" ? (
          <div className="flex min-h-0 flex-1 flex-col">
            <SectionHeader title="Sessions" />
            <EmptyHint label="Review workspaces don't have sessions yet." />
          </div>
        ) : showDeleted ? (
          <div className="flex min-h-0 flex-1 flex-col">
            <SectionHeader
              title="Recently Deleted"
              trailing={<CountBadge value={deleted.length} color="var(--color-ws-orange)" />}
            />
            <button
              onClick={() => setShowDeleted(false)}
              className="mb-2 flex items-center gap-1"
              style={{ padding: "4px 6px", color: text.muted, fontSize: 11 }}
            >
              <Icons.chevronLeft size={11} strokeWidth={2.2} />
              Back
            </button>
            {deleted.length === 0 ? (
              <EmptyHint label="Deleted terminal sessions will show up here." />
            ) : (
              <div className="scrollbar-thin flex min-h-0 flex-col gap-1 overflow-y-auto">
                {deleted.map((session) => (
                  <TranscriptRow
                    key={session.id}
                    session={session}
                    tint="var(--color-ws-orange)"
                    icon={<Icons.trash size={12} strokeWidth={2.1} />}
                    onPrimary={() => setPreview(session)}
                    actions={
                      <>
                        <TinyIconButton
                          title="Recover transcript"
                          onClick={async () => {
                            await ipc.terminalTranscripts.recoverDeleted(session.id);
                            await refreshSidebarData();
                          }}
                        >
                          <Icons.rerunReverse size={11} strokeWidth={2} />
                        </TinyIconButton>
                        <TinyIconButton
                          title="Delete permanently"
                          onClick={async () => {
                            await ipc.terminalTranscripts.deletePermanently(session.id);
                            await refreshSidebarData();
                          }}
                        >
                          <Icons.close size={11} strokeWidth={2.4} />
                        </TinyIconButton>
                      </>
                    }
                  />
                ))}
              </div>
            )}
          </div>
        ) : (
          <div className="flex min-h-0 flex-1 flex-col">
            <SectionHeader
              title="Terminal Sessions"
              trailing={
                <div className="flex items-center gap-1">
                  <CountBadge value={terminalBlocks.length} color="var(--color-ws-green)" />
                  {terminalBlocks.length > 0 && (
                    <TinyIconButton title="Close all terminals" onClick={closeAllTerminals}>
                      <Icons.trash size={11} strokeWidth={2} />
                    </TinyIconButton>
                  )}
                </div>
              }
            />
            {terminalBlocks.length === 0 ? (
              <EmptyHint label="No terminal blocks open. Use +Terminal in the top bar." />
            ) : (
              <div className="scrollbar-thin flex min-h-0 flex-col gap-1 overflow-y-auto">
                {terminalBlocks.map((block, index) => (
                  <TerminalBlockRow
                    key={block.id}
                    block={block}
                    index={index}
                    isRenaming={renamingBlock === block.id}
                    renameDraft={renameDraft}
                    setRenameDraft={setRenameDraft}
                    onRenameStart={() => {
                      setRenameDraft(block.customTitle || `Terminal ${index + 1}`);
                      setRenamingBlock(block.id);
                    }}
                    onRenameCommit={async () => {
                      await updateBlock(block.id, { customTitle: renameDraft.trim() || undefined });
                      setRenamingBlock(null);
                    }}
                    onClose={() => removeBlock(block.id)}
                  />
                ))}
              </div>
            )}

            <div className="flex-1" />

            {closed.length > 0 && (
              <>
                <div style={{ height: 12 }} />
                <SectionHeader
                  title="Recently Closed"
                  trailing={<CountBadge value={closed.length} color="var(--color-ws-green)" />}
                />
                <div className="flex flex-col gap-1">
                  {closed.map((session) => (
                    <TranscriptRow
                      key={session.id}
                      session={session}
                      tint="var(--color-ws-green)"
                      icon={<Icons.rerunReverse size={12} strokeWidth={2.1} />}
                      onPrimary={() => restoreTranscript(session)}
                      actions={
                        <>
                          <TinyIconButton title="Open transcript" onClick={() => setPreview(session)}>
                            <Icons.eye size={11} strokeWidth={2} />
                          </TinyIconButton>
                          <TinyIconButton
                            title="Move to Recently Deleted"
                            onClick={async () => {
                              await ipc.terminalTranscripts.moveToDeleted(session.id);
                              await refreshSidebarData();
                            }}
                          >
                            <Icons.trash size={11} strokeWidth={2} />
                          </TinyIconButton>
                        </>
                      }
                    />
                  ))}
                </div>
              </>
            )}
            <button
              onClick={() => setShowDeleted(true)}
              className="mt-2 flex w-full flex-none items-center gap-2"
              style={{
                padding: "6px 8px",
                borderRadius: 6,
                background: "color-mix(in srgb, " + surface.softPanel + ", transparent 55%)",
                color: text.muted,
                fontSize: 11,
              }}
            >
              <Icons.trash size={11} strokeWidth={2} />
              Recently Deleted
              <Icons.chevronRight className="ml-auto" size={11} strokeWidth={2.2} />
            </button>
          </div>
        )}
      </div>
      {preview && (
        <TranscriptPreviewModal
          session={preview}
          onClose={() => setPreview(null)}
          onRestore={() => restoreTranscript(preview)}
        />
      )}
    </aside>
  );
}

function SectionHeader({
  title,
  trailing,
}: {
  title: string;
  trailing?: ReactNode;
}) {
  return (
    <div
      className="flex items-center justify-between"
      style={{ padding: "3px 6px 7px" }}
    >
      <span className="section-header">{title}</span>
      {trailing}
    </div>
  );
}

function WorkspaceRow({
  workspace,
  selected,
  sessionCount,
  onSelect,
}: {
  workspace: Workspace;
  selected: boolean;
  sessionCount: number;
  onSelect: () => void;
}) {
  const color = workspaceColorVar[workspace.colorName as WorkspaceColor];
  const KindIcon = kindIconFor(workspace.kindRaw);
  const name = workspace.name.trim() || workspaceKindFallback(workspace.kindRaw);
  return (
    <button
      onClick={onSelect}
      className="group flex w-full items-center gap-2 text-left transition-colors"
      style={{
        padding: `${sidebar.rowPaddingV}px ${sidebar.rowPaddingH}px`,
        borderRadius: radius.row,
        background: selected
          ? "color-mix(in srgb, " + color + ", transparent 84%)"
          : "transparent",
        border: `1px solid ${selected ? "color-mix(in srgb, " + color + ", transparent 55%)" : "transparent"}`,
        color: selected ? text.primary : text.muted,
      }}
      title={workspace.folderPath || workspace.name}
    >
      <span
        aria-hidden="true"
        style={{
          width: 4,
          alignSelf: "stretch",
          minHeight: 28,
          borderRadius: 999,
          background: color,
          opacity: selected ? 1 : 0.72,
          flex: "none",
        }}
      />
      <KindIcon
        size={13}
        strokeWidth={2.1}
        style={{ color, flex: "none" }}
      />
      <span className="flex min-w-0 flex-1 flex-col">
        <span style={{ fontSize: 13, fontWeight: 700, color: text.primary }}>
          {name}
        </span>
        {workspace.folderPath && (
          <span
            className="truncate"
            style={{
              marginTop: 2,
              fontSize: 10,
              color: text.tertiary,
              fontFamily: "var(--font-mono)",
            }}
          >
            {displayPath(workspace.folderPath)}
          </span>
        )}
      </span>
      {sessionCount > 0 && (
        <CountBadge value={sessionCount} color="var(--color-ws-green)" />
      )}
    </button>
  );
}

function UsageRow({
  tool,
  data,
  selected,
  onSelect,
}: {
  tool: Tool;
  data?: CliToolUsage;
  selected: boolean;
  onSelect: () => void;
}) {
  const color = toolBrandColor(tool);
  const tokens = data
    ? data.inputTokens + data.outputTokens + data.cachedTokens
    : 0;
  const limit = tool === "codex" && data ? codexLimitSummary(data) : null;
  return (
    <button
      onClick={onSelect}
      className="flex w-full items-center gap-2 text-left transition-colors"
      style={{
        padding: "8px 10px",
        borderRadius: radius.row,
        background: selected
          ? "color-mix(in srgb, " + color + ", transparent 84%)"
          : "color-mix(in srgb, " + surface.softPanel + ", transparent 62%)",
        border: `1px solid ${selected ? "color-mix(in srgb, " + color + ", transparent 52%)" : surface.hairline}`,
        color: text.primary,
      }}
      title={`Open ${toolLabel(tool)}`}
    >
      <span
        aria-hidden="true"
        style={{
          width: 8,
          height: 8,
          borderRadius: 999,
          background: color,
          boxShadow: selected ? `0 0 10px ${color}` : "none",
          flex: "none",
        }}
      />
      <span className="flex min-w-0 flex-1 flex-col">
        <span style={{ fontSize: 12, fontWeight: 700 }}>{toolLabel(tool)}</span>
        <span
          className="truncate"
          style={{ marginTop: 2, fontSize: 10, color: text.tertiary }}
        >
          {data
            ? `${data.activeSessions} active · ${fmt(tokens)} tokens`
            : "Scanning local sessions"}
          {data?.lastActivity ? ` · ${shortAgo(data.lastActivity)}` : ""}
        </span>
      </span>
      {limit ? <LimitBadge label={limit} color={color} /> : null}
    </button>
  );
}

function TerminalBlockRow({
  block,
  index,
  isRenaming,
  renameDraft,
  setRenameDraft,
  onRenameStart,
  onRenameCommit,
  onClose,
}: {
  block: Block;
  index: number;
  isRenaming: boolean;
  renameDraft: string;
  setRenameDraft: (value: string) => void;
  onRenameStart: () => void;
  onRenameCommit: () => void;
  onClose: () => void;
}) {
  const title = block.customTitle?.trim() || (index === 0 ? "Terminal" : `Terminal ${index + 1}`);
  return (
    <div
      className="flex items-center gap-2"
      style={{
        padding: "6px 9px",
        borderRadius: radius.row,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 58%)",
        border: `1px solid ${surface.hairline}`,
      }}
      onDoubleClick={onRenameStart}
      title="Double-click to rename"
    >
      <Icons.terminal size={12} strokeWidth={2.2} color="var(--color-ws-green)" />
      {isRenaming ? (
        <input
          autoFocus
          value={renameDraft}
          onChange={(e) => setRenameDraft(e.target.value)}
          onBlur={onRenameCommit}
          onKeyDown={(e) => {
            if (e.key === "Enter") onRenameCommit();
            if (e.key === "Escape") e.currentTarget.blur();
          }}
          style={{
            flex: 1,
            minWidth: 0,
            background: "transparent",
            border: 0,
            outline: "none",
            fontSize: 11,
            fontWeight: 650,
            color: text.primary,
          }}
        />
      ) : (
        <span
          className="truncate"
          style={{
            flex: 1,
            fontSize: 11,
            fontWeight: 650,
            color: text.primary,
          }}
        >
          {title}
        </span>
      )}
      {block.terminalCount && block.terminalCount > 1 ? (
        <span style={{ fontSize: 10, color: text.tertiary }}>{block.terminalCount}</span>
      ) : null}
      <TinyIconButton title="Close terminal" onClick={onClose}>
        <Icons.close size={10} strokeWidth={2.4} />
      </TinyIconButton>
    </div>
  );
}

function IdeaRow({ note, onDeleted }: { note: IdeaNote; onDeleted: () => void }) {
  const [renaming, setRenaming] = useState(false);
  const [draft, setDraft] = useState(note.title);
  const commit = async () => {
    const title = draft.trim() || "Untitled";
    await ipc.notes.upsert({ id: note.id, workspaceId: note.workspaceId, title, body: note.body });
    setRenaming(false);
    onDeleted();
  };
  return (
    <div
      className="flex items-center gap-2"
      onDoubleClick={() => setRenaming(true)}
      style={{
        padding: "6px 9px",
        borderRadius: radius.row,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 58%)",
        border: `1px solid ${surface.hairline}`,
      }}
    >
      <Icons.lightbulb size={12} strokeWidth={2.2} color="var(--color-ws-pink)" />
      {renaming ? (
        <input
          autoFocus
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === "Enter") commit();
            if (e.key === "Escape") setRenaming(false);
          }}
          style={{
            flex: 1,
            minWidth: 0,
            background: "transparent",
            border: 0,
            outline: "none",
            fontSize: 11,
            fontWeight: 650,
            color: text.primary,
          }}
        />
      ) : (
        <span className="truncate" style={{ flex: 1, fontSize: 11, fontWeight: 650, color: text.primary }}>
          {note.title || "Untitled"}
        </span>
      )}
      <TinyIconButton
        title="Delete idea"
        onClick={async () => {
          await ipc.notes.delete(note.id);
          onDeleted();
        }}
      >
        <Icons.close size={10} strokeWidth={2.4} />
      </TinyIconButton>
    </div>
  );
}

function TranscriptRow({
  session,
  tint,
  icon,
  onPrimary,
  actions,
}: {
  session: TerminalTranscriptSession;
  tint: string;
  icon: ReactNode;
  onPrimary: () => void;
  actions: ReactNode;
}) {
  return (
    <div
      className="flex items-center gap-2"
      onClick={onPrimary}
      style={{
        padding: "6px 9px",
        borderRadius: radius.row,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 58%)",
        border: `1px solid ${surface.hairline}`,
        cursor: "pointer",
      }}
    >
      <span style={{ color: tint, flex: "none" }}>{icon}</span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="truncate" style={{ fontSize: 11, fontWeight: 650, color: text.primary }}>
          {session.title?.trim() || "Terminal Session"}
        </span>
        <span
          className="truncate"
          style={{ fontSize: 10, color: text.tertiary, fontFamily: "var(--font-mono)" }}
        >
          {displayPath(session.cwd)}
        </span>
      </span>
      <span className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
        {actions}
      </span>
    </div>
  );
}

function TranscriptPreviewModal({
  session,
  onClose,
  onRestore,
}: {
  session: TerminalTranscriptSession;
  onClose: () => void;
  onRestore: () => void;
}) {
  const [body, setBody] = useState("Loading...");
  useEffect(() => {
    ipc.terminalTranscripts.read(session.id).then(setBody).catch((e) => setBody(String(e)));
  }, [session.id]);
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.48)" }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: "min(980px, calc(100vw - 48px))",
          height: "min(760px, calc(100vh - 48px))",
          background: surface.panel,
          border: `1px solid ${surface.hairline}`,
          borderRadius: 14,
          boxShadow: "0 28px 70px rgba(0,0,0,0.45)",
          display: "flex",
          flexDirection: "column",
        }}
      >
        <header className="flex items-center gap-2" style={{ padding: "12px 14px", borderBottom: `1px solid ${surface.hairline}` }}>
          <Icons.terminal size={14} strokeWidth={2.2} color="var(--color-ws-green)" />
          <div className="min-w-0 flex-1">
            <div className="truncate" style={{ fontSize: 13, fontWeight: 700, color: text.primary }}>
              {session.title?.trim() || "Terminal Session"}
            </div>
            <div className="truncate" style={{ fontSize: 11, color: text.tertiary, fontFamily: "var(--font-mono)" }}>
              {displayPath(session.cwd)} · {fmtBytes(session.byteCount)}
            </div>
          </div>
          {session.state === "closed" && (
            <button
              onClick={onRestore}
              style={{
                padding: "6px 10px",
                borderRadius: 7,
                background: "var(--color-loom-accent)",
                color: "white",
                fontSize: 12,
                fontWeight: 650,
              }}
            >
              Restore Session
            </button>
          )}
          <TinyIconButton title="Reveal history folder" onClick={() => ipc.terminalTranscripts.folder().then(ipc.shell.open)}>
            <Icons.folderOpen size={13} strokeWidth={2} />
          </TinyIconButton>
          <TinyIconButton title="Close" onClick={onClose}>
            <Icons.close size={13} strokeWidth={2.4} />
          </TinyIconButton>
        </header>
        <pre
          className="scrollbar-thin flex-1 overflow-auto whitespace-pre-wrap"
          style={{
            margin: 0,
            padding: 14,
            background: "#04050A",
            color: "rgba(255,255,255,0.88)",
            fontSize: 12,
            lineHeight: 1.45,
            fontFamily: "var(--font-mono)",
          }}
        >
          {body}
        </pre>
      </div>
    </div>
  );
}

function TinyIconButton({
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
      title={title}
      aria-label={title}
      style={{ padding: 4, color: text.muted, borderRadius: 5, display: "inline-flex" }}
    >
      {children}
    </button>
  );
}

function CountBadge({ value, color }: { value: number; color: string }) {
  return (
    <span
      className="font-mono"
      style={{
        fontSize: 10,
        fontWeight: 800,
        color,
        padding: "1px 6px",
        borderRadius: 999,
        background: surface.inset,
        border: `1px solid ${surface.hairline}`,
      }}
    >
      {value}
    </span>
  );
}

function LimitBadge({ label, color }: { label: string; color: string }) {
  return (
    <span
      style={{
        fontSize: 10,
        fontWeight: 800,
        color,
        padding: "2px 6px",
        borderRadius: 999,
        background: "color-mix(in srgb, " + color + ", transparent 88%)",
        border: `1px solid color-mix(in srgb, ${color}, transparent 58%)`,
      }}
    >
      {label}
    </span>
  );
}

function EmptyHint({ label }: { label: string }) {
  return (
    <div
      style={{
        padding: "10px 8px",
        fontSize: 11,
        color: text.tertiary,
        textAlign: "center",
      }}
    >
      {label}
    </div>
  );
}

function kindIconFor(kind: IpcKind): typeof Icons.textCursor {
  switch (kind) {
    case "ideas":
      return Icons.lightbulb;
    case "review":
    case "build":
      return Icons.eye;
    case "code":
    default:
      return Icons.textCursor;
  }
}

function workspaceKindFallback(kind: IpcKind): string {
  switch (kind) {
    case "ideas":
      return "Ideas";
    case "review":
    case "build":
      return "Review";
    case "code":
    default:
      return "Prompt";
  }
}

function countSessions(sessions: SessionInfo[], folderPath: string): number {
  if (!folderPath) return 0;
  const fp = folderPath.toLowerCase();
  return sessions.filter((s) => {
    const cwd = (s.cwd ?? "").toLowerCase();
    return cwd === fp || cwd.startsWith(fp + "\\") || cwd.startsWith(fp + "/");
  }).length;
}

function displayPath(path: string): string {
  if (!path) return "";
  const normalized = path.replace(/[\\/]$/, "");
  const home = (
    (window as unknown as { __LOOM_HOME__?: string }).__LOOM_HOME__ ?? ""
  ).replace(/[\\/]$/, "");
  if (home && normalized.toLowerCase() === home.toLowerCase()) return "~";
  if (home && normalized.toLowerCase().startsWith(home.toLowerCase() + "\\")) {
    return "~" + normalized.slice(home.length);
  }
  return normalized;
}

function fmtBytes(bytes: number): string {
  if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(1)} GB`;
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

function codexLimitSummary(data: CliToolUsage): string | null {
  if (data.rateLimitReachedType) return "Limited";
  const peak = [
    data.rateLimitPrimaryUsedPercent,
    data.rateLimitSecondaryUsedPercent,
  ]
    .filter((v): v is number => typeof v === "number")
    .sort((a, b) => b - a)[0];
  if (peak == null) return null;
  return `${Math.round(peak)}%`;
}

function fmt(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1) + "k";
  return String(n);
}

function shortAgo(iso: string): string {
  const t = new Date(iso).getTime();
  if (!t) return "";
  const diff = Date.now() - t;
  const m = Math.floor(diff / 60000);
  if (m < 1) return "now";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}
