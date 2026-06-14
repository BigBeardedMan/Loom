import { useEffect } from "react";
import { Titlebar } from "./Titlebar";
import { LoomPanel } from "./LoomPanel";
import { Icons } from "../lib/icons";
import { WorkspaceSidebar } from "../modules/workspace/WorkspaceSidebar";
import { WorkspaceView } from "../modules/workspace/WorkspaceView";
import { WorkspaceRightRail } from "./WorkspaceRightRail";
import { WorkspaceStatusBar } from "./WorkspaceStatusBar";
import { on } from "../lib/ipc";
import { useApp, workspaceKindLabel, type RightRailTab } from "../lib/store";
import { cockpit, surface, text, workspaceColorVar } from "../lib/theme";

export function AppShell() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const selectedUsageTool = useApp((s) => s.selectedUsageTool);
  const setUsageTool = useApp((s) => s.setUsageTool);
  const isRightRailVisible = useApp((s) => s.isRightRailVisible);
  const toggleRightRail = useApp((s) => s.toggleRightRail);
  const rightRailTab = useApp((s) => s.rightRailTab);
  const setRightRailTab = useApp((s) => s.setRightRailTab);
  const openSettings = useApp((s) => s.openSettings);

  useEffect(() => {
    let off: (() => void) | undefined;
    on("loom://open-settings", () => openSettings()).then((u) => {
      off = u;
    });
    return () => off?.();
  }, [openSettings]);

  return (
    <div
      className="flex h-full w-full flex-col overflow-hidden"
      style={{
        color: "var(--color-loom-text)",
        padding: cockpit.outerPadding,
        gap: 8,
        ["--loom-inspector-width" as string]: `clamp(276px, 24vw, ${cockpit.inspectorWidth}px)`,
      }}
    >
      <Titlebar />
      <div className="loom-shell-workspace-row flex flex-1 min-h-0" style={{ gap: cockpit.gap }}>
        <RoomRail
          selectedUsageTool={selectedUsageTool}
          onUsageToggle={() => setUsageTool(selectedUsageTool ? null : "claude")}
          workspaces={workspaces}
          selectedId={selectedId}
          selectWorkspace={selectWorkspace}
          isRightRailVisible={isRightRailVisible}
          activeInspectorTab={rightRailTab}
          toggleRightRail={toggleRightRail}
          openInspector={setRightRailTab}
          openSettings={openSettings}
        />
        <LoomPanel noShadow className="loom-shell-sidebar-panel">
          <WorkspaceSidebar />
        </LoomPanel>
        <LoomPanel noShadow className="flex-1 min-w-0 min-h-0">
          <WorkspaceView />
        </LoomPanel>
        {isRightRailVisible && (
          <>
            <button
              type="button"
              className="loom-right-rail-scrim"
              aria-label="Hide inspector"
              title="Hide inspector"
              onClick={toggleRightRail}
            />
            <WorkspaceRightRail />
          </>
        )}
      </div>
      <WorkspaceStatusBar />
    </div>
  );
}

function RoomRail({
  workspaces,
  selectedId,
  selectedUsageTool,
  isRightRailVisible,
  activeInspectorTab,
  selectWorkspace,
  onUsageToggle,
  toggleRightRail,
  openInspector,
  openSettings,
}: {
  workspaces: ReturnType<typeof useApp.getState>["workspaces"];
  selectedId: string | null;
  selectedUsageTool: ReturnType<typeof useApp.getState>["selectedUsageTool"];
  isRightRailVisible: boolean;
  activeInspectorTab: RightRailTab;
  selectWorkspace: (id: string | null) => void;
  onUsageToggle: () => void;
  toggleRightRail: () => void;
  openInspector: (tab: RightRailTab) => void;
  openSettings: () => void;
}) {
  return (
    <nav
      className="flex flex-none flex-col items-center"
      style={{
        width: cockpit.roomRailWidth,
        padding: "10px 5px",
        borderRadius: 10,
        border: `1px solid ${surface.hairline}`,
        background: surface.shellRail,
        gap: 8,
      }}
    >
      {workspaces.map((workspace) => {
        const selected = workspace.id === selectedId && !selectedUsageTool;
        const Icon = workspace.kindRaw === "ideas"
          ? Icons.lightbulb
          : workspace.kindRaw === "review" || workspace.kindRaw === "build"
            ? Icons.search
            : workspace.kindRaw === "runs"
              ? Icons.workflow
              : Icons.textCursor;
        return (
          <button
            key={workspace.id}
            onClick={() => selectWorkspace(workspace.id)}
            title={workspaceKindLabel[workspace.kindRaw]}
            className="flex w-full flex-col items-center gap-1"
            style={{
              padding: "5px 3px",
              borderRadius: 8,
              background: selected ? surface.softPanel : "transparent",
            }}
          >
            <span
              style={{
                width: 34,
                height: 28,
                borderRadius: 8,
                display: "grid",
                placeItems: "center",
                background: selected ? workspaceColorVar[workspace.colorName] : `color-mix(in srgb, ${workspaceColorVar[workspace.colorName]} 16%, transparent)`,
                color: selected ? "#fff" : workspaceColorVar[workspace.colorName],
              }}
            >
              <Icon size={14} strokeWidth={2.2} />
            </span>
            <span className="truncate" style={{ maxWidth: 54, fontSize: 9, fontWeight: 700, color: selected ? text.primary : text.muted }}>
              {workspaceKindLabel[workspace.kindRaw]}
            </span>
          </button>
        );
      })}
      <div className="flex-1" />
      <RailUtilityButton icon="layers" active={!!selectedUsageTool} title="Usage dashboards" onClick={onUsageToggle} />
      <RailUtilityButton icon="tools" active={isRightRailVisible && activeInspectorTab === "tools"} title="Open tools and models" onClick={() => openInspector("tools")} />
      <RailUtilityButton icon="panelRight" active={isRightRailVisible} title={isRightRailVisible ? "Hide inspector" : "Show inspector"} onClick={toggleRightRail} />
      <RailUtilityButton icon="settings" active={false} title="Open Settings" onClick={openSettings} />
    </nav>
  );
}

function RailUtilityButton({
  icon,
  active,
  title,
  onClick,
}: {
  icon: keyof typeof Icons;
  active: boolean;
  title: string;
  onClick: () => void;
}) {
  const Icon = Icons[icon];
  return (
    <button
      onClick={onClick}
      title={title}
      aria-label={title}
      style={{
        width: 34,
        height: 30,
        borderRadius: 8,
        display: "grid",
        placeItems: "center",
        background: active ? workspaceColorVar.blue : surface.softPanel,
        color: active ? "#fff" : text.muted,
      }}
    >
      <Icon size={13} strokeWidth={2.2} />
    </button>
  );
}
