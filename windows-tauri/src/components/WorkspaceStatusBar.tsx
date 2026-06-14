import { useEffect, useState } from "react";
import { Icons } from "../lib/icons";
import { ipc, type AgentDescriptor, type LiveAgentTaskGroup, type LocalEndpoint } from "../lib/ipc";
import { PANEL_META } from "../lib/commands";
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
  const updatePill = useApp((s) => s.updatePill);
  const [liveGroups, setLiveGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [agents, setAgents] = useState<AgentDescriptor[]>([]);
  const [endpoints, setEndpoints] = useState<LocalEndpoint[]>([]);

  useEffect(() => {
    const tick = () => ipc.liveTasks.list().then(setLiveGroups).catch(() => {});
    tick();
    const id = setInterval(tick, 2500);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    ipc.agents.refresh().then(setAgents).catch(() => setAgents([]));
    ipc.endpoints.list().then(setEndpoints).catch(() => setEndpoints([]));
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
      <StatusSegment icon="layers" color={workspace ? workspaceColorVar[workspace.colorName] : workspaceColorVar.blue} label={workspace?.name ?? "No workspace"} detail={workspace?.folderPath || workspace?.kindRaw} />
      <StatusSegment icon="panelRight" color={workspaceColorVar.blue} label={`${layout?.blocks.length ?? 0} panes`} detail={activeBlock ? blockTitle(activeBlock) : "No selection"} />
      <StatusSegment icon="workflow" color={liveGroups.length ? workspaceColorVar.green : text.tertiary} label={`${liveGroups.length} live runs`} detail={liveRunDetail(liveGroups)} />
      <StatusSegment icon="server" color={endpoints.length ? workspaceColorVar.purple : text.tertiary} label={agents[0]?.name || "Default agent"} detail={agents[0]?.model || `${endpoints.length} local endpoints`} />
      <div className="flex-1" />
      <StatusSegment icon="panelRight" color={workspaceColorVar.blue} label={rightRailTab} detail="inspector" />
      {updatePill && <StatusSegment icon="updateAvailable" color={workspaceColorVar.green} label="Update available" detail={updatePill.version} />}
    </footer>
  );
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

function StatusSegment({
  icon,
  color,
  label,
  detail,
}: {
  icon: keyof typeof Icons;
  color: string;
  label: string;
  detail?: string | null;
}) {
  const Icon = Icons[icon];
  return (
    <div className="flex min-w-0 items-center gap-1.5" style={{ color: text.primary }}>
      <Icon size={11} strokeWidth={2.2} color={color} style={{ flex: "0 0 auto" }} />
      <span className="truncate" style={{ maxWidth: 180, fontSize: 10, fontWeight: 700 }}>
        {label}
      </span>
      {detail && (
        <span className="truncate font-mono" style={{ maxWidth: 220, fontSize: 9, color: text.tertiary }}>
          {detail}
        </span>
      )}
    </div>
  );
}
