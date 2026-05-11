import { useApp } from "../../lib/store";
import { TerminalPane } from "../terminal/TerminalPane";
import { EditorPane } from "../editor/EditorPane";
import { KanbanPane } from "../kanban/KanbanPane";
import { AgentPane } from "../agents/AgentPane";
import { NotesPane } from "../notes/NotesPane";
import { PreviewPane } from "../build/PreviewPane";
import { LoomPanel } from "../../components/LoomPanel";
import { cockpit, text } from "../../lib/theme";
import {
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from "react-resizable-panels";

// Mirrors Loom/Workspace/WorkspaceView.swift cockpit (lines 41-58).
// 14 px outer padding, 12 px gap, every block wrapped in LoomPanel so the
// gradient bg shows through the gaps between cards.
export function WorkspaceView() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const workspace = workspaces.find((w) => w.id === selectedId);

  if (!workspace) {
    return (
      <div
        className="flex h-full items-center justify-center"
        style={{ fontSize: 12, color: text.muted }}
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
          <ResizeH />
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
          <ResizeH />
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
            <ResizeV />
            <Panel defaultSize={45} minSize={20}>
              <LoomPanel className="h-full">
                <KanbanPane workspace={workspace} />
              </LoomPanel>
            </Panel>
          </PanelGroup>
        </Panel>
        <ResizeH />
        <Panel defaultSize={44} minSize={20}>
          <LoomPanel className="h-full">
            <TerminalPane workspace={workspace} />
          </LoomPanel>
        </Panel>
        <ResizeH />
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
      style={{
        paddingLeft: cockpit.outerPadding,
        paddingRight: cockpit.outerPadding,
        paddingBottom: cockpit.outerPadding,
        paddingTop: 0,
      }}
    >
      {inner}
    </div>
  );
}

function ResizeH() {
  return (
    <PanelResizeHandle
      style={{
        width: cockpit.gap,
        background: "transparent",
        position: "relative",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          margin: "auto",
          width: 2,
          background: "transparent",
        }}
      />
    </PanelResizeHandle>
  );
}

function ResizeV() {
  return (
    <PanelResizeHandle
      style={{
        height: cockpit.gap,
        background: "transparent",
        position: "relative",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          margin: "auto",
          height: 2,
          background: "transparent",
        }}
      />
    </PanelResizeHandle>
  );
}
