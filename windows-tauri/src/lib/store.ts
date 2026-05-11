import { create } from "zustand";
import { ipc, type Workspace } from "./ipc";

export type Panel =
  | "terminal"
  | "editor"
  | "tasks"
  | "agent"
  | "notes"
  | "preview"
  | "commands";

type AppState = {
  workspaces: Workspace[];
  selectedWorkspaceId: string | null;
  activePanels: Panel[];
  isPaletteOpen: boolean;
  isSettingsOpen: boolean;
  updatePill: { version: string } | null;

  loadWorkspaces: () => Promise<void>;
  selectWorkspace: (id: string | null) => void;
  createWorkspace: (
    name: string,
    folderPath: string,
    color: Workspace["colorName"],
    kind: Workspace["kindRaw"]
  ) => Promise<Workspace>;
  deleteWorkspace: (id: string) => Promise<void>;
  setActivePanels: (panels: Panel[]) => void;
  openPalette: () => void;
  closePalette: () => void;
  openSettings: () => void;
  closeSettings: () => void;
  setUpdatePill: (info: { version: string } | null) => void;
};

const KIND_PANELS: Record<Workspace["kindRaw"], Panel[]> = {
  code: ["terminal", "editor", "tasks", "agent", "commands"],
  ideas: ["notes", "agent"],
  review: ["preview", "agent"],
  build: ["preview", "agent"],
};

export const useApp = create<AppState>((set, get) => ({
  workspaces: [],
  selectedWorkspaceId: null,
  activePanels: ["terminal", "editor", "tasks", "agent"],
  isPaletteOpen: false,
  isSettingsOpen: false,
  updatePill: null,

  loadWorkspaces: async () => {
    const list = await ipc.workspace.list();
    set({ workspaces: list });
    if (!get().selectedWorkspaceId && list.length > 0) {
      set({
        selectedWorkspaceId: list[0].id,
        activePanels: KIND_PANELS[list[0].kindRaw] ?? KIND_PANELS.code,
      });
    }
  },
  selectWorkspace: (id) => {
    const ws = get().workspaces.find((w) => w.id === id);
    set({
      selectedWorkspaceId: id,
      activePanels: ws ? KIND_PANELS[ws.kindRaw] ?? KIND_PANELS.code : [],
    });
    if (id) ipc.workspace.touchLastOpened(id).catch(() => {});
  },
  createWorkspace: async (name, folderPath, colorName, kindRaw) => {
    const ws = await ipc.workspace.create({
      name,
      folderPath,
      colorName,
      kindRaw,
    });
    set((s) => ({
      workspaces: [ws, ...s.workspaces],
      selectedWorkspaceId: ws.id,
      activePanels: KIND_PANELS[ws.kindRaw] ?? KIND_PANELS.code,
    }));
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
      const nextWs = remaining.find((w) => w.id === nextId);
      return {
        workspaces: remaining,
        selectedWorkspaceId: nextId,
        activePanels: nextWs
          ? KIND_PANELS[nextWs.kindRaw] ?? KIND_PANELS.code
          : [],
      };
    });
  },
  setActivePanels: (panels) => set({ activePanels: panels }),
  openPalette: () => set({ isPaletteOpen: true }),
  closePalette: () => set({ isPaletteOpen: false }),
  openSettings: () => set({ isSettingsOpen: true }),
  closeSettings: () => set({ isSettingsOpen: false }),
  setUpdatePill: (info) => set({ updatePill: info }),
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
