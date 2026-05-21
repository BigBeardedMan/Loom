import { useEffect, useState, type ReactNode } from "react";
import { Icons } from "../../lib/icons";
import { useApp, workspaceKindLabel } from "../../lib/store";
import {
  ipc,
  type CliToolUsage,
  type SessionInfo,
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

const USAGE_TOOLS: Tool[] = ["claude", "codex", "lmstudio"];

export function WorkspaceSidebar() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const selectedUsageTool = useApp((s) => s.selectedUsageTool);
  const setUsageTool = useApp((s) => s.setUsageTool);
  const timeframe = useApp((s) => s.usageTimeframe);
  const [sessions, setSessions] = useState<SessionInfo[]>([]);
  const [usage, setUsage] = useState<Partial<Record<Tool, CliToolUsage>>>({});
  const [usageLoading, setUsageLoading] = useState(false);

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

  return (
    <aside
      className="flex h-full flex-col"
      style={{
        padding: sidebar.paddingV,
        background: "transparent",
      }}
    >
      <div className="scrollbar-thin flex-1 overflow-y-auto">
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

        <SectionHeader
          title="Sessions"
          trailing={
            sessions.length > 0 ? (
              <CountBadge value={sessions.length} color="var(--color-ws-green)" />
            ) : null
          }
        />
        {sessions.length === 0 ? (
          <EmptyHint label="No active terminal sessions." />
        ) : (
          <div className="flex flex-col gap-1">
            {sessions.map((session, index) => (
              <SessionRow key={session.id} session={session} index={index} />
            ))}
          </div>
        )}
      </div>
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
          {workspaceKindLabel[workspace.kindRaw]}
        </span>
        {workspace.folderPath ? (
          <span
            className="truncate"
            style={{
              marginTop: 2,
              fontSize: 10,
              color: text.tertiary,
              fontFamily: "var(--font-mono)",
            }}
          >
            {workspace.folderPath}
          </span>
        ) : (
          <span style={{ marginTop: 2, fontSize: 10, color: text.tertiary }}>
            Ready
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

function SessionRow({ session, index }: { session: SessionInfo; index: number }) {
  return (
    <div
      className="flex items-center gap-2"
      style={{
        padding: "6px 9px",
        borderRadius: radius.row,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 58%)",
        border: `1px solid ${surface.hairline}`,
      }}
      title={session.cwd ?? session.shell}
    >
      <Icons.terminal size={12} strokeWidth={2.2} color="var(--color-ws-green)" />
      <span
        className="truncate"
        style={{
          flex: 1,
          fontSize: 11,
          fontWeight: 650,
          color: text.primary,
          fontFamily: "var(--font-mono)",
        }}
      >
        Terminal {index + 1}
      </span>
      <span style={{ fontSize: 10, color: text.tertiary }}>{session.pid}</span>
    </div>
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

function countSessions(sessions: SessionInfo[], folderPath: string): number {
  if (!folderPath) return 0;
  const fp = folderPath.toLowerCase();
  return sessions.filter((s) => {
    const cwd = (s.cwd ?? "").toLowerCase();
    return cwd === fp || cwd.startsWith(fp + "\\") || cwd.startsWith(fp + "/");
  }).length;
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
