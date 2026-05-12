import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
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
import { cockpit, surface, text } from "../../lib/theme";
import type { Block, BlockPin } from "./LayoutPersistence";
import type { Workspace } from "../../lib/ipc";
import { UsageView } from "../usage/UsageView";
import { CommandsPane } from "../commands/CommandsPane";
import {
  computeDeckMetrics,
  dropTargetAt,
  pinPreviewRect,
  pinDragSign,
  MIN_BLOCK_WIDTH,
  MIN_BLOCK_HEIGHT,
  type DeckDivider,
  type DeckMetrics,
  type DropTarget,
  type Rect,
} from "./deckMetrics";

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

// Mirrors Loom/Workspace/WorkspaceView.swift deck. Custom GeometryReader-style
// layout: compute per-block frames via DeckMetrics, render absolutely
// positioned, overlay divider grips in the gaps for live resize.
export function WorkspaceView() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const layout = useApp((s) => s.layout);
  const removeBlock = useApp((s) => s.removeBlock);
  const resetLayout = useApp((s) => s.resetLayout);
  const resetAllWeights = useApp((s) => s.resetAllWeights);
  const setBlockPin = useApp((s) => s.setBlockPin);
  const swapBlocks = useApp((s) => s.swapBlocks);
  const toggleFullRow = useApp((s) => s.toggleFullRow);
  const usageTool = useApp((s) => s.selectedUsageTool);
  const workspace = workspaces.find((w) => w.id === selectedId);

  const containerRef = useRef<HTMLDivElement | null>(null);
  const [deckSize, setDeckSize] = useState<{ width: number; height: number }>({ width: 0, height: 0 });

  useLayoutEffect(() => {
    if (!containerRef.current) return;
    const el = containerRef.current;
    const ro = new ResizeObserver((entries) => {
      const r = entries[0]?.contentRect;
      if (!r) return;
      setDeckSize({ width: r.width, height: r.height });
    });
    ro.observe(el);
    const rect = el.getBoundingClientRect();
    setDeckSize({ width: rect.width, height: rect.height });
    return () => ro.disconnect();
  }, []);

  const blocks = layout?.blocks ?? [];
  const metrics = useMemo<DeckMetrics>(
    () => computeDeckMetrics(deckSize, blocks),
    [deckSize, blocks]
  );

  // Block-drag state for pin/swap. Tracking is global so the user can drag
  // anywhere on screen and we still see mousemove/mouseup.
  const [drag, setDrag] = useState<
    | { blockID: string; startMouse: { x: number; y: number }; startFrame: Rect; translation: { x: number; y: number }; target: DropTarget }
    | null
  >(null);

  useEffect(() => {
    if (!drag) return;
    const onMove = (e: PointerEvent) => {
      const containerRect = containerRef.current?.getBoundingClientRect();
      if (!containerRect) return;
      const tx = e.clientX - drag.startMouse.x;
      const ty = e.clientY - drag.startMouse.y;
      const cursor = {
        x: drag.startFrame.x + drag.startFrame.width / 2 + tx,
        y: drag.startFrame.y + drag.startFrame.height / 2 + ty,
      };
      const target = dropTargetAt(metrics, cursor, drag.blockID);
      setDrag({ ...drag, translation: { x: tx, y: ty }, target });
    };
    const onUp = () => {
      const resolved = drag.target;
      if (resolved?.kind === "pin") {
        setBlockPin(drag.blockID, resolved.pin);
      } else if (resolved?.kind === "swap") {
        swapBlocks(drag.blockID, resolved.id);
      }
      setDrag(null);
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
    return () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
    };
  }, [drag, metrics, setBlockPin, swapBlocks]);

  // Deck-level right-click for "Reset Grid Layout".
  const [deckMenu, setDeckMenu] = useState<{ x: number; y: number } | null>(null);

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

  const pinPreview =
    drag && drag.target?.kind === "pin"
      ? pinPreviewRect(drag.target.pin, deckSize)
      : null;

  return (
    <div
      ref={containerRef}
      className="h-full w-full"
      style={{ position: "relative", padding: cockpit.outerPadding, paddingTop: 0 }}
      onContextMenu={(e) => {
        // Suppress deck-level menu when right-clicking inside a block; the
        // block has its own context menu via stopPropagation.
        e.preventDefault();
        setDeckMenu({ x: e.clientX, y: e.clientY });
      }}
    >
      <div
        style={{
          position: "absolute",
          left: cockpit.outerPadding,
          top: 0,
          width: deckSize.width,
          height: deckSize.height,
        }}
      >
        {pinPreview && (
          <div
            style={{
              position: "absolute",
              left: pinPreview.x,
              top: pinPreview.y,
              width: pinPreview.width,
              height: pinPreview.height,
              borderRadius: 14,
              background: "rgba(45, 128, 245, 0.13)",
              border: "2px dashed rgba(45, 128, 245, 0.65)",
              pointerEvents: "none",
              transition: "all 120ms ease-out",
            }}
          />
        )}

        {layout.blocks.map((block) => {
          const frame = metrics.frames.get(block.id);
          if (!frame) return null;
          const isDragging = drag?.blockID === block.id;
          const isHoverTarget =
            drag && !isDragging && drag.target?.kind === "swap" && drag.target.id === block.id;
          return (
            <BlockShell
              key={block.id}
              block={block}
              frame={frame}
              translation={isDragging ? drag!.translation : { x: 0, y: 0 }}
              isDragging={!!isDragging}
              isHoverTarget={!!isHoverTarget}
              workspace={workspace}
              onRemove={() => removeBlock(block.id)}
              onTitleBarDragStart={(mouse) =>
                setDrag({
                  blockID: block.id,
                  startMouse: mouse,
                  startFrame: frame,
                  translation: { x: 0, y: 0 },
                  target: null,
                })
              }
              onToggleFullRow={() => toggleFullRow(block.id)}
              onUnpin={() => setBlockPin(block.id, undefined)}
            />
          );
        })}

        {!drag &&
          metrics.dividers.map((divider, idx) => (
            <DividerGrip
              key={`${divider.kind.kind}-${idx}`}
              divider={divider}
              metrics={metrics}
              deckSize={deckSize}
            />
          ))}
      </div>

      {deckMenu && (
        <DeckMenu
          x={deckMenu.x}
          y={deckMenu.y}
          onClose={() => setDeckMenu(null)}
          onReset={() => {
            resetAllWeights();
            setDeckMenu(null);
          }}
        />
      )}
    </div>
  );
}

