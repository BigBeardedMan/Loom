// Mirrors Loom/Workspace/LayoutPersistence.swift.
// Reads and writes the per-workspace Block list as JSON in the
// workspace_layouts SQLite table via existing layout_save / layout_get
// Tauri commands.

import { ipc } from "../../lib/ipc";
import type { Panel } from "../../lib/store";
import type { WorkspaceKind } from "../../lib/ipc";

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
  // Pin the block to a fixed grid cell. When any block has pinnedTo,
  // the grid switches to fixed-track mode. 0-indexed row/col.
  pinnedTo?: { row: number; col: number };
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

export async function loadLayout(
  workspaceId: string,
  kind: WorkspaceKind
): Promise<Layout> {
  const raw = await ipc.workspace.getLayout(workspaceId).catch(() => null);
  if (!raw) return defaultLayout(kind);
  try {
    const parsed = JSON.parse(raw) as Layout;
    if (Array.isArray(parsed.blocks) && parsed.blocks.length > 0) {
      return parsed;
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
