import { useMemo } from "react";
import {
  DndContext,
  PointerSensor,
  useSensor,
  useSensors,
  closestCenter,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  rectSortingStrategy,
  useSortable,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { useApp, type Panel } from "../../lib/store";
import { TerminalPane } from "../terminal/TerminalPane";
import { EditorPane } from "../editor/EditorPane";
import { KanbanPane } from "../kanban/KanbanPane";
import { AgentPane } from "../agents/AgentPane";
import { NotesPane } from "../notes/NotesPane";
import { PreviewPane } from "../build/PreviewPane";
import { LoomPanel } from "../../components/LoomPanel";
import { BlockTitleBar } from "../../components/BlockTitleBar";
import { Icons } from "../../lib/icons";
import { cockpit, text } from "../../lib/theme";
import type { Block } from "./LayoutPersistence";
import type { Workspace } from "../../lib/ipc";

const PANEL_LABEL: Record<Panel, string> = {
  terminal: "Terminal",
  editor: "Editor",
  tasks: "Tasks",
  agent: "Agent",
  notes: "Notes",
  preview: "Preview",
  commands: "Commands",
};

const DARK_PANES: Panel[] = ["terminal", "agent", "preview", "notes"];

// Mirrors Loom/Workspace/WorkspaceView.swift deck (lines 43-58, 261-340).
// CSS grid auto-fits blocks at min 320 px; @dnd-kit handles reorder.
export function WorkspaceView() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const layout = useApp((s) => s.layout);
  const removeBlock = useApp((s) => s.removeBlock);
  const reorderBlocks = useApp((s) => s.reorderBlocks);
  const resetLayout = useApp((s) => s.resetLayout);
  const workspace = workspaces.find((w) => w.id === selectedId);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );

  const blockIds = useMemo(() => layout?.blocks.map((b) => b.id) ?? [], [layout]);

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

  if (!layout || layout.blocks.length === 0) {
    return (
      <div
        className="h-full w-full flex items-center justify-center"
        style={{ padding: cockpit.outerPadding }}
      >
        <div
          className="flex flex-col items-center gap-2"
          style={{
            padding: 40,
            border: `1px solid var(--color-loom-hairline)`,
            borderRadius: 14,
            background: "var(--color-loom-panel)",
            color: text.tertiary,
            textAlign: "center",
          }}
        >
          <Icons.emptyDeck size={32} strokeWidth={1.2} />
          <span style={{ fontSize: 13, fontWeight: 500, color: text.primary }}>
            Empty deck
          </span>
          <span style={{ fontSize: 11 }}>
            Add a block from the top bar to begin.
          </span>
          <button
            onClick={resetLayout}
            style={{
              marginTop: 6,
              padding: "4px 10px",
              borderRadius: 999,
              background: "var(--color-loom-soft-panel)",
              border: `1px solid var(--color-loom-hairline)`,
              fontSize: 11,
              color: text.primary,
              fontWeight: 500,
            }}
          >
            Reset to default
          </button>
        </div>
      </div>
    );
  }

  const handleDragEnd = (e: DragEndEvent) => {
    const { active, over } = e;
    if (!over || active.id === over.id) return;
    const oldIndex = layout.blocks.findIndex((b) => b.id === active.id);
    const newIndex = layout.blocks.findIndex((b) => b.id === over.id);
    if (oldIndex < 0 || newIndex < 0) return;
    reorderBlocks(arrayMove(layout.blocks, oldIndex, newIndex));
  };

  return (
    <div
      className="h-full w-full overflow-auto scrollbar-thin"
      style={{
        padding: cockpit.outerPadding,
        paddingTop: 0,
      }}
    >
      <DndContext
        sensors={sensors}
        collisionDetection={closestCenter}
        onDragEnd={handleDragEnd}
      >
        <SortableContext items={blockIds} strategy={rectSortingStrategy}>
          <div
            className="grid h-full"
            style={{
              gap: cockpit.gap,
              gridTemplateColumns: `repeat(auto-fit, minmax(360px, 1fr))`,
              gridAutoRows: `minmax(260px, 1fr)`,
            }}
          >
            {layout.blocks.map((b) => (
              <SortableBlock
                key={b.id}
                block={b}
                workspace={workspace}
                onRemove={() => removeBlock(b.id)}
              />
            ))}
          </div>
        </SortableContext>
      </DndContext>
    </div>
  );
}

function SortableBlock({
  block,
  workspace,
  onRemove,
}: {
  block: Block;
  workspace: Workspace;
  onRemove: () => void;
}) {
  const status = useApp((s) => s.blockStatus[block.id] ?? "idle");
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: block.id });

  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    minHeight: 0,
    minWidth: 0,
    height: "100%",
  };
  const isDark = DARK_PANES.includes(block.kind);

  return (
    <div ref={setNodeRef} style={style}>
      <LoomPanel className="h-full" dragging={isDragging}>
        <BlockTitleBar
          kind={block.kind}
          title={PANEL_LABEL[block.kind]}
          status={status}
          variant={isDark ? "dark" : "light"}
          onClose={onRemove}
          dragHandleProps={{ ...attributes, ...listeners }}
        />
        <div className="flex-1 min-h-0 min-w-0">
          <BlockContent kind={block.kind} workspace={workspace} blockId={block.id} />
        </div>
      </LoomPanel>
    </div>
  );
}

function BlockContent({
  kind,
  workspace,
  blockId,
}: {
  kind: Panel;
  workspace: Workspace;
  blockId: string;
}) {
  switch (kind) {
    case "terminal":
      return <TerminalPane workspace={workspace} blockId={blockId} />;
    case "editor":
      return <EditorPane workspace={workspace} blockId={blockId} />;
    case "tasks":
      return <KanbanPane workspace={workspace} blockId={blockId} />;
    case "agent":
      return <AgentPane workspace={workspace} blockId={blockId} />;
    case "notes":
      return <NotesPane workspace={workspace} blockId={blockId} />;
    case "preview":
      return <PreviewPane workspace={workspace} blockId={blockId} />;
    case "commands":
      return (
        <div
          className="flex h-full items-center justify-center"
          style={{ color: text.tertiary, fontSize: 12, padding: 24 }}
        >
          Commands pane coming soon.
        </div>
      );
    default:
      return null;
  }
}
