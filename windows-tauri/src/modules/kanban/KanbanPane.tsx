import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from "react";
import { useApp } from "../../lib/store";
import { Icons } from "../../lib/icons";
import {
  ipc,
  on,
  type AgentGraphEvent,
  type AgentGraphRunSummary,
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

const TASK_STATUSES = new Set<LiveAgentTask["status"]>([
  "pending",
  "in_progress",
  "completed",
  "cancelled",
  "deleted",
]);

async function loadProjectedGroups(summaries: AgentGraphRunSummary[]): Promise<LiveAgentTaskGroup[]> {
  const eventLists = await Promise.all(
    summaries.slice(0, 8).map((summary) => ipc.agentGraph.read(summary.id).catch(() => []))
  );
  const projected = eventLists.flatMap(projectTaskGroupsFromEvents);
  const seen = new Set<string>();
  return projected.filter((group) => {
    if (seen.has(group.id)) return false;
    seen.add(group.id);
    return true;
  });
}

function mergeTaskGroups(
  liveGroups: LiveAgentTaskGroup[],
  projectedGroups: LiveAgentTaskGroup[]
): LiveAgentTaskGroup[] {
  const liveIds = new Set(liveGroups.map((group) => group.id));
  return [...liveGroups, ...projectedGroups.filter((group) => !liveIds.has(group.id))];
}

function projectTaskGroupsFromEvents(events: AgentGraphEvent[]): LiveAgentTaskGroup[] {
  const tasks = events
    .filter((event) =>
      event.type === "task.created" ||
      event.type === "task.updated" ||
      event.type === "task.statusChanged"
    )
    .map((event): LiveAgentTask | null => {
      const payload = event.payload ?? {};
      const taskId = payload.taskID ?? payload.id;
      const sessionId = event.runId ?? event.runID ?? event.rootRunId ?? event.rootRunID;
      if (!taskId || !sessionId) return null;
      const source = normalizeAgentSource(event.source);
      const status = normalizeTaskStatus(payload.status);
      const subject = event.title?.trim() || payload.subject?.trim() || "Agent task";
      const activeForm = payload.activeForm?.trim() || event.title?.trim() || subject;
      return {
        id: `${source}:${sessionId}:${taskId}`,
        source,
        modelLabel: event.modelLabel ?? null,
        sessionId,
        taskId,
        subject,
        description: event.summary ?? "",
        activeForm,
        status,
        updatedAt: event.occurredAt,
      };
    })
    .filter((task): task is LiveAgentTask => Boolean(task));

  const latestTasks = new Map<string, LiveAgentTask>();
  for (const task of tasks) {
    const previous = latestTasks.get(task.id);
    if (!previous || task.updatedAt > previous.updatedAt) {
      latestTasks.set(task.id, task);
    }
  }

  const grouped = new Map<string, LiveAgentTask[]>();
  for (const task of latestTasks.values()) {
    const list = grouped.get(task.sessionId) ?? [];
    list.push(task);
    grouped.set(task.sessionId, list);
  }

  return Array.from(grouped.entries())
    .map(([sessionId, groupTasks]) => {
      const sorted = [...groupTasks].sort((a, b) => {
        const statusDelta = taskStatusPriority(a.status) - taskStatusPriority(b.status);
        if (statusDelta !== 0) return statusDelta;
        return b.updatedAt.localeCompare(a.updatedAt);
      });
      const first = sorted[0];
      return {
        id: `${first.source}:${modelKey(first.modelLabel)}:${sessionId}`,
        sessionId,
        source: first.source,
        modelLabel: first.modelLabel,
        lastActivity: sorted.reduce(
          (latest, task) => (task.updatedAt > latest ? task.updatedAt : latest),
          sorted[0]?.updatedAt ?? new Date(0).toISOString()
        ),
        headline: taskGroupHeadline(sorted),
        tasks: sorted,
      };
    })
    .sort((a, b) => b.lastActivity.localeCompare(a.lastActivity));
}

function normalizeAgentSource(raw: AgentGraphEvent["source"]): AgentSource {
  if (typeof raw === "string" && raw in SOURCE_META) return raw as AgentSource;
  return "lmstudio";
}

function normalizeTaskStatus(raw?: string): LiveAgentTask["status"] {
  return raw && TASK_STATUSES.has(raw as LiveAgentTask["status"])
    ? (raw as LiveAgentTask["status"])
    : "pending";
}

function taskStatusPriority(status: LiveAgentTask["status"]): number {
  switch (status) {
    case "in_progress":
      return 0;
    case "pending":
      return 1;
    case "completed":
      return 2;
    case "cancelled":
      return 3;
    case "deleted":
      return 4;
  }
}

function modelKey(modelLabel: string | null): string {
  return modelLabel?.trim().toLowerCase().replace(/[:/]/g, "_") || "default";
}

function taskGroupHeadline(tasks: LiveAgentTask[]): string | null {
  const inProgress = tasks.find((task) => task.status === "in_progress");
  if (inProgress) return inProgress.activeForm.trim() || inProgress.subject;
  return tasks[0]?.subject ?? null;
}

// Mirrors Loom/Kanban/KanbanPaneView.swift: this pane shows live CLI agent
// run/task sessions plus graph-ledger task projections. Saved kanban data
// remains in storage for compatibility.
export function KanbanPane({ blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [groups, setGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [projectedGroups, setProjectedGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [runSummaries, setRunSummaries] = useState<AgentGraphRunSummary[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const visibleGroups = useMemo(() => mergeTaskGroups(groups, projectedGroups), [groups, projectedGroups]);
  const tasks = useMemo(() => visibleGroups.flatMap((g) => g.tasks), [visibleGroups]);

  const refresh = async () => {
    const [nextGroups, nextSummaries] = await Promise.all([
      ipc.liveTasks.list(),
      ipc.agentGraph.list(),
    ]);
    const nextProjected = await loadProjectedGroups(nextSummaries);
    setGroups(nextGroups);
    setRunSummaries(nextSummaries);
    setProjectedGroups(nextProjected);
  };

  useEffect(() => {
    let active = true;
    Promise.all([ipc.liveTasks.list(), ipc.agentGraph.list()])
      .then(async ([nextGroups, nextSummaries]) => {
        const nextProjected = await loadProjectedGroups(nextSummaries);
        if (!active) return;
        setGroups(nextGroups);
        setRunSummaries(nextSummaries);
        setProjectedGroups(nextProjected);
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
        sessionCount={visibleGroups.length}
        taskCount={tasks.length}
        busy={busy}
        canClearAll={groups.length > 0}
        onRefresh={() => void refresh()}
        onClearAll={() => void clearAll()}
      />
      {visibleGroups.length === 0 && runSummaries.length === 0 ? (
        <EmptyState />
      ) : (
        <div className="scrollbar-thin flex-1 overflow-y-auto" style={{ padding: "4px 0" }}>
          {visibleGroups.map((group) => {
            const historical = !groups.some((live) => live.id === group.id);
            return (
              <GroupBlock
                key={group.id}
                group={group}
                busy={busy === group.id}
                historical={historical}
                onClear={historical ? undefined : () => void clearGroup(group)}
              />
            );
          })}
          {runSummaries.length > 0 && <RunHistory summaries={runSummaries} />}
        </div>
      )}
    </div>
  );
}

function Header({
  sessionCount,
  taskCount,
  busy,
  canClearAll,
  onRefresh,
  onClearAll,
}: {
  sessionCount: number;
  taskCount: number;
  busy: string | null;
  canClearAll: boolean;
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
      {canClearAll && (
        <IconButton title="Clear all visible run sessions" disabled={busy !== null} onClick={onClearAll}>
          <Icons.trash size={13} />
        </IconButton>
      )}
    </div>
  );
}

function GroupBlock({
  group,
  busy,
  historical = false,
  onClear,
}: {
  group: LiveAgentTaskGroup;
  busy: boolean;
  historical?: boolean;
  onClear?: () => void;
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
        {historical && (
          <span
            style={{
              fontSize: 9,
              fontWeight: 700,
              color: "rgba(255,255,255,0.36)",
              background: "rgba(255,255,255,0.05)",
              borderRadius: 999,
              padding: "1px 5px",
            }}
          >
            History
          </span>
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
        {!historical && onClear && (
          <IconButton title={clearHelp(group)} disabled={busy} onClick={onClear}>
            {busy ? <Icons.spinner size={12} className="animate-spin" /> : <Icons.close size={12} />}
          </IconButton>
        )}
      </header>
      <div>
        {group.tasks.map((task, index) => (
          <TaskRow key={task.id} task={task} showDivider={index < group.tasks.length - 1} />
        ))}
      </div>
    </section>
  );
}

function RunHistory({ summaries }: { summaries: AgentGraphRunSummary[] }) {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const [eventsById, setEventsById] = useState<Record<string, AgentGraphEvent[]>>({});

  const toggle = (summary: AgentGraphRunSummary) => {
    if (expandedId === summary.id) {
      setExpandedId(null);
      return;
    }
    setExpandedId(summary.id);
    if (eventsById[summary.id]) return;
    setLoadingId(summary.id);
    ipc.agentGraph
      .read(summary.id)
      .then((events) => {
        setEventsById((current) => ({ ...current, [summary.id]: events }));
      })
      .catch(() => {
        setEventsById((current) => ({ ...current, [summary.id]: [] }));
      })
      .finally(() => {
        setLoadingId((current) => (current === summary.id ? null : current));
      });
  };

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
        <Icons.listBulletRect size={12} color="rgba(255,255,255,0.5)" strokeWidth={2.4} />
        <span style={{ fontSize: 10, fontWeight: 700, color: "rgba(255,255,255,0.86)" }}>
          Recent runs
        </span>
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
          {summaries.length}
        </span>
      </header>
      <div>
        {summaries.map((summary, index) => (
          <RunHistoryRow
            key={summary.id}
            summary={summary}
            showDivider={index < summaries.length - 1}
            expanded={expandedId === summary.id}
            loading={loadingId === summary.id}
            events={eventsById[summary.id] ?? []}
            onToggle={() => toggle(summary)}
          />
        ))}
      </div>
    </section>
  );
}

function RunHistoryRow({
  summary,
  showDivider,
  expanded,
  loading,
  events,
  onToggle,
}: {
  summary: AgentGraphRunSummary;
  showDivider: boolean;
  expanded: boolean;
  loading: boolean;
  events: AgentGraphEvent[];
  onToggle: () => void;
}) {
  return (
    <div style={{ borderBottom: showDivider ? "1px solid rgba(255,255,255,0.06)" : undefined }}>
      <div className="flex items-start" style={{ padding: "9px 8px 9px 12px" }}>
        <button
          type="button"
          className="flex min-w-0 flex-1 items-start gap-2.5 text-left"
          style={{
            border: 0,
            background: "transparent",
            color: "inherit",
            cursor: "pointer",
            padding: 0,
          }}
          onClick={onToggle}
          onContextMenu={(event) => {
            event.preventDefault();
            void navigator.clipboard?.writeText(summary.id);
          }}
        >
          <RunStatusIcon status={summary.status} />
          <div style={{ minWidth: 0, flex: 1 }}>
            <div
              style={{
                fontSize: 12,
                fontWeight: 500,
                color: "rgba(255,255,255,0.9)",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {summary.title || summary.id}
            </div>
            <div className="flex items-center gap-1.5" style={{ marginTop: 4 }}>
              <span style={{ fontSize: 9, fontWeight: 700, color: "rgba(255,255,255,0.35)" }}>
                {runSummarySource(summary)}
              </span>
              <span style={{ fontSize: 9, color: "rgba(255,255,255,0.25)" }}>-</span>
              <span style={{ fontSize: 9, fontWeight: 700, color: runStatusColor(summary.status) }}>
                {summary.status || "running"}
              </span>
              <span style={{ fontSize: 9, color: "rgba(255,255,255,0.25)" }}>-</span>
              <span style={{ fontSize: 9, color: "rgba(255,255,255,0.48)" }}>
                {formatRunTime(summary.lastActivity)}
              </span>
            </div>
            <div
              style={{
                marginTop: 3,
                fontSize: 9,
                fontFamily: "var(--font-mono)",
                color: "rgba(255,255,255,0.28)",
              }}
            >
              {summary.id.slice(0, 8)}
            </div>
            <div
              style={{
                marginTop: 3,
                fontSize: 9,
                fontFamily: "var(--font-mono)",
                color: "rgba(255,255,255,0.34)",
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
            >
              {runSummaryChips(summary).join(" - ")}
            </div>
          </div>
          {expanded ? (
            <Icons.chevronDown size={13} color="rgba(255,255,255,0.45)" style={{ marginTop: 2 }} />
          ) : (
            <Icons.chevronRight size={13} color="rgba(255,255,255,0.45)" style={{ marginTop: 2 }} />
          )}
        </button>
        <div className="flex items-center gap-0.5" style={{ marginLeft: 6 }}>
          <IconButton
            title="Copy ledger path"
            onClick={() => void navigator.clipboard?.writeText(summary.ledgerPath)}
          >
            <Icons.copy size={12} />
          </IconButton>
          <IconButton
            title="Reveal ledger"
            onClick={() => void ipc.agentGraph.reveal(summary.id)}
          >
            <Icons.folderOpen size={12} />
          </IconButton>
        </div>
      </div>
      {expanded && (
        <RunTimeline
          loading={loading}
          events={events}
        >
          No ledger events found for this run.
        </RunTimeline>
      )}
    </div>
  );
}

function RunTimeline({
  loading,
  events,
  children,
}: {
  loading: boolean;
  events: AgentGraphEvent[];
  children: ReactNode;
}) {
  if (loading) {
    return (
      <div className="flex items-center gap-2" style={timelineContainerStyle}>
        <Icons.spinner size={13} className="animate-spin" />
        <span style={{ fontSize: 10, fontWeight: 700, color: "rgba(255,255,255,0.52)" }}>
          Loading timeline
        </span>
      </div>
    );
  }
  if (events.length === 0) {
    return (
      <div style={timelineContainerStyle}>
        <span style={{ fontSize: 10, fontWeight: 700, color: "rgba(255,255,255,0.52)" }}>
          {children}
        </span>
      </div>
    );
  }
  return (
    <div>
      {[...events]
        .sort((a, b) => new Date(a.occurredAt).getTime() - new Date(b.occurredAt).getTime())
        .map((event) => (
          <RunTimelineRow key={event.eventId ?? event.eventID ?? `${event.type}-${event.occurredAt}`} event={event} />
        ))}
    </div>
  );
}

const timelineContainerStyle = {
  padding: "8px 12px 8px 40px",
  background: "rgba(0,0,0,0.12)",
} satisfies CSSProperties;

function RunTimelineRow({ event }: { event: AgentGraphEvent }) {
  return (
    <div
      className="flex items-start gap-2"
      style={{
        padding: "7px 12px 7px 40px",
        background: "rgba(0,0,0,0.12)",
      }}
    >
      <TimelineIcon type={event.type} />
      <div style={{ minWidth: 0, flex: 1 }}>
        <div className="flex items-center gap-1.5">
          <span style={{ fontSize: 10, fontWeight: 700, color: "rgba(255,255,255,0.82)" }}>
            {timelineLabel(event.type)}
          </span>
          <span style={{ fontSize: 9, fontFamily: "var(--font-mono)", color: "rgba(255,255,255,0.32)" }}>
            {formatEventTime(event.occurredAt)}
          </span>
        </div>
        {timelineText(event) && (
          <div
            style={{
              marginTop: 3,
              fontSize: 10,
              lineHeight: 1.35,
              color: "rgba(255,255,255,0.54)",
              display: "-webkit-box",
              WebkitLineClamp: 2,
              WebkitBoxOrient: "vertical",
              overflow: "hidden",
            }}
          >
            {timelineText(event)}
          </div>
        )}
        {timelineChips(event).length > 0 && (
          <div
            style={{
              marginTop: 3,
              fontSize: 9,
              fontFamily: "var(--font-mono)",
              color: "rgba(255,255,255,0.34)",
              overflow: "hidden",
              textOverflow: "ellipsis",
              whiteSpace: "nowrap",
            }}
          >
            {timelineChips(event).join(" - ")}
          </div>
        )}
      </div>
    </div>
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

function RunStatusIcon({ status }: { status: string }) {
  const normalized = status.toLowerCase();
  if (normalized === "completed") {
    return <Icons.checkCircle size={15} color="rgb(59, 219, 117)" style={{ marginTop: 1 }} />;
  }
  if (normalized === "failed" || normalized === "cancelled") {
    return <Icons.failedCircle size={15} color="rgb(242, 99, 46)" style={{ marginTop: 1 }} />;
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

function TimelineIcon({ type }: { type: string }) {
  const color = timelineColor(type);
  if (type === "run.completed" || type === "spawn.completed" || type === "handoff.accepted") {
    return <Icons.checkCircle size={13} color={color} style={{ marginTop: 1, flex: "0 0 auto" }} />;
  }
  if (
    type === "run.failed" ||
    type === "spawn.failed" ||
    type === "handoff.rejected" ||
    type === "attention.requested"
  ) {
    return <Icons.failedCircle size={13} color={color} style={{ marginTop: 1, flex: "0 0 auto" }} />;
  }
  if (type.startsWith("tool.")) {
    return <Icons.settings size={13} color={color} style={{ marginTop: 1, flex: "0 0 auto" }} />;
  }
  if (type.startsWith("task.")) {
    return <Icons.listBulletRect size={13} color={color} style={{ marginTop: 1, flex: "0 0 auto" }} />;
  }
  return (
    <span
      style={{
        width: 10,
        height: 10,
        marginTop: 4,
        borderRadius: 999,
        border: `1.5px solid ${color}`,
        flex: "0 0 auto",
      }}
    />
  );
}

function timelineLabel(type: string): string {
  switch (type) {
    case "graph.created":
      return "Graph created";
    case "run.started":
      return "Run started";
    case "run.heartbeat":
      return "Heartbeat";
    case "run.statusChanged":
      return "Run status";
    case "run.completed":
      return "Run completed";
    case "run.failed":
      return "Run failed";
    case "run.cancelled":
      return "Run cancelled";
    case "task.created":
      return "Task created";
    case "task.updated":
      return "Task updated";
    case "task.statusChanged":
      return "Task status";
    case "edge.created":
      return "Lineage edge";
    case "spawn.requested":
      return "Spawn requested";
    case "spawn.started":
      return "Spawn started";
    case "spawn.completed":
      return "Spawn completed";
    case "spawn.failed":
      return "Spawn failed";
    case "tool.started":
      return "Tool started";
    case "tool.completed":
      return "Tool completed";
    case "handoff.written":
      return "Handoff written";
    case "handoff.accepted":
      return "Handoff accepted";
    case "handoff.rejected":
      return "Handoff rejected";
    case "attention.requested":
      return "Attention requested";
    case "andon.paused":
      return "Andon paused";
    case "andon.resumed":
      return "Andon resumed";
    default:
      return type;
  }
}

function timelineColor(type: string): string {
  if (type === "run.completed" || type === "spawn.completed" || type === "handoff.accepted") {
    return "rgb(59, 219, 117)";
  }
  if (
    type === "run.failed" ||
    type === "spawn.failed" ||
    type === "handoff.rejected" ||
    type === "attention.requested"
  ) {
    return "rgb(242, 99, 46)";
  }
  if (type.startsWith("tool.")) return "rgb(158, 102, 242)";
  if (type.startsWith("task.")) return "rgb(242, 139, 46)";
  return "rgba(255,255,255,0.46)";
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
        No runs yet
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

function runSummarySource(summary: AgentGraphRunSummary): string {
  const rawSource = summary.source?.trim();
  const source =
    rawSource && rawSource in SOURCE_META
      ? SOURCE_META[rawSource as AgentSource].label
      : rawSource;
  const model = normalizedModelLabel(summary.modelLabel);
  return [source, model].filter(Boolean).join(" - ") || "Run";
}

function runSummaryChips(summary: AgentGraphRunSummary): string[] {
  const chips = [`${summary.eventCount ?? 0} events`];
  if (summary.toolEventCount && summary.toolEventCount > 0) {
    chips.push(`${summary.toolEventCount} tool events`);
  }
  if (summary.taskCount && summary.taskCount > 0) {
    chips.push(`${summary.taskCount} tasks`);
  }
  if (summary.toolNames && summary.toolNames.length > 0) {
    chips.push(summary.toolNames.slice(0, 3).join(", "));
  }
  if (summary.gitBranch && summary.gitBranch !== "HEAD") {
    chips.push(`branch: ${summary.gitBranch}`);
  }
  if (summary.gitHead) {
    chips.push(`head: ${summary.gitHead}`);
  }
  if (summary.gitDirty) {
    chips.push("dirty");
  }
  if (summary.workspacePath) {
    const bits = summary.workspacePath.split(/[\\/]/).filter(Boolean);
    chips.push(bits[bits.length - 1] ?? summary.workspacePath);
  } else if (summary.gitRoot) {
    const bits = summary.gitRoot.split(/[\\/]/).filter(Boolean);
    chips.push(bits[bits.length - 1] ?? summary.gitRoot);
  }
  return chips;
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

function runStatusColor(status: string): string {
  switch (status.toLowerCase()) {
    case "completed":
      return "rgb(59, 219, 117)";
    case "failed":
    case "cancelled":
      return "rgb(242, 99, 46)";
    default:
      return "rgba(255,255,255,0.5)";
  }
}

function timelineText(event: AgentGraphEvent): string {
  return [event.title, event.summary, event.payload?.reviewSummary]
    .map((value) => value?.trim())
    .filter(Boolean)
    .join(" - ");
}

function timelineChips(event: AgentGraphEvent): string[] {
  const payload = event.payload ?? {};
  const chips = ["tool", "status", "taskID", "subject", "activeForm"]
    .map((key) => {
      const value = payload[key]?.trim();
      return value ? `${key}: ${value}` : null;
    })
    .filter((value): value is string => Boolean(value));
  const parent = event.parentRunId ?? event.parentRunID;
  const branch = payload.gitBranch?.trim();
  if (branch && branch !== "HEAD") chips.push(`branch: ${branch}`);
  const head = payload.gitHead?.trim();
  if (head) chips.push(`head: ${head}`);
  if (payload.gitDirty === "true") chips.push("dirty");
  if (parent) chips.push(`parent: ${parent.slice(0, 8)}`);
  if (event.workspacePath) {
    const bits = event.workspacePath.split(/[\\/]/).filter(Boolean);
    chips.push(bits[bits.length - 1] ?? event.workspacePath);
  } else if (payload.gitRoot) {
    const bits = payload.gitRoot.split(/[\\/]/).filter(Boolean);
    chips.push(bits[bits.length - 1] ?? payload.gitRoot);
  }
  if (event.permissionMode) chips.push(event.permissionMode);
  return chips;
}

function formatRunTime(raw: string): string {
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw;
  return date.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function formatEventTime(raw: string): string {
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw;
  return date.toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
  });
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
  return `Clear every visible run session${labelText ? ` for ${labelText}` : ""}? File-backed sessions delete task JSON files; log-backed sessions such as Codex stay hidden until their task plan updates.`;
}
