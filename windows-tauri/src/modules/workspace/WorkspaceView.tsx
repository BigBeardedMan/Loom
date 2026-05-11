import { useApp } from "../../lib/store";
import { TerminalPane } from "../terminal/TerminalPane";
import { EditorPane } from "../editor/EditorPane";
import { KanbanPane } from "../kanban/KanbanPane";
import { AgentPane } from "../agents/AgentPane";
import { NotesPane } from "../notes/NotesPane";
import { PreviewPane } from "../build/PreviewPane";
import { LoomPanel } from "../../components/LoomPanel";
import { cockpit, surface } from "../../lib/theme";
import {
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from "react-resizable-panels";

// Mirrors Loom/Workspace/WorkspaceView.swift cockpit layout.
// 14 px outer padding, 12 px gap, every block wrapped in LoomPanel.
export function WorkspaceView() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const workspace = workspaces.find((w) => w.id === selectedId);

  if (!workspace) {
    return (
      <div
        className="flex h-full items-center justify-center"
        style={{ fontSize: 12, color: "var(--color-loom-text-muted)" }}
      >
        Select or create a workspace to begin.
      </div>
    );
  }

  const inner = (() => {
    if (workspace.kindRaw === "ideas") {
      return (
        <PanelGroup direction="horizontal" className="h-full">
          <Panel defaultSize={55} minSize={25}>
            <LoomPanel className="h-full">
              <NotesPane workspace={workspace} />
            </LoomPanel>
          </Panel>
          <Resize />
          <Panel defaultSize={45} minSize={25}>
            <LoomPanel className="h-full">
              <AgentPane workspace={workspace} />
            </LoomPanel>
          </Panel>
        </PanelGroup>
      );
    }

    if (workspace.kindRaw === "review" || workspace.kindRaw === "build") {
      return (
        <PanelGroup direction="horizontal" className="h-full">
          <Panel defaultSize={65} minSize={25}>
            <LoomPanel className="h-full">
              <PreviewPane workspace={workspace} />
            </LoomPanel>
          </Panel>
          <Resize />
          <Panel defaultSize={35} minSize={20}>
            <LoomPanel className="h-full">
              <AgentPane workspace={workspace} />
            </LoomPanel>
          </Panel>
        </PanelGroup>
      );
    }

    return (
      <PanelGroup direction="horizontal" className="h-full">
        <Panel defaultSize={28} minSize={15}>
          <PanelGroup direction="vertical">
            <Panel defaultSize={55} minSize={20}>
              <LoomPanel className="h-full">
                <EditorPane workspace={workspace} />
              </LoomPanel>
            </Panel>
            <Resize vertical />
            <Panel defaultSize={45} minSize={20}>
              <LoomPanel className="h-full">
                <KanbanPane workspace={workspace} />
              </LoomPanel>
            </Panel>
          </PanelGroup>
        </Panel>
        <Resize />
        <Panel defaultSize={44} minSize={20}>
          <LoomPanel className="h-full">
            <TerminalPane workspace={workspace} />
          </LoomPanel>
        </Panel>
        <Resize />
        <Panel defaultSize={28} minSize={20}>
          <LoomPanel className="h-full">
            <AgentPane workspace={workspace} />
          </LoomPanel>
        </Panel>
      </PanelGroup>
    );
  })();

  return (
    <div
      className="h-full w-full"
      style={{ padding: cockpit.outerPadding }}
    >
      {inner}
    </div>
  );
}

function Resize({ vertical = false }: { vertical?: boolean }) {
  return (
    <PanelResizeHandle
      className={vertical ? "h-2" : "w-2"}
      style={{ background: "transparent" }}
    >
      <div
        style={{
          width: vertical ? "100%" : cockpit.gap,
          height: vertical ? cockpit.gap : "100%",
          background: "transparent",
        }}
      />
      {/* visual line at center on hover for affordance */}
      <style>{`
        [data-panel-resize-handle-active="pointer"] > div,
        [data-panel-resize-handle-active="keyboard"] > div {
          background: ${surface.hairline} !important;
        }
      `}</style>
    </PanelResizeHandle>
  );
}
