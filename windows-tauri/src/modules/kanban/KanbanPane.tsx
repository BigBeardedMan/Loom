import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useApp } from "../../lib/store";
import { Icons } from "../../lib/icons";
import {
  ipc,
  on,
  type AgentSource,
  type LiveAgentTask,
  type LiveAgentTaskGroup,
  type Workspace,
} from "../../lib/ipc";

type Props = { workspace: Workspace; blockId?: string };

const SOURCE_META: Record<
  AgentSource,
  { label: string; color: string; Icon: typeof Icons.sparkles }
> = {
  claude: { label: "Claude Code", color: "rgb(242, 99, 46)", Icon: Icons.sparkles },
  codex: { label: "Codex", color: "rgb(59, 219, 117)", Icon: Icons.textCursor },
  gemini: { label: "Gemini", color: "rgb(46, 128, 245)", Icon: Icons.diamond },
  lmstudio: { label: "LM Studio", color: "rgb(158, 102, 242)", Icon: Icons.cpu },
  ollama: { label: "Ollama", color: "rgb(217, 217, 217)", Icon: Icons.package },
  openAICompatible: { label: "Local", color: "rgb(140, 166, 191)", Icon: Icons.server },
};

// Mirrors Loom/Kanban/KanbanPaneView.swift: this pane shows live CLI agent
// task sessions only. Saved kanban data remains in storage for compatibility.
export function KanbanPane({ blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [groups, setGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const tasks = useMemo(() => groups.flatMap((g) => g.tasks), [groups]);

  const refresh = async () => {
    setGroups(await ipc.liveTasks.list());
  };

  useEffect(() => {
    let active = true;
    ipc.liveTasks
      .list()
      .then((g) => {
        if (active) setGroups(g);
      })
      .catch(() => {});
    let off: (() => void) | undefined;
    on<LiveAgentTaskGroup[]>("live_tasks/changed", (next) => {
      if (active) setGroups(next);
    }).then((u) => {
      off = u;
    });
    return () => {
      active = false;
      off?.();
    };
  }, []);

  useEffect(() => {
    if (!blockId) return;
    const inFlight = groups.some((g) =>
      g.tasks.some((t) => t.status === "in_progress" || t.status === "pending")
    );
    setBlockStatus(blockId, inFlight ? "active" : "idle");
  }, [groups, blockId, setBlockStatus]);

  const clearGroup = async (group: LiveAgentTaskGroup) => {
    setBusy(group.id);
    try {
      setGroups(await ipc.liveTasks.clearGroup(group.id));
    } finally {
      setBusy(null);
    }
  };

  const clearAll = async () => {
    if (!window.confirm(clearAllMessage(groups))) return;
    setBusy("all");
    try {
      setGroups(await ipc.liveTasks.clearAll());
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="flex h-full flex-col" style={{ background: "var(--color-loom-panel)" }}>
      <Header
        sessionCount={groups.length}
        taskCount={tasks.length}
        busy={busy}
        onRefresh={() => void refresh()}
        onClearAll={() => void clearAll()}
      />
      {groups.length === 0 ? (
        <EmptyState />
      ) : (
        <div className="scrollbar-thin flex-1 overflow-y-auto" style={{ padding: "4px 0" }}>
          {groups.map((group) => (
            <GroupBlock
              key={group.id}
              group={group}
              busy={busy === group.id}
              onClear={() => void clearGroup(group)}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function Header({
  sessionCount,
  taskCount,
  busy,
  onRefresh,
  onClearAll,
}: {
  sessionCount: number;
  taskCount: number;
  busy: string | null;
  onRefresh: () => void;
  onClearAll: () => void;
}) {
  return (
    <div
      className="flex items-center gap-2"
      style={{
        minHeight: 32,
        padding: "6px 12px",
        background: "var(--color-loom-inset)",
        borderBottom: "1px solid var(--color-loom-border)",
      }}
    >
      {sessionCount === 0 ? (
        <>
          <span
            style={{
              width: 10,
              height: 10,
              borderRadius: 999,
              border: "1px dashed rgba(255,255,255,0.35)",
            }}
          />
          <span style={{ fontSize: 11, fontWeight: 500, color: "rgba(255,255,255,0.56)" }}>
            No active sessions
          </span>
        </>
      ) : (
        <>
          <Icons.listBulletRect size={13} color="rgb(242, 139, 46)" strokeWidth={2.4} />
          <span style={{ fontSize: 11, fontWeight: 500, color: "rgba(255,255,255,0.86)" }}>
            {sessionCount === 1 ? "1 session" : `${sessionCount} sessions`}
          </span>
        </>
      )}
      <div style={{ flex: 1 }} />
      {taskCount > 0 && (
        <span
          style={{
            fontSize: 10,
            fontFamily: "var(--font-mono)",
            fontWeight: 700,
            color: "rgba(255,255,255,0.52)",
            background: "rgba(255,255,255,0.06)",
            borderRadius: 999,
            padding: "2px 7px",
          }}
        >
          {taskCount} tasks
        </span>
      )}
      <IconButton title="Refresh now" disabled={busy !== null} onClick={onRefresh}>
        <Icons.refresh size={13} />
      </IconButton>
      {sessionCount > 0 && (
        <IconButton title="Clear all visible task sessions" disabled={busy !== null} onClick={onClearAll}>
          <Icons.trash size={13} />
        </IconButton>
      )}
    </div>
  );
}

function GroupBlock({
  group,
  busy,
  onClear,
}: {
  group: LiveAgentTaskGroup;
  busy: boolean;
  onClear: () => void;
}) {
  const meta = SOURCE_META[group.source] ?? SOURCE_META.openAICompatible;
  const Icon = meta.Icon;
  return (
    <section>
      <header
        className="flex items-center gap-1.5"
        style={{
          minHeight: 31,
          padding: "7px 12px",
          background: "var(--color-loom-inset)",
          borderBottom: "1px solid var(--color-loom-border)",
        }}
      >
        <Icon size={12} color={meta.color} strokeWidth={2.5} />
        <span style={{ fontSize: 10, fontWeight: 700, color: "rgba(255,255,255,0.86)" }}>
          {displayName(group)}
        </span>
        <span style={{ fontSize: 9, color: "rgba(255,255,255,0.36)", fontFamily: "var(--font-mono)" }}>
          {group.sessionId.slice(0, 8)}
        </span>
        {group.headline && (
          <>
            <span style={{ color: "rgba(255,255,255,0.3)", fontSize: 10 }}>-</span>
            <span
              style={{
                minWidth: 0,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                fontSize: 10,
                color: "rgba(255,255,255,0.58)",
              }}
            >
              {group.headline}
            </span>
          </>
        )}
        <div style={{ flex: 1 }} />
        <span
          style={{
            fontSize: 9,
            fontFamily: "var(--font-mono)",
            fontWeight: 700,
            color: "rgba(255,255,255,0.5)",
            background: "rgba(255,255,255,0.05)",
            borderRadius: 999,
            padding: "1px 6px",
          }}
        >
          {group.tasks.length}
        </span>
        <IconButton title={clearHelp(group)} disabled={busy} onClick={onClear}>
          {busy ? <Icons.spinner size={12} className="animate-spin" /> : <Icons.close size={12} />}
        </IconButton>
      </header>
      <div>
        {group.tasks.map((task, index) => (
          <TaskRow key={task.id} task={task} showDivider={index < group.tasks.length - 1} />
        ))}
      </div>
    </section>
  );
}

function TaskRow({ task, showDivider }: { task: LiveAgentTask; showDivider: boolean }) {
  const title = displayTitle(task);
  return (
    <div
      className="flex items-start gap-2.5"
      style={{
        padding: "9px 12px",
        borderBottom: showDivider ? "1px solid rgba(255,255,255,0.06)" : undefined,
      }}
      onContextMenu={(event) => {
        event.preventDefault();
        void navigator.clipboard?.writeText(task.subject);
      }}
    >
      <StatusIcon status={task.status} />
      <div style={{ minWidth: 0, flex: 1 }}>
        <div
          style={{
            fontSize: 12,
            fontWeight: 500,
            color: task.status === "completed" ? "rgba(255,255,255,0.55)" : "rgba(255,255,255,0.9)",
            textDecoration: task.status === "completed" ? "line-through" : undefined,
            overflowWrap: "anywhere",
          }}
        >
          {title}
        </div>
        {task.description && (
          <div
            style={{
              marginTop: 3,
              fontSize: 11,
              color: "rgba(255,255,255,0.54)",
              lineHeight: 1.35,
              display: "-webkit-box",
              WebkitLineClamp: 2,
              WebkitBoxOrient: "vertical",
              overflow: "hidden",
            }}
          >
            {task.description}
          </div>
        )}
        <div className="flex items-center gap-1.5" style={{ marginTop: 4 }}>
          <span style={{ fontSize: 9, fontWeight: 700, color: "rgba(255,255,255,0.35)" }}>
            {sourceLabel(task)}
          </span>
          {task.status !== "pending" && (
            <>
              <span style={{ fontSize: 9, color: "rgba(255,255,255,0.25)" }}>-</span>
              <span style={{ fontSize: 9, fontWeight: 700, color: statusColor(task.status) }}>
                {statusLabel(task.status)}
              </span>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function StatusIcon({ status }: { status: LiveAgentTask["status"] }) {
  if (status === "in_progress") {
    return <Icons.spinner size={16} className="animate-spin" color="rgb(245, 196, 51)" style={{ marginTop: 1 }} />;
  }
  if (status === "completed") {
    return <Icons.checkCircle size={15} color="rgb(59, 219, 117)" style={{ marginTop: 1 }} />;
  }
  if (status === "cancelled") {
    return <Icons.failedCircle size={15} color="rgb(242, 99, 46)" style={{ marginTop: 1 }} />;
  }
  if (status === "deleted") {
    return <Icons.trash size={14} color="rgba(255,255,255,0.35)" style={{ marginTop: 1 }} />;
  }
  return (
    <span
      style={{
        width: 12,
        height: 12,
        marginTop: 3,
        borderRadius: 999,
        border: "1.5px solid rgba(255,255,255,0.38)",
        flex: "0 0 auto",
      }}
    />
  );
}

function IconButton({
  title,
  disabled,
  onClick,
  children,
}: {
  title: string;
  disabled?: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      disabled={disabled}
      onClick={onClick}
      className="grid place-items-center"
      style={{
        width: 22,
        height: 22,
        border: 0,
        background: "transparent",
        color: disabled ? "rgba(255,255,255,0.22)" : "rgba(255,255,255,0.58)",
        cursor: disabled ? "default" : "pointer",
        padding: 0,
      }}
    >
      {children}
    </button>
  );
}

function EmptyState() {
  return (
    <div
      className="flex flex-1 flex-col items-center justify-center"
      style={{ color: "rgba(255,255,255,0.45)", padding: 40, textAlign: "center" }}
    >
      <Icons.listBulletRect size={32} strokeWidth={1.2} />
      <div style={{ fontSize: 13, fontWeight: 600, marginTop: 12, color: "rgba(255,255,255,0.72)" }}>
        No tasks yet
      </div>
      <div style={{ fontSize: 11, lineHeight: 1.45, marginTop: 5, maxWidth: 300 }}>
        Run claude, codex, or lmstudio in the terminal and active task lists will mirror here.
      </div>
    </div>
  );
}

function displayName(group: LiveAgentTaskGroup): string {
  const meta = SOURCE_META[group.source] ?? SOURCE_META.openAICompatible;
  const model = normalizedModelLabel(group.modelLabel);
  return `${meta.label} - ${model ?? "Default"}`;
}

function sourceLabel(task: LiveAgentTask): string {
  const meta = SOURCE_META[task.source] ?? SOURCE_META.openAICompatible;
  const model = normalizedModelLabel(task.modelLabel);
  return `${meta.label} - ${model ?? "Default"}`;
}

function normalizedModelLabel(raw: string | null | undefined): string | null {
  const trimmed = raw?.trim();
  return trimmed ? trimmed : null;
}

function displayTitle(task: LiveAgentTask): string {
  if (task.status === "in_progress" && task.activeForm.trim()) {
    return task.activeForm;
  }
  return task.subject?.trim() || "(no subject)";
}

function statusLabel(status: LiveAgentTask["status"]): string {
  switch (status) {
    case "in_progress":
      return "In progress";
    case "completed":
      return "Done";
    case "cancelled":
      return "Cancelled";
    case "deleted":
      return "Deleted";
    case "pending":
    default:
      return "Todo";
  }
}

function statusColor(status: LiveAgentTask["status"]): string {
  switch (status) {
    case "in_progress":
      return "rgb(245, 196, 51)";
    case "completed":
      return "rgb(59, 219, 117)";
    case "cancelled":
      return "rgb(242, 99, 46)";
    case "deleted":
      return "rgba(255,255,255,0.35)";
    case "pending":
    default:
      return "rgba(255,255,255,0.5)";
  }
}

function clearHelp(group: LiveAgentTaskGroup): string {
  if (group.source === "claude" || group.source === "lmstudio") {
    return `Clear ${displayName(group)} task files`;
  }
  return `Hide ${displayName(group)} until it next updates`;
}

function clearAllMessage(groups: LiveAgentTaskGroup[]): string {
  const labels = Array.from(new Set(groups.map(displayName))).sort();
  const labelText =
    labels.length <= 3
      ? labels.join(", ")
      : `${labels.slice(0, 3).join(", ")}, and ${labels.length - 3} more`;
  return `Clear every visible task session${labelText ? ` for ${labelText}` : ""}? File-backed task sessions delete task JSON files; log-backed sessions such as Codex stay hidden until their task plan updates.`;
}
