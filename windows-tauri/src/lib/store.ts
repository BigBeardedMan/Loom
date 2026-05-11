import { create } from "zustand";
import { ipc, type Workspace } from "./ipc";
import {
  loadLayout,
  saveLayout,
  newBlock,
  type Block,
  type Layout,
  defaultLayout,
} from "../modules/workspace/LayoutPersistence";

export type Panel =
  | "terminal"
  | "editor"
  | "tasks"
  | "agent"
  | "notes"
  | "preview"
  | "commands";

type UsageTool = "claude" | "codex" | "gemini" | null;

type Theme = "system" | "light" | "dark";

type AppState = {
  workspaces: Workspace[];
  selectedWorkspaceId: string | null;
  layout: Layout | null;
  isPaletteOpen: boolean;
  isSettingsOpen: boolean;
  selectedUsageTool: UsageTool;
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
  addBlock: (kind: Panel) => Promise<void>;
  removeBlock: (id: string) => Promise<void>;
  reorderBlocks: (newOrder: Block[]) => Promise<void>;
  resetLayout: () => Promise<void>;
  setBlockStatus: (id: string, status: "idle" | "active" | "warning") => void;
  openPalette: () => void;
  closePalette: () => void;
  openSettings: () => void;
  closeSettings: () => void;
  setUsageTool: (t: UsageTool) => void;
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
    set({ selectedWorkspaceId: id });
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

  addBlock: async (kind) => {
    const wsId = get().selectedWorkspaceId;
    const current = get().layout;
    if (!wsId || !current) return;
    const next: Layout = { blocks: [...current.blocks, newBlock(kind)] };
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

  setBlockStatus: (id, status) =>
    set((s) => ({ blockStatus: { ...s.blockStatus, [id]: status } })),

  openPalette: () => set({ isPaletteOpen: true }),
  closePalette: () => set({ isPaletteOpen: false }),
  openSettings: () => set({ isSettingsOpen: true }),
  closeSettings: () => set({ isSettingsOpen: false }),
  setUsageTool: (t) => set({ selectedUsageTool: t }),
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
