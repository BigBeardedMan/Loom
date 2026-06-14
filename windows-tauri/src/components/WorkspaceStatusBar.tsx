import { useEffect, useState } from "react";
import { Icons } from "../lib/icons";
import { ipc, type AgentDescriptor, type LiveAgentTaskGroup, type LocalEndpoint } from "../lib/ipc";
import { effectiveRailTab, PANEL_META, ROOM_META, rightRailTabLabel } from "../lib/commands";
import { LOOM_ENDPOINTS_CHANGED } from "../lib/events";
import { useRightRailContext } from "../lib/railContext";
import { useApp } from "../lib/store";
import { surface, text, workspaceColorVar } from "../lib/theme";
import type { Block } from "../modules/workspace/LayoutPersistence";

export function WorkspaceStatusBar() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const workspace = workspaces.find((w) => w.id === selectedId) ?? null;
  const layout = useApp((s) => s.layout);
  const activeBlockId = useApp((s) => s.activeBlockId);
  const activeBlock = layout?.blocks.find((b) => b.id === activeBlockId) ?? null;
  const rightRailTab = useApp((s) => s.rightRailTab);
  const setRightRailTab = useApp((s) => s.setRightRailTab);
  const updatePill = useApp((s) => s.updatePill);
  const updateStatus = useApp((s) => s.updateStatus);
  const setUpdatePill = useApp((s) => s.setUpdatePill);
  const setUpdateStatus = useApp((s) => s.setUpdateStatus);
  const [liveGroups, setLiveGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [agents, setAgents] = useState<AgentDescriptor[]>([]);
  const [endpoints, setEndpoints] = useState<LocalEndpoint[]>([]);
  const updateSegment = updateStatusSegment(updateStatus, updatePill);
  const { scopedRuns, memoryFiles } = useRightRailContext(workspace, layout?.blocks ?? []);
  const effectiveRightRailTab = effectiveRailTab(rightRailTab, {
    workspace,
    blocks: layout?.blocks ?? [],
    runs: scopedRuns,
    hasMemoryFiles: memoryFiles.length > 0,
  });
  const scopedLiveGroups = filterLiveGroupsForWorkspace(liveGroups, workspace?.folderPath);

  useEffect(() => {
    const tick = () => ipc.liveTasks.list().then(setLiveGroups).catch(() => {});
    tick();
    const id = setInterval(tick, 2500);
    return () => clearInterval(id);
  }, []);

  const refreshProviders = () => {
    ipc.agents.refresh().then(setAgents).catch(() => setAgents([]));
    ipc.endpoints.list().then(setEndpoints).catch(() => setEndpoints([]));
  };

  const checkForUpdates = async () => {
    let currentVersion = updateStatus.version ?? null;
    try {
      currentVersion = await ipc.appVersion();
    } catch {}
    setUpdateStatus({ state: "checking", version: currentVersion });
    try {
      const info = await ipc.update.check();
      if (info) {
        setUpdatePill({ version: info.version });
        setUpdateStatus({ state: "available", version: info.version });
      } else {
        setUpdatePill(null);
        setUpdateStatus({ state: "upToDate", version: currentVersion });
      }
    } catch {
      setUpdateStatus({ state: "failed", version: currentVersion });
    }
  };

  useEffect(() => {
    refreshProviders();
    window.addEventListener(LOOM_ENDPOINTS_CHANGED, refreshProviders);
    return () => window.removeEventListener(LOOM_ENDPOINTS_CHANGED, refreshProviders);
  }, []);

  return (
    <footer
      className="flex flex-none items-center gap-2 overflow-hidden"
      style={{
        minHeight: 30,
        padding: "5px 10px",
        borderRadius: 10,
        border: `1px solid ${surface.hairline}`,
        background: surface.shellStatus,
      }}
    >
      <StatusSegment
        icon="layers"
        color={workspace ? workspaceColorVar[workspace.colorName] : workspaceColorVar.blue}
        label={workspace?.name ?? "No workspace"}
        detail={workspace?.folderPath || (workspace ? ROOM_META[workspace.kindRaw]?.label : undefined)}
        onClick={() => setRightRailTab("details")}
      />
      <StatusSegment icon="panelRight" color={workspaceColorVar.blue} label={`${layout?.blocks.length ?? 0} panes`} detail={activeBlock ? blockTitle(activeBlock) : "No selection"} onClick={() => setRightRailTab("details")} />
      <StatusSegment icon="workflow" color={scopedLiveGroups.length ? workspaceColorVar.green : text.tertiary} label={`${scopedLiveGroups.length} live runs`} detail={liveRunDetail(scopedLiveGroups)} onClick={() => setRightRailTab("timeline")} />
      <StatusSegment icon="server" color={endpoints.length ? workspaceColorVar.purple : text.tertiary} label={agents[0]?.name || "Default agent"} detail={agents[0]?.model || `${endpoints.length} local endpoints`} onClick={() => setRightRailTab("tools")} />
      <div className="flex-1" />
      <StatusSegment icon={updateSegment.icon} color={updateSegment.color} label={updateSegment.label} detail={updateSegment.detail} onClick={() => void checkForUpdates()} />
      <StatusSegment icon="panelRight" color={workspaceColorVar.blue} label={rightRailTabLabel(effectiveRightRailTab)} detail="inspector" onClick={() => setRightRailTab(effectiveRightRailTab)} />
    </footer>
  );
}

