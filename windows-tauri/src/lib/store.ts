import { create } from "zustand";
import { ipc, type Workspace } from "./ipc";
import {
  loadLayout,
  saveLayout,
  newBlock,
  type Block,
  type BlockPin,
  type Layout,
  defaultLayout,
} from "../modules/workspace/LayoutPersistence";
import {
  WEIGHT_MIN,
  WEIGHT_MAX,
  PIN_FRACTION_MIN,
  PIN_FRACTION_MAX,
  WIDTH_FRACTION_MIN,
  WIDTH_FRACTION_MAX,
} from "../modules/workspace/deckMetrics";

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

export type Panel =
  | "terminal"
  | "editor"
  | "tasks"
  | "agent"
  | "notes"
  | "preview"
  | "commands";

type UsageTool = "claude" | "codex" | "gemini" | null;
type UsageTimeframe = "day" | "week" | "month" | "year";

type Theme = "system" | "light" | "dark";

type AppState = {
  workspaces: Workspace[];
  selectedWorkspaceId: string | null;
  layout: Layout | null;
  isPaletteOpen: boolean;
  isSettingsOpen: boolean;
  selectedUsageTool: UsageTool;
  usageTimeframe: UsageTimeframe;
  updatePill: { version: string } | null;
  blockStatus: Record<string, "idle" | "active" | "warning">;
  theme: Theme;

  loadWorkspaces: () => Promise<void>;
  selectWorkspace: (id: string | null) => void;
  createWorkspace: (
    name: string,
    folderPath: string,
    color: Workspace["colorName"],
    kind: Workspace["kindRaw"]
  ) => Promise<Workspace>;
  deleteWorkspace: (id: string) => Promise<void>;
  renameWorkspace: (id: string, name: string) => Promise<void>;
  addBlock: (kind: Panel) => Promise<void>;
  removeBlock: (id: string) => Promise<void>;
  reorderBlocks: (newOrder: Block[]) => Promise<void>;
  swapBlocks: (a: string, b: string) => Promise<void>;
  resetLayout: () => Promise<void>;
  updateBlock: (id: string, patch: Partial<Block>) => Promise<void>;
  setBlockPin: (id: string, pin: BlockPin | undefined) => Promise<void>;
  toggleFullRow: (id: string) => Promise<void>;
  applyBlockWeights: (
    updates: { id: string; widthWeight?: number; heightWeight?: number }[]
  ) => Promise<void>;
  setPinFraction: (id: string, fraction: number) => Promise<void>;
  setWidthFraction: (id: string, fraction: number) => Promise<void>;
  resetSeam: (ids: string[]) => Promise<void>;
  resetAllWeights: () => Promise<void>;
  setBlockStatus: (id: string, status: "idle" | "active" | "warning") => void;
  openPalette: () => void;
  closePalette: () => void;
  openSettings: () => void;
  closeSettings: () => void;
  setUsageTool: (t: UsageTool) => void;
  setUsageTimeframe: (tf: UsageTimeframe) => void;
  setUpdatePill: (info: { version: string } | null) => void;
  setTheme: (t: Theme) => void;
};

const SELECTED_WS_KEY = "loom.selectedWorkspaceId";

