import { useMemo, useState } from "react";
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
import { UsageView } from "../usage/UsageView";
import { CommandsPane } from "../commands/CommandsPane";

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
  const usageTool = useApp((s) => s.selectedUsageTool);
  const workspace = workspaces.find((w) => w.id === selectedId);

  // All hooks must run on every render — keep these above the early returns
  // so React's hook-order invariant holds when the usage dashboard toggles.
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );
  const blockIds = useMemo(() => layout?.blocks.map((b) => b.id) ?? [], [layout]);

  if (usageTool) {
    return <UsageView tool={usageTool} />;
  }

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

  const hasPinned = layout.blocks.some((b) => b.pinnedTo);
  const pinnedCols = layout.blocks
    .map((b) => b.pinnedTo?.col ?? -1)
    .filter((c) => c >= 0);
  const trackCount = hasPinned ? Math.max(4, Math.max(0, ...pinnedCols) + 1) : 0;

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
              gridTemplateColumns: hasPinned
                ? `repeat(${trackCount}, 1fr)`
                : `repeat(auto-fit, minmax(360px, 1fr))`,
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
  const updateBlock = useApp((s) => s.updateBlock);
  const layout = useApp((s) => s.layout);
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
    isOver,
  } = useSortable({ id: block.id });
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);

  const pinGridStyle: React.CSSProperties = block.pinnedTo
    ? {
        gridColumn: `${block.pinnedTo.col + 1}`,
        gridRow: `${block.pinnedTo.row + 1}`,
      }
    : {};

  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    minHeight: 0,
    minWidth: 0,
    height: "100%",
    ...(block.fullRowSpan && !block.pinnedTo ? { gridColumn: "1 / -1" } : {}),
    ...pinGridStyle,
  };
  const isDark = DARK_PANES.includes(block.kind);
  const title = block.customTitle?.trim() || PANEL_LABEL[block.kind];

  const toggleFullRow = () => {
    updateBlock(block.id, { fullRowSpan: !block.fullRowSpan });
  };

  const pinHere = () => {
    if (!layout) return;
    const idx = layout.blocks.findIndex((b) => b.id === block.id);
    if (idx < 0) return;
    const col = idx % 4;
    const row = Math.floor(idx / 4);
    updateBlock(block.id, { pinnedTo: { row, col } });
  };

  const unpin = () => {
    updateBlock(block.id, { pinnedTo: undefined });
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      onContextMenu={(e) => {
        e.preventDefault();
        setMenu({ x: e.clientX, y: e.clientY });
      }}
    >
      <LoomPanel
        className="h-full"
        dragging={isDragging}
        dropTarget={isOver && !isDragging}
      >
        <BlockTitleBar
          kind={block.kind}
          title={title}
          status={status}
          variant={isDark ? "dark" : "light"}
          onRename={(next) => updateBlock(block.id, { customTitle: next })}
          onClose={onRemove}
          dragHandleProps={{ ...attributes, ...listeners }}
        />
        <div className="flex-1 min-h-0 min-w-0">
          <BlockContent kind={block.kind} workspace={workspace} blockId={block.id} />
        </div>
      </LoomPanel>
      {menu && (
        <BlockContextMenu
          x={menu.x}
          y={menu.y}
          onClose={() => setMenu(null)}
          fullRow={!!block.fullRowSpan}
          pinned={!!block.pinnedTo}
          onToggleFullRow={() => {
            toggleFullRow();
            setMenu(null);
          }}
          onPin={() => {
            pinHere();
            setMenu(null);
          }}
          onUnpin={() => {
            unpin();
            setMenu(null);
          }}
          onClose2={() => {
            onRemove();
            setMenu(null);
          }}
        />
      )}
    </div>
  );
}

function BlockContextMenu({
  x,
  y,
  onClose,
  fullRow,
  pinned,
  onToggleFullRow,
  onPin,
  onUnpin,
  onClose2,
}: {
  x: number;
  y: number;
  onClose: () => void;
  fullRow: boolean;
  pinned: boolean;
  onToggleFullRow: () => void;
  onPin: () => void;
  onUnpin: () => void;
  onClose2: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-50"
      onClick={onClose}
      onContextMenu={(e) => {
        e.preventDefault();
        onClose();
      }}
    >
      <div
        style={{
          position: "fixed",
          left: x,
          top: y,
          background: "var(--color-loom-panel)",
          border: `1px solid var(--color-loom-hairline)`,
          borderRadius: 8,
          boxShadow: "0 12px 28px rgba(0,0,0,0.40)",
          padding: 4,
          minWidth: 200,
          fontSize: 12,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <MenuButton onClick={onToggleFullRow}>
          {fullRow ? "Unspan full row" : "Span full row"}
        </MenuButton>
        {pinned ? (
          <MenuButton onClick={onUnpin}>Unpin from grid</MenuButton>
        ) : (
          <MenuButton onClick={onPin}>Pin to current position</MenuButton>
        )}
        <div
          style={{
            height: 1,
            background: "var(--color-loom-hairline)",
            margin: "4px 0",
          }}
        />
        <MenuButton onClick={onClose2} danger>
          Close block
        </MenuButton>
      </div>
    </div>
  );
}

function MenuButton({
  onClick,
  danger,
  children,
}: {
  onClick: () => void;
  danger?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      style={{
        display: "block",
        width: "100%",
        textAlign: "left",
        padding: "7px 10px",
        background: "transparent",
        border: "none",
        borderRadius: 4,
        color: danger ? "rgb(242,99,46)" : "var(--color-loom-text)",
        cursor: "pointer",
        fontSize: 12,
      }}
      onMouseEnter={(e) =>
        ((e.target as HTMLButtonElement).style.background =
          "var(--color-loom-soft-panel)")
      }
      onMouseLeave={(e) =>
        ((e.target as HTMLButtonElement).style.background = "transparent")
      }
    >
      {children}
    </button>
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
      return <CommandsPane workspace={workspace} blockId={blockId} />;
    default:
      return null;
  }
}
