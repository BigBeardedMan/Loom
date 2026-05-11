import { useApp } from "../../lib/store";
import { TerminalPane } from "../terminal/TerminalPane";
import { EditorPane } from "../editor/EditorPane";
import { KanbanPane } from "../kanban/KanbanPane";
import { AgentPane } from "../agents/AgentPane";
import { NotesPane } from "../notes/NotesPane";
import { PreviewPane } from "../build/PreviewPane";
import {
  Panel,
  PanelGroup,
  PanelResizeHandle,
} from "react-resizable-panels";

export function WorkspaceView() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const workspace = workspaces.find((w) => w.id === selectedId);

  if (!workspace) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-loom-text-mute">
        Select or create a workspace to begin.
      </div>
    );
  }

  if (workspace.kindRaw === "ideas") {
    return (
      <PanelGroup direction="horizontal" className="h-full">
        <Panel defaultSize={55} minSize={25}>
          <NotesPane workspace={workspace} />
        </Panel>
        <PanelResizeHandle className="w-px bg-loom-border hover:bg-loom-accent" />
        <Panel defaultSize={45} minSize={25}>
          <AgentPane workspace={workspace} />
        </Panel>
      </PanelGroup>
    );
  }

  if (workspace.kindRaw === "review" || workspace.kindRaw === "build") {
    return (
      <PanelGroup direction="horizontal" className="h-full">
        <Panel defaultSize={65} minSize={25}>
          <PreviewPane workspace={workspace} />
        </Panel>
        <PanelResizeHandle className="w-px bg-loom-border hover:bg-loom-accent" />
        <Panel defaultSize={35} minSize={20}>
          <AgentPane workspace={workspace} />
        </Panel>
      </PanelGroup>
    );
  }

  return (
    <PanelGroup direction="horizontal" className="h-full">
      <Panel defaultSize={28} minSize={15}>
        <PanelGroup direction="vertical">
          <Panel defaultSize={55} minSize={20}>
            <EditorPane workspace={workspace} />
          </Panel>
          <PanelResizeHandle className="h-px bg-loom-border hover:bg-loom-accent" />
          <Panel defaultSize={45} minSize={20}>
            <KanbanPane workspace={workspace} />
          </Panel>
        </PanelGroup>
      </Panel>
      <PanelResizeHandle className="w-px bg-loom-border hover:bg-loom-accent" />
      <Panel defaultSize={44} minSize={20}>
        <TerminalPane workspace={workspace} />
      </Panel>
      <PanelResizeHandle className="w-px bg-loom-border hover:bg-loom-accent" />
      <Panel defaultSize={28} minSize={20}>
        <AgentPane workspace={workspace} />
      </Panel>
    </PanelGroup>
  );
}
