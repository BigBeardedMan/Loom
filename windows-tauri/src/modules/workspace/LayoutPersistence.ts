// Mirrors Loom/Workspace/LayoutPersistence.swift.
// Reads and writes the per-workspace Block list as JSON in the
// workspace_layouts SQLite table via existing layout_save / layout_get
// Tauri commands.

import { ipc } from "../../lib/ipc";
import type { Panel } from "../../lib/store";
import type { TerminalTranscriptRestore, WorkspaceKind } from "../../lib/ipc";
import { isPanelKind } from "../../lib/commands";

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
  // Transient restore payload for a recently-closed transcript. Never persisted.
  restoredTranscript?: TerminalTranscriptRestore;
  // Chat blocks only: stable display index, mirroring macOS autoChatIndex.
  autoChatIndex?: number;
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

type LayoutEnvelope = Record<string, unknown>;

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
        return ["agent"];
      case "ideas":
        return ["agent"];
      case "review":
      case "build":
        return ["agent"];
      case "runs":
        return ["tasks", "chat"];
      default:
        return [];
    }
  })();
  let chatIndex = 0;
  return {
    blocks: kinds.map((k) => {
      if (k === "chat") {
        chatIndex += 1;
        return { id: uuid(), kind: k, autoChatIndex: chatIndex };
      }
      return { id: uuid(), kind: k };
    }),
  };
}

/// Legacy layouts stored `pinnedTo: { row, col }`. The current model uses
/// edge/corner pins (`pin`). On load we drop the legacy field and treat the
/// block as unpinned; the user can re-pin via drag-to-edge.
function migrateLegacyBlock(raw: unknown): Block | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (!isPanelKind(r.kind)) return null;
  const block: Block = {
    id: typeof r.id === "string" ? r.id : uuid(),
    kind: r.kind,
  };
  if (typeof r.customTitle === "string") block.customTitle = r.customTitle;
  if (typeof r.fullRowSpan === "boolean") block.fullRowSpan = r.fullRowSpan;
  if (typeof r.spansFullRow === "boolean") block.fullRowSpan = r.spansFullRow;
  if (typeof r.terminalCount === "number") {
    block.terminalCount = r.terminalCount;
  } else if (Array.isArray(r.terminalCwds) && r.terminalCwds.length > 0) {
    block.terminalCount = Math.max(1, Math.min(4, r.terminalCwds.length));
  }
  const terminalAxis = normalizeTerminalAxis(r.terminalAxis ?? r.terminalSplitAxis);
  if (terminalAxis) block.terminalAxis = terminalAxis;
  if (typeof r.autoChatIndex === "number") block.autoChatIndex = r.autoChatIndex;
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

function normalizeTerminalAxis(raw: unknown): Block["terminalAxis"] | null {
  if (raw === "h" || raw === "horizontal") return "h";
  if (raw === "v" || raw === "vertical") return "v";
  return null;
}

function blocksFromParsedLayout(parsed: unknown, kind: WorkspaceKind): unknown[] | null {
  const r = layoutEnvelope(parsed);
  if (!r) return null;
  const blocksByKind = layoutBlocksByKind(r);
  if (blocksByKind) {
    for (const key of layoutKindKeys(kind)) {
      const blocks = blocksByKind[key];
      if (Array.isArray(blocks)) return blocks;
    }
  }
  return Array.isArray(r.blocks) ? r.blocks : null;
}

export async function loadLayout(
  workspaceId: string,
  kind: WorkspaceKind
): Promise<Layout> {
  const raw = await ipc.workspace.getLayout(workspaceId).catch(() => null);
  if (!raw) return defaultLayout(kind);
  try {
    const parsed = JSON.parse(raw) as unknown;
    const blocks = blocksFromParsedLayout(parsed, kind);
    if (blocks && blocks.length > 0) {
      const migrated = blocks
        .map(migrateLegacyBlock)
        .filter((b): b is Block => b !== null);
      if (migrated.length > 0) {
        if (isLegacyFocusedMigrationCandidate(kind, migrated)) {
          const focused = defaultLayout(kind);
          await saveLayout(workspaceId, kind, focused);
          return focused;
        }
        return { blocks: migrated };
      }
    }
  } catch {
    /* fall through */
  }
  return defaultLayout(kind);
}

export async function saveLayout(
  workspaceId: string,
  kind: WorkspaceKind,
  layout: Layout
): Promise<void> {
  const blocks = layout.blocks.map(({ restoredTranscript: _restoredTranscript, ...block }) => block);
  const raw = await ipc.workspace.getLayout(workspaceId).catch(() => null);
  const envelope = parseLayoutEnvelope(raw);
  const blocksByKind = layoutBlocksByKind(envelope);
  const persistable: LayoutEnvelope = blocksByKind
    ? {
        ...envelope,
        ...(Array.isArray(envelope.blocks) ? { blocks } : {}),
        blocksByKind: {
          ...blocksByKind,
          [layoutKindKeyForSave(blocksByKind, kind)]: blocks,
        },
      }
    : {
        ...envelope,
        blocks,
      };
  await ipc.workspace.saveLayout(workspaceId, JSON.stringify(persistable)).catch(() => {});
}

export function newBlock(kind: Panel): Block {
  return { id: uuid(), kind };
}

function isLegacyFocusedMigrationCandidate(kind: WorkspaceKind, blocks: Block[]): boolean {
  const expected: Panel[] | null =
    kind === "code"
      ? ["terminal", "tasks", "agent"]
      : kind === "ideas"
        ? ["notes", "agent"]
        : kind === "review" || kind === "build"
          ? ["preview", "agent"]
          : null;
  if (!expected) return false;
  if (blocks.length !== expected.length) return false;
  if (!blocks.every((block, index) => block.kind === expected[index])) return false;
  return blocks.every((block) => {
    const title = block.customTitle?.trim() ?? "";
    return (
      title.length === 0 &&
      !block.fullRowSpan &&
      !block.pin &&
      block.pinFraction === undefined &&
      (block.widthWeight === undefined || block.widthWeight === 1) &&
      (block.heightWeight === undefined || block.heightWeight === 1) &&
      (block.widthFraction === undefined || block.widthFraction === 1)
    );
  });
}

function layoutEnvelope(parsed: unknown): LayoutEnvelope | null {
  return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
    ? (parsed as LayoutEnvelope)
    : null;
}

function parseLayoutEnvelope(raw: string | null): LayoutEnvelope {
  if (!raw) return {};
  try {
    return layoutEnvelope(JSON.parse(raw) as unknown) ?? {};
  } catch {
    return {};
  }
}

function layoutBlocksByKind(envelope: LayoutEnvelope): Record<string, unknown> | null {
  return typeof envelope.blocksByKind === "object" &&
    envelope.blocksByKind !== null &&
    !Array.isArray(envelope.blocksByKind)
    ? (envelope.blocksByKind as Record<string, unknown>)
    : null;
}

function layoutKindKeys(kind: WorkspaceKind): string[] {
  return kind === "review" || kind === "build" ? ["review", "build"] : [kind];
}

function layoutKindKeyForSave(blocksByKind: Record<string, unknown>, kind: WorkspaceKind): string {
  if (kind === "review" || kind === "build") {
    if (Array.isArray(blocksByKind.review)) return "review";
    if (Array.isArray(blocksByKind.build)) return "build";
    return "review";
  }
  return kind;
}
