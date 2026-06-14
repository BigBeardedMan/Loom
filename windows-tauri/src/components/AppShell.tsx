import { useEffect } from "react";
import { Titlebar } from "./Titlebar";
import { WorkspaceSidebar } from "../modules/workspace/WorkspaceSidebar";
import { WorkspaceView } from "../modules/workspace/WorkspaceView";
import { WorkspaceRightRail } from "./WorkspaceRightRail";
import { WorkspaceStatusBar } from "./WorkspaceStatusBar";
import { on } from "../lib/ipc";
import { useApp } from "../lib/store";
import { cockpit, surface } from "../lib/theme";

const SHOW_STATUS_BAR = false;

export function AppShell() {
  const isRightRailVisible = useApp((s) => s.isRightRailVisible);
  const toggleRightRail = useApp((s) => s.toggleRightRail);
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
        <aside
          className="loom-shell-sidebar-panel flex flex-col overflow-hidden"
          style={{
            background: surface.shellRail,
            borderRight: `1px solid ${surface.hairline}`,
          }}
        >
          <WorkspaceSidebar />
        </aside>
        <main className="flex-1 min-w-0 min-h-0">
          <WorkspaceView />
        </main>
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
      {SHOW_STATUS_BAR && <WorkspaceStatusBar />}
    </div>
  );
}
