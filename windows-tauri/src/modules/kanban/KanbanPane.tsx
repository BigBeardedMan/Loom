import { useEffect, useState } from "react";
import { useApp } from "../../lib/store";
import { Icons } from "../../lib/icons";
import {
  ipc,
  on,
  type LiveAgentTask,
  type LiveAgentTaskGroup,
  type Workspace,
} from "../../lib/ipc";

type Props = { workspace: Workspace; blockId?: string };

const STATUS_COLUMNS: { key: LiveAgentTask["status"]; label: string }[] = [
  { key: "in_progress", label: "In Progress" },
  { key: "pending", label: "Todo" },
  { key: "completed", label: "Done" },
  { key: "cancelled", label: "Cancelled" },
];

// Mirrors Loom/Kanban/KanbanPaneView.swift — live mirror of CLI agent task state.
// Polls ~/.claude/tasks/<session>/<id>.json and ~/.codex/sessions/.../*.jsonl
// through the Rust live_tasks poller. Read-only.
export function KanbanPane({ blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [groups, setGroups] = useState<LiveAgentTaskGroup[]>([]);

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

  if (groups.length === 0) {
    return (
      <div
        className="flex h-full w-full flex-col items-center justify-center"
        style={{ background: "var(--color-loom-panel)", color: "rgba(255,255,255,0.45)", padding: 32, textAlign: "center" }}
      >
        <Icons.listBulletRect size={32} strokeWidth={1.2} />
        <div style={{ fontSize: 13, fontWeight: 500, marginTop: 8, color: "rgba(255,255,255,0.7)" }}>
          No live agent tasks
        </div>
        <div style={{ fontSize: 11, marginTop: 4, maxWidth: 280 }}>
          Tasks appear here while a Claude Code, Codex, or Gemini CLI session is in flight.
        </div>
      </div>
    );
  }

  return (
    <div
      className="scrollbar-thin h-full overflow-y-auto"
      style={{ background: "var(--color-loom-panel)" }}
    >
      {groups.map((group) => (
        <GroupBlock key={group.id} group={group} />
      ))}
    </div>
  );
}

function GroupBlock({ group }: { group: LiveAgentTaskGroup }) {
  const brand =
    group.source === "claude"
      ? "rgb(242, 99, 46)"
      : group.source === "codex"
        ? "rgb(59, 219, 117)"
        : "rgb(46, 128, 245)";
  return (
    <section style={{ padding: "14px 14px 6px" }}>
      <header className="flex items-center gap-2" style={{ marginBottom: 8 }}>
        <span
          style={{
            display: "inline-block",
            width: 8,
            height: 8,
            borderRadius: 999,
            background: brand,
          }}
        />
        <span style={{ fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,0.85)", textTransform: "uppercase", letterSpacing: 0.6 }}>
          {group.source === "claude" ? "Claude" : group.source === "codex" ? "Codex" : "Gemini"}
        </span>
        <span style={{ fontSize: 10, color: "rgba(255,255,255,0.4)", fontFamily: "var(--font-mono)" }}>
          {group.sessionId.slice(0, 8)}
        </span>
        {group.headline && (
          <span
            className="ml-auto"
            style={{
              fontSize: 11,
              color: "rgba(255,255,255,0.55)",
              maxWidth: 360,
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {group.headline}
          </span>
        )}
      </header>
      <div className="grid gap-2" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))" }}>
        {STATUS_COLUMNS.map((col) => {
          const tasks = group.tasks.filter((t) => t.status === col.key);
          if (tasks.length === 0) return null;
          return (
            <div
              key={col.key}
              style={{
                background: "rgba(255,255,255,0.03)",
                border: "1px solid rgba(255,255,255,0.06)",
                borderRadius: 10,
                padding: 10,
              }}
            >
              <div
                style={{
                  fontSize: 10,
                  fontWeight: 600,
                  color: "rgba(255,255,255,0.5)",
                  letterSpacing: 0.6,
                  textTransform: "uppercase",
                  marginBottom: 6,
                  display: "flex",
                  alignItems: "center",
                  gap: 6,
                }}
              >
                <span>{col.label}</span>
                <span style={{ color: "rgba(255,255,255,0.3)" }}>{tasks.length}</span>
              </div>
              <div className="flex flex-col gap-1.5">
                {tasks.map((t) => (
                  <TaskCard key={t.id} task={t} />
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}

function TaskCard({ task }: { task: LiveAgentTask }) {
  const subject = task.subject?.trim() || "(no subject)";
  return (
    <div
      style={{
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.05)",
        borderRadius: 8,
        padding: "8px 10px",
        fontSize: 12,
        color: "rgba(255,255,255,0.88)",
        lineHeight: 1.4,
      }}
    >
      <div style={{ fontWeight: 500 }}>{subject}</div>
      {task.activeForm && task.activeForm !== task.subject && (
        <div
          style={{
            fontSize: 11,
            color: "rgba(255,255,255,0.5)",
            marginTop: 3,
            fontFamily: "var(--font-mono)",
          }}
        >
          {task.activeForm}
        </div>
      )}
      {task.description && (
        <div
          style={{
            fontSize: 11,
            color: "rgba(255,255,255,0.55)",
            marginTop: 4,
          }}
        >
          {task.description}
        </div>
      )}
    </div>
  );
}
