// Mirrors Loom/Workspace/WorkspaceView.swift (DeckMetrics) and
// Loom/Workspace/WorkspaceLayout.swift (capacity, weights). Computes
// per-block frames, draggable divider rects, and drop targets for a deck of
// blocks under a given container size. Pure functions; no React.

import type { Block, BlockPin } from "./LayoutPersistence";

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type DeckDividerKind =
  | { kind: "columnGap"; leftID: string; rightID: string }
  | { kind: "rowGap"; topAnchorID: string; bottomAnchorID: string }
  | { kind: "pinSplit"; pinnedID: string; axis: "horizontal" | "vertical" }
  | { kind: "trailingEdge"; blockID: string };

export interface DeckDivider {
  kind: DeckDividerKind;
  rect: Rect;
  isVertical: boolean;
}

export type DropTarget =
  | { kind: "pin"; pin: BlockPin }
  | { kind: "swap"; id: string }
  | null;

export interface DeckMetrics {
  containerSize: { width: number; height: number };
  gap: number;
  frames: Map<string, Rect>;
  /// Pre-`widthFraction` cell width for each block. Equal to `frame.width`
  /// when the block fills its cell; larger when it has been shrunk via the
  /// trailing-edge handle. Used by the trailing-edge drag handler.
  cellWidths: Map<string, number>;
  pinnedID: string | null;
  dividers: DeckDivider[];
}

export const DECK_GAP = 12;
export const MIN_BLOCK_WIDTH = 140;
export const MIN_BLOCK_HEIGHT = 160;
export const WEIGHT_MIN = 0.2;
export const WEIGHT_MAX = 5.0;
export const PIN_FRACTION_MIN = 0.2;
export const PIN_FRACTION_MAX = 0.8;
export const WIDTH_FRACTION_MIN = 0.3;
export const WIDTH_FRACTION_MAX = 1.0;

export function clampWidthFraction(f: number): number {
  return Math.min(Math.max(f, WIDTH_FRACTION_MIN), WIDTH_FRACTION_MAX);
}

export function clampWeight(w: number): number {
  return Math.min(Math.max(w, WEIGHT_MIN), WEIGHT_MAX);
}

export function clampPinFraction(f: number): number {
  return Math.min(Math.max(f, PIN_FRACTION_MIN), PIN_FRACTION_MAX);
}

export function isCornerPin(pin: BlockPin): boolean {
  return pin === "topLeft" || pin === "topRight" || pin === "bottomLeft" || pin === "bottomRight";
}

/// Capacity ladder mirrors WorkspaceLayout.capacity on macOS.
export function deckCapacity(size: { width: number; height: number }): { cols: number; rows: number } {
  if (size.width >= 1800 && size.height >= 900) return { cols: 4, rows: 3 };
  if (size.width >= 1300) return { cols: 4, rows: 2 };
  if (size.width >= 900) return { cols: 3, rows: 2 };
  return { cols: 2, rows: 2 };
}

/// Pick the column count that produces the most balanced cell aspect ratio
/// for the given block count and container.
export function balancedCols(
  count: number,
  capCols: number,
  capRows: number,
  size: { width: number; height: number }
): number {
  const target = 1.35;
  const w = Math.max(size.width, 1);
  const h = Math.max(size.height, 1);
  let bestCols = 1;
  let bestScore = Number.POSITIVE_INFINITY;
  const maxC = Math.max(capCols, 1);
  for (let cols = 1; cols <= maxC; cols++) {
    const rows = Math.max(1, Math.ceil(count / cols));
    if (rows > capRows && cols < capCols) continue;
    const cellAspect = w / cols / (h / rows);
    const score = Math.abs(Math.log(cellAspect / target));
    if (score < bestScore) {
      bestScore = score;
      bestCols = cols;
    }
  }
  return bestCols;
}

function pinFrame(
  pin: BlockPin,
  deckSize: { width: number; height: number },
  gap: number,
  fraction: number
): Rect {
  const leftW = (deckSize.width - gap) * fraction;
  const rightW = deckSize.width - gap - leftW;
  const topH = (deckSize.height - gap) * fraction;
  const bottomH = deckSize.height - gap - topH;
  switch (pin) {
    case "left":
      return { x: 0, y: 0, width: leftW, height: deckSize.height };
    case "right":
      return { x: leftW + gap, y: 0, width: rightW, height: deckSize.height };
    case "top":
      return { x: 0, y: 0, width: deckSize.width, height: topH };
    case "bottom":
      return { x: 0, y: topH + gap, width: deckSize.width, height: bottomH };
    case "topLeft":
      return { x: 0, y: 0, width: leftW, height: topH };
    case "topRight":
      return { x: leftW + gap, y: 0, width: rightW, height: topH };
    case "bottomLeft":
      return { x: 0, y: topH + gap, width: leftW, height: bottomH };
    case "bottomRight":
      return { x: leftW + gap, y: topH + gap, width: rightW, height: bottomH };
  }
}