export const useApp = create<AppState>((set, get) => ({
  workspaces: [],
  selectedWorkspaceId: localStorage.getItem(SELECTED_WS_KEY),
  layout: null,
  isPaletteOpen: false,
  isSettingsOpen: false,
  selectedUsageTool: null,
  usageTimeframe: (localStorage.getItem("loom.usage.timeframe") as UsageTimeframe) || "day",
  updatePill: null,
  blockStatus: {},
  theme: (localStorage.getItem("loom.theme") as Theme) || "system",

  loadWorkspaces: async () => {
    const list = await ipc.workspace.list();
    set({ workspaces: list });
    const current = get().selectedWorkspaceId;
    const valid = list.find((w) => w.id === current);
    const target = valid?.id ?? list[0]?.id ?? null;
    if (target) {
      const ws = list.find((w) => w.id === target)!;
      const layout = await loadLayout(ws.id, ws.kindRaw);
      set({ selectedWorkspaceId: target, layout });
      if (target) localStorage.setItem(SELECTED_WS_KEY, target);
    } else {
      set({ selectedWorkspaceId: null, layout: null });
    }
  },

  selectWorkspace: async (id) => {
    // Picking a workspace always lands on the deck. Without clearing the
    // usage selection, the workspace swap happens silently behind the usage
    // dashboard and the click feels like a no-op until the user toggles the
    // pill off.
    set({ selectedWorkspaceId: id, selectedUsageTool: id ? null : get().selectedUsageTool });
    if (id) {
      localStorage.setItem(SELECTED_WS_KEY, id);
      ipc.workspace.touchLastOpened(id).catch(() => {});
      const ws = get().workspaces.find((w) => w.id === id);
      if (ws) {
        const layout = await loadLayout(ws.id, ws.kindRaw);
        set({ layout });
      }
    } else {
      localStorage.removeItem(SELECTED_WS_KEY);
      set({ layout: null });
    }
  },

  createWorkspace: async (name, folderPath, colorName, kindRaw) => {
    const ws = await ipc.workspace.create({
      name,
      folderPath,
      colorName,
      kindRaw,
    });
    const layout = defaultLayout(kindRaw);
    await saveLayout(ws.id, layout);
    set((s) => ({
      workspaces: [ws, ...s.workspaces],
      selectedWorkspaceId: ws.id,
      layout,
    }));
    localStorage.setItem(SELECTED_WS_KEY, ws.id);
    return ws;
  },

  deleteWorkspace: async (id) => {
    await ipc.workspace.delete(id);
    set((s) => {
      const remaining = s.workspaces.filter((w) => w.id !== id);
      const nextId =
        s.selectedWorkspaceId === id
          ? remaining[0]?.id ?? null
          : s.selectedWorkspaceId;
      if (nextId) localStorage.setItem(SELECTED_WS_KEY, nextId);
      else localStorage.removeItem(SELECTED_WS_KEY);
      return {
        workspaces: remaining,
        selectedWorkspaceId: nextId,
        layout: null,
      };
    });
    const next = get().selectedWorkspaceId;
    if (next) {
      const ws = get().workspaces.find((w) => w.id === next);
      if (ws) {
        const layout = await loadLayout(ws.id, ws.kindRaw);
        set({ layout });
      }
    }
  },

  renameWorkspace: async (id, name) => {
    const trimmed = name.trim();
    if (!trimmed) return;
    const updated = await ipc.workspace.update(id, { name: trimmed }).catch(() => null);
    if (!updated) return;
    set((s) => ({
      workspaces: s.workspaces.map((w) => (w.id === id ? updated : w)),
    }));
  },

  addBlock: async (kind) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const block = newBlock(kind);
    if (kind === "preview") {
      block.autoPreviewIndex = current.blocks.filter((b) => b.kind === "preview").length;
    }
    const next: Layout = { blocks: [...current.blocks, block] };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  removeBlock: async (id) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.filter((b) => b.id !== id),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  reorderBlocks: async (newOrder) => {
    const wsId = get().selectedWorkspaceId;
    if (!wsId) return;
    const next: Layout = { blocks: newOrder };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  resetLayout: async () => {
    const wsId = get().selectedWorkspaceId;
    const ws = get().workspaces.find((w) => w.id === wsId);
    if (!wsId || !ws) return;
    const layout = defaultLayout(ws.kindRaw);
    set({ layout });
    await saveLayout(wsId, layout);
  },

  updateBlock: async (id, patch) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.map((b) => (b.id === id ? { ...b, ...patch } : b)),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  setBlockPin: async (id, pin) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.map((b) => {
        if (b.id === id) {
          // Re-pinning to the same edge keeps the current pinFraction; any
          // change clears it so the new edge starts at 50%.
          const sameEdge = b.pin === pin;
          return {
            ...b,
            pin,
            pinFraction: sameEdge ? b.pinFraction : undefined,
          };
        }
        // Only one block can be pinned at a time.
        if (pin && b.pin) return { ...b, pin: undefined, pinFraction: undefined };
        return b;
      }),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  toggleFullRow: async (id) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.map((b) =>
        b.id === id ? { ...b, fullRowSpan: !b.fullRowSpan } : b
      ),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  swapBlocks: async (a, b) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const blocks = [...current.blocks];
    const i = blocks.findIndex((x) => x.id === a);
    const j = blocks.findIndex((x) => x.id === b);
    if (i < 0 || j < 0 || i === j) return;
    // Swapping clears pins on both ends so the user can re-pin intentionally.
    const ai = { ...blocks[i], pin: undefined, pinFraction: undefined };
    const aj = { ...blocks[j], pin: undefined, pinFraction: undefined };
    blocks[i] = aj;
    blocks[j] = ai;
    const next: Layout = { blocks };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  applyBlockWeights: async (updates) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const updateMap = new Map(updates.map((u) => [u.id, u]));
    const next: Layout = {
      blocks: current.blocks.map((b) => {
        const u = updateMap.get(b.id);
        if (!u) return b;
        const patch: Partial<Block> = {};
        if (u.widthWeight !== undefined) {
          patch.widthWeight = clamp(u.widthWeight, WEIGHT_MIN, WEIGHT_MAX);
        }
        if (u.heightWeight !== undefined) {
          patch.heightWeight = clamp(u.heightWeight, WEIGHT_MIN, WEIGHT_MAX);
        }
        return { ...b, ...patch };
      }),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  setPinFraction: async (id, fraction) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.map((b) =>
        b.id === id && b.pin
          ? { ...b, pinFraction: clamp(fraction, PIN_FRACTION_MIN, PIN_FRACTION_MAX) }
          : b
      ),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  setWidthFraction: async (id, fraction) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.map((b) =>
        b.id === id
          ? { ...b, widthFraction: clamp(fraction, WIDTH_FRACTION_MIN, WIDTH_FRACTION_MAX) }
          : b
      ),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  resetSeam: async (ids) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const idSet = new Set(ids);
    const next: Layout = {
      blocks: current.blocks.map((b) =>
        idSet.has(b.id) ? { ...b, widthWeight: 1.0, heightWeight: 1.0, widthFraction: 1.0 } : b
      ),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  resetAllWeights: async () => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = {
      blocks: current.blocks.map((b) => ({
        ...b,
        widthWeight: 1.0,
        heightWeight: 1.0,
        pinFraction: undefined,
        widthFraction: 1.0,
      })),
    };
    set({ layout: next });
    await saveLayout(wsId, next);
  },

  setBlockStatus: (id, status) =>
    set((s) => ({ blockStatus: { ...s.blockStatus, [id]: status } })),

  openPalette: () => set({ isPaletteOpen: true }),
  closePalette: () => set({ isPaletteOpen: false }),
  openSettings: () => set({ isSettingsOpen: true }),
  closeSettings: () => set({ isSettingsOpen: false }),
  setUsageTool: (t) => set({ selectedUsageTool: t }),
  setUsageTimeframe: (tf) => {
    localStorage.setItem("loom.usage.timeframe", tf);
    set({ usageTimeframe: tf });
  },
  setUpdatePill: (info) => set({ updatePill: info }),
  setTheme: (t) => {
    localStorage.setItem("loom.theme", t);
    if (t === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", t);
    set({ theme: t });
  },
}));

export const workspaceColorClass: Record<Workspace["colorName"], string> = {
  orange: "bg-[var(--color-ws-orange)]",
  green: "bg-[var(--color-ws-green)]",
  blue: "bg-[var(--color-ws-blue)]",
  pink: "bg-[var(--color-ws-pink)]",
  yellow: "bg-[var(--color-ws-yellow)]",
  purple: "bg-[var(--color-ws-purple)]",
};

export const workspaceKindLabel: Record<Workspace["kindRaw"], string> = {
  code: "Prompt",
  ideas: "Ideas",
  review: "Review",
  build: "Review",
};