function BlockShell({
  block,
  frame,
  translation,
  isDragging,
  isHoverTarget,
  workspace,
  onRemove,
  onTitleBarDragStart,
  onToggleFullRow,
  onUnpin,
}: {
  block: Block;
  frame: Rect;
  translation: { x: number; y: number };
  isDragging: boolean;
  isHoverTarget: boolean;
  workspace: Workspace;
  onRemove: () => void;
  onTitleBarDragStart: (mouse: { x: number; y: number }) => void;
  onToggleFullRow: () => void;
  onUnpin: () => void;
}) {
  const status = useApp((s) => s.blockStatus[block.id] ?? "idle");
  const updateBlock = useApp((s) => s.updateBlock);
  const isDark = DARK_PANES.includes(block.kind);
  const title = block.customTitle?.trim() || PANEL_LABEL[block.kind];
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);

  const startDrag = useCallback(
    (e: React.PointerEvent) => {
      // Only left button; ignore right-click and middle-click.
      if (e.button !== 0) return;
      e.preventDefault();
      onTitleBarDragStart({ x: e.clientX, y: e.clientY });
    },
    [onTitleBarDragStart]
  );

  return (
    <div
      style={{
        position: "absolute",
        left: frame.x + translation.x,
        top: frame.y + translation.y,
        width: frame.width,
        height: frame.height,
        zIndex: isDragging ? 10 : isHoverTarget ? 1 : 0,
        transition: isDragging ? "none" : "left 180ms ease-out, top 180ms ease-out, width 180ms ease-out, height 180ms ease-out",
      }}
      onContextMenu={(e) => {
        e.preventDefault();
        e.stopPropagation();
        setMenu({ x: e.clientX, y: e.clientY });
      }}
    >
      <LoomPanel
        className="h-full"
        dragging={isDragging}
        dropTarget={isHoverTarget}
      >
        <BlockTitleBar
          kind={block.kind}
          title={title}
          status={status}
          variant={isDark ? "dark" : "light"}
          onRename={(next) => updateBlock(block.id, { customTitle: next })}
          onClose={onRemove}
          dragHandleProps={{ onPointerDown: startDrag }}
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
          pinned={!!block.pin}
          onToggleFullRow={() => {
            onToggleFullRow();
            setMenu(null);
          }}
          onUnpin={() => {
            onUnpin();
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

function DividerGrip({
  divider,
  metrics,
  deckSize,
}: {
  divider: DeckDivider;
  metrics: DeckMetrics;
  deckSize: { width: number; height: number };
}) {
  const layoutState = useApp((s) => s.layout);
  const applyBlockWeights = useApp((s) => s.applyBlockWeights);
  const setPinFraction = useApp((s) => s.setPinFraction);
  const resetSeam = useApp((s) => s.resetSeam);
  const [hover, setHover] = useState(false);
  const [active, setActive] = useState(false);

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    if (!layoutState) return;
    const start = { x: e.clientX, y: e.clientY };

    type StartState =
      | {
          kind: "column";
          leftID: string;
          rightID: string;
          leftWeight: number;
          rightWeight: number;
          leftPx: number;
          rowWidthPx: number;
        }
      | {
          kind: "row";
          topID: string;
          bottomID: string;
          topWeight: number;
          bottomWeight: number;
          topPx: number;
          colHeightPx: number;
        }
      | {
          kind: "pin";
          pinnedID: string;
          axis: "horizontal" | "vertical";
          fraction: number;
          extentPx: number;
          sign: number;
        };

    let s: StartState | null = null;
    if (divider.kind.kind === "columnGap") {
      const { leftID, rightID } = divider.kind;
      const l = layoutState.blocks.find((b) => b.id === leftID);
      const r = layoutState.blocks.find((b) => b.id === rightID);
      const lr = metrics.frames.get(leftID);
      const rr = metrics.frames.get(rightID);
      if (!l || !r || !lr || !rr) return;
      s = {
        kind: "column",
        leftID,
        rightID,
        leftWeight: l.widthWeight ?? 1.0,
        rightWeight: r.widthWeight ?? 1.0,
        leftPx: lr.width,
        rowWidthPx: lr.width + rr.width + metrics.gap,
      };
    } else if (divider.kind.kind === "rowGap") {
      const { topAnchorID, bottomAnchorID } = divider.kind;
      const t = layoutState.blocks.find((b) => b.id === topAnchorID);
      const bb = layoutState.blocks.find((b) => b.id === bottomAnchorID);
      const tr = metrics.frames.get(topAnchorID);
      const br = metrics.frames.get(bottomAnchorID);
      if (!t || !bb || !tr || !br) return;
      s = {
        kind: "row",
        topID: topAnchorID,
        bottomID: bottomAnchorID,
        topWeight: t.heightWeight ?? 1.0,
        bottomWeight: bb.heightWeight ?? 1.0,
        topPx: tr.height,
        colHeightPx: tr.height + br.height + metrics.gap,
      };
    } else if (divider.kind.kind === "pinSplit") {
      const { pinnedID, axis } = divider.kind;
      const p = layoutState.blocks.find((b) => b.id === pinnedID);
      if (!p || !p.pin) return;
      const extent = axis === "horizontal" ? deckSize.width - metrics.gap : deckSize.height - metrics.gap;
      s = {
        kind: "pin",
        pinnedID,
        axis,
        fraction: p.pinFraction ?? 0.5,
        extentPx: extent,
        sign: pinDragSign(p.pin, axis),
      };
    }
    if (!s) return;
    setActive(true);
    const startState: StartState = s;

    const onMove = (ev: PointerEvent) => {
      const dx = ev.clientX - start.x;
      const dy = ev.clientY - start.y;
      if (startState.kind === "column") {
        const totalW = Math.max(0.0001, startState.leftWeight + startState.rightWeight);
        const usable = startState.rowWidthPx - metrics.gap;
        const minLeft = MIN_BLOCK_WIDTH;
        const minRight = MIN_BLOCK_WIDTH;
        const newLeftPx = Math.min(
          Math.max(startState.leftPx + dx, minLeft),
          Math.max(minLeft, usable - minRight)
        );
        const leftFrac = Math.max(0.001, Math.min(0.999, newLeftPx / Math.max(1, usable)));
        applyBlockWeights([
          { id: startState.leftID, widthWeight: totalW * leftFrac },
          { id: startState.rightID, widthWeight: totalW * (1 - leftFrac) },
        ]);
      } else if (startState.kind === "row") {
        const totalH = Math.max(0.0001, startState.topWeight + startState.bottomWeight);
        const usable = startState.colHeightPx - metrics.gap;
        const minTop = MIN_BLOCK_HEIGHT;
        const minBottom = MIN_BLOCK_HEIGHT;
        const newTopPx = Math.min(
          Math.max(startState.topPx + dy, minTop),
          Math.max(minTop, usable - minBottom)
        );
        const topFrac = Math.max(0.001, Math.min(0.999, newTopPx / Math.max(1, usable)));
        applyBlockWeights([
          { id: startState.topID, heightWeight: totalH * topFrac },
          { id: startState.bottomID, heightWeight: totalH * (1 - topFrac) },
        ]);
      } else {
        const d = startState.axis === "horizontal" ? dx : dy;
        const normalized = (startState.sign * d) / Math.max(1, startState.extentPx);
        setPinFraction(startState.pinnedID, startState.fraction + normalized);
      }
    };
    const onUp = () => {
      setActive(false);
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onUp);
    };
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onUp);
  };

  const onDoubleClick = () => {
    if (divider.kind.kind === "columnGap") {
      resetSeam([divider.kind.leftID, divider.kind.rightID]);
    } else if (divider.kind.kind === "rowGap") {
      resetSeam([divider.kind.topAnchorID, divider.kind.bottomAnchorID]);
    } else if (divider.kind.kind === "pinSplit") {
      setPinFraction(divider.kind.pinnedID, 0.5);
    }
  };

  const opacity = active ? 0.45 : hover ? 0.25 : 0;

  return (
    <div
      style={{
        position: "absolute",
        left: divider.rect.x,
        top: divider.rect.y,
        width: divider.rect.width,
        height: divider.rect.height,
        cursor: divider.isVertical ? "ew-resize" : "ns-resize",
        touchAction: "none",
        zIndex: 5,
      }}
      onPointerEnter={() => setHover(true)}
      onPointerLeave={() => setHover(false)}
      onPointerDown={onPointerDown}
      onDoubleClick={onDoubleClick}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          opacity,
          transition: "opacity 120ms ease-out",
          pointerEvents: "none",
        }}
      >
        <div
          style={
            divider.isVertical
              ? { width: 2, height: "100%", background: surface.hairline }
              : { width: "100%", height: 2, background: surface.hairline }
          }
        />
      </div>
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
  onUnpin,
  onClose2,
}: {
  x: number;
  y: number;
  onClose: () => void;
  fullRow: boolean;
  pinned: boolean;
  onToggleFullRow: () => void;
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
        {pinned && <MenuButton onClick={onUnpin}>Unpin from edge</MenuButton>}
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

function DeckMenu({
  x,
  y,
  onClose,
  onReset,
}: {
  x: number;
  y: number;
  onClose: () => void;
  onReset: () => void;
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
          minWidth: 180,
          fontSize: 12,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <MenuButton onClick={onReset}>Reset Grid Layout</MenuButton>
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

// Re-exports to avoid unused-import lint when tightening the file further.
export type { BlockPin };