function complementFrame(
  pin: BlockPin,
  deckSize: { width: number; height: number },
  gap: number,
  fraction: number
): Rect {
  const leftW = (deckSize.width - gap) * fraction;
  const rightW = deckSize.width - gap - leftW;
  const topH = (deckSize.height - gap) * fraction;
  const bottomH = deckSize.height - gap - topH;
  switch (pin) {
    case "left":
      return { x: leftW + gap, y: 0, width: rightW, height: deckSize.height };
    case "right":
      return { x: 0, y: 0, width: leftW, height: deckSize.height };
    case "top":
      return { x: 0, y: topH + gap, width: deckSize.width, height: bottomH };
    case "bottom":
      return { x: 0, y: 0, width: deckSize.width, height: topH };
    default:
      return { x: 0, y: 0, width: deckSize.width, height: deckSize.height };
  }
}

function cornerComplementZones(
  pin: BlockPin,
  deckSize: { width: number; height: number },
  gap: number,
  fraction: number
): { neighbor: Rect; wideRow: Rect } {
  const leftW = (deckSize.width - gap) * fraction;
  const rightW = deckSize.width - gap - leftW;
  const topH = (deckSize.height - gap) * fraction;
  const bottomH = deckSize.height - gap - topH;
  switch (pin) {
    case "topLeft":
      return {
        neighbor: { x: leftW + gap, y: 0, width: rightW, height: topH },
        wideRow: { x: 0, y: topH + gap, width: deckSize.width, height: bottomH },
      };
    case "topRight":
      return {
        neighbor: { x: 0, y: 0, width: leftW, height: topH },
        wideRow: { x: 0, y: topH + gap, width: deckSize.width, height: bottomH },
      };
    case "bottomLeft":
      return {
        neighbor: { x: leftW + gap, y: topH + gap, width: rightW, height: bottomH },
        wideRow: { x: 0, y: 0, width: deckSize.width, height: topH },
      };
    case "bottomRight":
      return {
        neighbor: { x: 0, y: topH + gap, width: leftW, height: bottomH },
        wideRow: { x: 0, y: 0, width: deckSize.width, height: topH },
      };
    default:
      return {
        neighbor: { x: 0, y: 0, width: 0, height: 0 },
        wideRow: { x: 0, y: 0, width: 0, height: 0 },
      };
  }
}

function computeEvenRow(
  blocks: Block[],
  area: Rect,
  gap: number
): { frames: Map<string, Rect>; cellWidths: Map<string, number>; dividers: DeckDivider[] } {
  const frames = new Map<string, Rect>();
  const cellWidths = new Map<string, number>();
  const dividers: DeckDivider[] = [];
  if (blocks.length === 0 || area.width <= 0 || area.height <= 0) {
    return { frames, cellWidths, dividers };
  }
  const cap = deckCapacity({ width: area.width, height: area.height });
  const cols = balancedCols(blocks.length, cap.cols, cap.rows, {
    width: area.width,
    height: area.height,
  });

  // Pack blocks into rows. `fullRowSpan` blocks always take their own row.
  const rows: Block[][] = [];
  let i = 0;
  while (i < blocks.length) {
    if (blocks[i].fullRowSpan) {
      rows.push([blocks[i]]);
      i += 1;
    } else {
      const chunk: Block[] = [];
      while (i < blocks.length && chunk.length < cols && !blocks[i].fullRowSpan) {
        chunk.push(blocks[i]);
        i += 1;
      }
      rows.push(chunk);
    }
  }

  const totalGapY = Math.max(0, rows.length - 1) * gap;
  const usableH = Math.max(0, area.height - totalGapY);
  const rowWeights = rows.map((r) => r[0]?.heightWeight ?? 1.0);
  const rowWeightSum = Math.max(rowWeights.reduce((a, b) => a + b, 0), 0.0001);
  const rowHeights = rowWeights.map((w) => Math.max(MIN_BLOCK_HEIGHT, (usableH * w) / rowWeightSum));

  let cursorY = area.y;
  for (let r = 0; r < rows.length; r++) {
    const row = rows[r];
    const totalGapX = Math.max(0, row.length - 1) * gap;
    const usableW = Math.max(0, area.width - totalGapX);
    const rowH = rowHeights[r];

    const weights = row.map((b) => b.widthWeight ?? 1.0);
    const weightSum = Math.max(weights.reduce((a, b) => a + b, 0), 0.0001);
    const widths = weights.map((w) => Math.max(MIN_BLOCK_WIDTH, (usableW * w) / weightSum));

    let cursorX = area.x;
    for (let p = 0; p < row.length; p++) {
      const block = row[p];
      const cellW = widths[p];
      const isLast = p === row.length - 1;
      // widthFraction only narrows the LAST block in a row. Earlier blocks
      // get the columnGap as their resize control; introducing a second
      // handle there would overlap.
      const frac = isLast ? clampWidthFraction(block.widthFraction ?? 1.0) : 1.0;
      const blockW = Math.max(MIN_BLOCK_WIDTH, cellW * frac);
      frames.set(block.id, { x: cursorX, y: cursorY, width: blockW, height: rowH });
      cellWidths.set(block.id, cellW);
      if (!isLast) {
        const dividerX = cursorX + cellW;
        dividers.push({
          kind: { kind: "columnGap", leftID: block.id, rightID: row[p + 1].id },
          rect: { x: dividerX, y: cursorY, width: gap, height: rowH },
          isVertical: true,
        });
      } else {
        // Trailing-edge handle: flush against block's right edge, 12pt wide.
        // The only horizontal control in a stacked single-block row.
        dividers.push({
          kind: { kind: "trailingEdge", blockID: block.id },
          rect: { x: cursorX + blockW, y: cursorY, width: gap, height: rowH },
          isVertical: true,
        });
      }
      cursorX += cellW + gap;
    }

    if (r < rows.length - 1) {
      const dividerY = cursorY + rowH;
      dividers.push({
        kind: {
          kind: "rowGap",
          topAnchorID: row[0].id,
          bottomAnchorID: rows[r + 1][0].id,
        },
        rect: { x: area.x, y: dividerY, width: area.width, height: gap },
        isVertical: false,
      });
    }
    cursorY += rowH + gap;
  }
  return { frames, cellWidths, dividers };
}

