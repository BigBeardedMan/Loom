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