function updateStatusSegment(
  status: ReturnType<typeof useApp.getState>["updateStatus"],
  pill: ReturnType<typeof useApp.getState>["updatePill"]
): { icon: keyof typeof Icons; color: string; label: string; detail?: string | null } {
  if (pill) {
    return { icon: "updateAvailable", color: workspaceColorVar.green, label: "Update Available", detail: pill.version };
  }
  switch (status.state) {
    case "available":
      return { icon: "updateAvailable", color: workspaceColorVar.green, label: "Update Available", detail: status.version };
    case "checking":
      return { icon: "updateApplying", color: workspaceColorVar.blue, label: "Checking Updates", detail: status.version };
    case "failed":
      return { icon: "failedCircle", color: workspaceColorVar.orange, label: "Update Check Failed", detail: status.version };
    case "upToDate":
      return { icon: "checkCircle", color: text.tertiary, label: "Up To Date", detail: status.version };
  }
}

function blockTitle(block: Block): string {
  if (block.customTitle?.trim()) return block.customTitle.trim();
  if (block.kind === "chat" && typeof block.autoChatIndex === "number") {
    return block.autoChatIndex === 1 ? "Chat" : `Chat ${block.autoChatIndex}`;
  }
  return PANEL_META[block.kind].label;
}

function liveRunDetail(groups: LiveAgentTaskGroup[]): string | undefined {
  const group = groups[0];
  if (!group) return undefined;
  if (group.headline) return `${group.modelLabel || group.source} - ${group.headline}`;
  return group.modelLabel || group.source;
}

function filterLiveGroupsForWorkspace(
  liveGroups: LiveAgentTaskGroup[],
  workspacePath?: string | null
): LiveAgentTaskGroup[] {
  const root = normalizedPath(workspacePath);
  if (!root) return liveGroups;
  return liveGroups.filter((group) => {
    const candidate = normalizedPath(group.workspacePath);
    if (!candidate) return true;
    return candidate === root || candidate.startsWith(`${root}/`) || candidate.startsWith(`${root}\\`);
  });
}

function normalizedPath(path?: string | null): string | null {
  const value = path?.trim();
  if (!value) return null;
  return value.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

function StatusSegment({
  icon,
  color,
  label,
  detail,
  onClick,
}: {
  icon: keyof typeof Icons;
  color: string;
  label: string;
  detail?: string | null;
  onClick?: () => void;
}) {
  const Icon = Icons[icon];
  const content = (
    <>
      <Icon size={11} strokeWidth={2.2} color={color} style={{ flex: "0 0 auto" }} />
      <span className="truncate" style={{ maxWidth: 180, fontSize: 10, fontWeight: 700 }}>
        {label}
      </span>
      {detail && (
        <span className="truncate font-mono" style={{ maxWidth: 220, fontSize: 9, color: text.tertiary }}>
          {detail}
        </span>
      )}
    </>
  );

  const style = {
    color: text.primary,
    minWidth: 0,
    cursor: onClick ? "pointer" : undefined,
    border: 0,
    background: "transparent",
    padding: 0,
    font: "inherit",
  } as const;

  if (onClick) {
    return (
      <button type="button" onClick={onClick} title={detail ? `${label} - ${detail}` : label} className="flex items-center gap-1.5" style={style}>
        {content}
      </button>
    );
  }

  return (
    <div className="flex items-center gap-1.5" style={style}>
      {content}
    </div>
  );
}