function pinDividers(
  pin: BlockPin,
  deckSize: { width: number; height: number },
  gap: number,
  fraction: number,
  pinnedID: string
): DeckDivider[] {
  const leftW = (deckSize.width - gap) * fraction;
  const topH = (deckSize.height - gap) * fraction;
  switch (pin) {
    case "left":
    case "right": {
      const x = pin === "left" ? leftW : deckSize.width - gap - leftW;
      return [
        {
          kind: { kind: "pinSplit", pinnedID, axis: "horizontal" },
          rect: { x, y: 0, width: gap, height: deckSize.height },
          isVertical: true,
        },
      ];
    }
    case "top":
    case "bottom": {
      const y = pin === "top" ? topH : deckSize.height - gap - topH;
      return [
        {
          kind: { kind: "pinSplit", pinnedID, axis: "vertical" },
          rect: { x: 0, y, width: deckSize.width, height: gap },
          isVertical: false,
        },
      ];
    }
    case "topLeft":
      return [
        {
          kind: { kind: "pinSplit", pinnedID, axis: "horizontal" },
          rect: { x: leftW, y: 0, width: gap, height: topH },
          isVertical: true,
        },
        {
          kind: { kind: "pinSplit", pinnedID, axis: "vertical" },
          rect: { x: 0, y: topH, width: deckSize.width, height: gap },
          isVertical: false,
        },
      ];
    case "topRight":
      return [
        {
          kind: { kind: "pinSplit", pinnedID, axis: "horizontal" },
          rect: { x: deckSize.width - gap - leftW, y: 0, width: gap, height: topH },
          isVertical: true,
        },
        {
          kind: { kind: "pinSplit", pinnedID, axis: "vertical" },
          rect: { x: 0, y: topH, width: deckSize.width, height: gap },
          isVertical: false,
        },
      ];
    case "bottomLeft":
      return [
        {
          kind: { kind: "pinSplit", pinnedID, axis: "horizontal" },
          rect: { x: leftW, y: topH + gap, width: gap, height: deckSize.height - gap - topH },
          isVertical: true,
        },
        {
          kind: { kind: "pinSplit", pinnedID, axis: "vertical" },
          rect: { x: 0, y: topH, width: deckSize.width, height: gap },
          isVertical: false,
        },
      ];
    case "bottomRight":
      return [
        {
          kind: { kind: "pinSplit", pinnedID, axis: "horizontal" },
          rect: {
            x: deckSize.width - gap - leftW,
            y: topH + gap,
            width: gap,
            height: deckSize.height - gap - topH,
          },
          isVertical: true,
        },
        {
          kind: { kind: "pinSplit", pinnedID, axis: "vertical" },
          rect: { x: 0, y: topH, width: deckSize.width, height: gap },
          isVertical: false,
        },
      ];
  }
}

