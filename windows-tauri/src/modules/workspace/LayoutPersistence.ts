// Mirrors Loom/Workspace/LayoutPersistence.swift.
// Reads and writes the per-workspace Block list as JSON in the
// workspace_layouts SQLite table via existing layout_save / layout_get
// Tauri commands.

import { ipc } from "../../lib/ipc";
import type { Panel } from "../../lib/store";
import type { WorkspaceKind } from "../../lib/ipc";

/// Edge or corner the block is anchored to on the deck. Mirrors the macOS
/// `BlockPin` enum in WorkspaceLayout.swift.
export type BlockPin =
  | "left"
  | "right"
  | "top"
  | "bottom"
  | "topLeft"
  | "topRight"
  | "bottomLeft"
  | "bottomRight";

export type Block = {
  id: string;
  kind: Panel;
  // User-renamed title; falls back to the default per-kind label when absent.
  customTitle?: string;
  // Block spans the full grid row when true.
  fullRowSpan?: boolean;
  // Terminal blocks only: persisted split layout. 1-4 panes, axis controls
  // 2H/2V/3H/3V (quad is forced at 4). Mirrors Loom/Workspace/WorkspaceLayout.swift.
  terminalCount?: number;
  terminalAxis?: "h" | "v";
  // Preview blocks only: defaults the URL to localhost:300X where X is the
  // 0-based index among Preview blocks. Mirrors autoPreviewIndex on Mac.
  autoPreviewIndex?: number;
  /// Pin the block to an edge or corner of the deck. Claims ~50% of the deck
  /// by default; combined with `pinFraction` to bias the split.
  pin?: BlockPin;
  /// Pin's share of the deck, 0.2..0.8. `undefined` falls back to 0.5.
  pinFraction?: number;
  /// Relative width within the block's row. `undefined` falls back to 1.0.
  widthWeight?: number;
  /// Relative height of the row this block anchors. `undefined` falls back to 1.0.
  heightWeight?: number;
  /// Block's share of its allotted cell along the horizontal axis (0.3..1.0).
  /// `undefined` means default 1.0 (fills the cell). Drives the trailing-edge
  /// resize handle, which is the only horizontal control in a stacked row.
  widthFraction?: number;
};

export type Layout = {
  blocks: Block[];
};

function uuid(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2, 14);
}

export function defaultLayout(kind: WorkspaceKind): Layout {
  const kinds: Panel[] = (() => {
    switch (kind) {
      case "code":
        return ["editor", "terminal", "tasks", "agent"];
      case "ideas":
        return ["notes", "agent"];
      case "review":
      case "build":
        return ["preview", "agent"];
      default:
        return [];
    }
  })();
  return {
    blocks: kinds.map((k) => ({ id: uuid(), kind: k })),
  };
}

/// Legacy layouts stored `pinnedTo: { row, col }`. The current model uses
/// edge/corner pins (`pin`). On load we drop the legacy field and treat the
/// block as unpinned; the user can re-pin via drag-to-edge.
function migrateLegacyBlock(raw: unknown): Block | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== "string" || typeof r.kind !== "string") return null;
  const block: Block = {
    id: r.id,
    kind: r.kind as Panel,
  };
  if (typeof r.customTitle === "string") block.customTitle = r.customTitle;
  if (typeof r.fullRowSpan === "boolean") block.fullRowSpan = r.fullRowSpan;
  if (typeof r.terminalCount === "number") block.terminalCount = r.terminalCount;
  if (r.terminalAxis === "h" || r.terminalAxis === "v") block.terminalAxis = r.terminalAxis;
  if (typeof r.autoPreviewIndex === "number") block.autoPreviewIndex = r.autoPreviewIndex;
  if (typeof r.pin === "string") {
    const pin = r.pin as BlockPin;
    if (
      pin === "left" || pin === "right" || pin === "top" || pin === "bottom" ||
      pin === "topLeft" || pin === "topRight" || pin === "bottomLeft" || pin === "bottomRight"
    ) {
      block.pin = pin;
    }
  }
  if (typeof r.pinFraction === "number") block.pinFraction = r.pinFraction;
  if (typeof r.widthWeight === "number") block.widthWeight = r.widthWeight;
  if (typeof r.heightWeight === "number") block.heightWeight = r.heightWeight;
  if (typeof r.widthFraction === "number") block.widthFraction = r.widthFraction;
  return block;
}

export async function loadLayout(
  workspaceId: string,
  kind: WorkspaceKind
): Promise<Layout> {
  const raw = await ipc.workspace.getLayout(workspaceId).catch(() => null);
  if (!raw) return defaultLayout(kind);
  try {
    const parsed = JSON.parse(raw) as { blocks?: unknown[] };
    if (Array.isArray(parsed.blocks) && parsed.blocks.length > 0) {
      const migrated = parsed.blocks
        .map(migrateLegacyBlock)
        .filter((b): b is Block => b !== null);
      if (migrated.length > 0) return { blocks: migrated };
    }
  } catch {
    /* fall through */
  }
  return defaultLayout(kind);
}

export async function saveLayout(
  workspaceId: string,
  layout: Layout
): Promise<void> {
  await ipc.workspace.saveLayout(workspaceId, JSON.stringify(layout)).catch(() => {});
}

export function newBlock(kind: Panel): Block {
  return { id: uuid(), kind };
}