export function computeDeckMetrics(
  size: { width: number; height: number },
  blocks: Block[]
): DeckMetrics {
  const gap = DECK_GAP;
  const frames = new Map<string, Rect>();
  const cellWidths = new Map<string, number>();
  let pinnedID: string | null = null;
  const dividers: DeckDivider[] = [];

  if (blocks.length === 1) {
    const only = blocks[0];
    const cellW = size.width;
    const frac = clampWidthFraction(only.widthFraction ?? 1.0);
    const blockW = Math.max(MIN_BLOCK_WIDTH, cellW * frac);
    frames.set(only.id, { x: 0, y: 0, width: blockW, height: size.height });
    cellWidths.set(only.id, cellW);
    dividers.push({
      kind: { kind: "trailingEdge", blockID: only.id },
      rect: { x: blockW, y: 0, width: gap, height: size.height },
      isVertical: true,
    });
  } else {
    const pinned = blocks.find((b) => b.pin);
    if (pinned && pinned.pin) {
      const fraction = pinned.pinFraction ?? 0.5;
      const pframe = pinFrame(pinned.pin, size, gap, fraction);
      frames.set(pinned.id, pframe);
      cellWidths.set(pinned.id, pframe.width);
      pinnedID = pinned.id;
      const free = blocks.filter((b) => b.id !== pinned.id);
      if (isCornerPin(pinned.pin)) {
        const zones = cornerComplementZones(pinned.pin, size, gap, fraction);
        if (free.length > 0) {
          frames.set(free[0].id, zones.neighbor);
          cellWidths.set(free[0].id, zones.neighbor.width);
          const tail = free.slice(1);
          const result = computeEvenRow(tail, zones.wideRow, gap);
          result.frames.forEach((r, id) => frames.set(id, r));
          result.cellWidths.forEach((w, id) => cellWidths.set(id, w));
          dividers.push(...result.dividers);
        }
      } else {
        const freeArea = complementFrame(pinned.pin, size, gap, fraction);
        const result = computeEvenRow(free, freeArea, gap);
        result.frames.forEach((r, id) => frames.set(id, r));
        result.cellWidths.forEach((w, id) => cellWidths.set(id, w));
        dividers.push(...result.dividers);
      }
      dividers.push(...pinDividers(pinned.pin, size, gap, fraction, pinned.id));
    } else {
      const result = computeEvenRow(blocks, { x: 0, y: 0, width: size.width, height: size.height }, gap);
      result.frames.forEach((r, id) => frames.set(id, r));
      result.cellWidths.forEach((w, id) => cellWidths.set(id, w));
      dividers.push(...result.dividers);
    }
  }

  return { containerSize: size, gap, frames, cellWidths, pinnedID, dividers };
}

/// Decide what should happen if the user drops the dragged block at the
/// given point. Corner zones beat edge zones beat swap targets, mirroring
/// macOS `DeckMetrics.dropTarget`.
export function dropTargetAt(
  metrics: DeckMetrics,
  point: { x: number; y: number },
  draggedID: string
): DropTarget {
  const cs = metrics.containerSize;
  const xMargin = Math.max(60, cs.width * 0.18);
  const yMargin = Math.max(60, cs.height * 0.18);
  const nearLeft = point.x < xMargin;
  const nearRight = cs.width - point.x < xMargin;
  const nearTop = point.y < yMargin;
  const nearBottom = cs.height - point.y < yMargin;
  if (nearTop && nearLeft) return { kind: "pin", pin: "topLeft" };
  if (nearTop && nearRight) return { kind: "pin", pin: "topRight" };
  if (nearBottom && nearLeft) return { kind: "pin", pin: "bottomLeft" };
  if (nearBottom && nearRight) return { kind: "pin", pin: "bottomRight" };
  if (nearLeft) return { kind: "pin", pin: "left" };
  if (nearRight) return { kind: "pin", pin: "right" };
  if (nearTop) return { kind: "pin", pin: "top" };
  if (nearBottom) return { kind: "pin", pin: "bottom" };
  for (const [id, rect] of metrics.frames) {
    if (id === draggedID) continue;
    if (
      point.x >= rect.x &&
      point.x <= rect.x + rect.width &&
      point.y >= rect.y &&
      point.y <= rect.y + rect.height
    ) {
      return { kind: "swap", id };
    }
  }
  return null;
}

export function pinPreviewRect(
  pin: BlockPin,
  deckSize: { width: number; height: number },
  fraction = 0.5
): Rect {
  return pinFrame(pin, deckSize, DECK_GAP, fraction);
}

export function pinDragSign(pin: BlockPin, axis: "horizontal" | "vertical"): number {
  if (axis === "horizontal") {
    if (pin === "left" || pin === "topLeft" || pin === "bottomLeft") return 1;
    if (pin === "right" || pin === "topRight" || pin === "bottomRight") return -1;
    return 1;
  }
  if (pin === "top" || pin === "topLeft" || pin === "topRight") return 1;
  if (pin === "bottom" || pin === "bottomLeft" || pin === "bottomRight") return -1;
  return 1;
}
