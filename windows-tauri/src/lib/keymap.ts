// Mirrors the macOS Loom keyboard shortcut surface.
// Single central place that the App-level keydown handler reads from.

import { useEffect } from "react";
import { useApp, type Panel, type RightRailTab } from "./store";
import { ipc, type WorkspaceKind } from "./ipc";
import { ROOM_KINDS, ROOM_META, panelsForKind, workspaceMatchesKind } from "./commands";
import { LOOM_REFRESH_RUNS } from "./events";

type Binding = {
  combo: string;
  description: string;
  run: () => void;
};

function matches(e: KeyboardEvent, combo: string): boolean {
  const parts = combo.toLowerCase().split("+");
  const ctrl = parts.includes("ctrl");
  const shift = parts.includes("shift");
  const alt = parts.includes("alt");
  const key = parts[parts.length - 1];
  const mod = e.ctrlKey || e.metaKey;
  if (ctrl && !mod) return false;
  if (shift !== e.shiftKey) return false;
  if (alt !== e.altKey) return false;
  if (e.key.toLowerCase() !== key) return false;
  return true;
}

export function useGlobalKeymap() {
  const openPalette = useApp((s) => s.openPalette);
  const closePalette = useApp((s) => s.closePalette);
  const isPaletteOpen = useApp((s) => s.isPaletteOpen);
  const addBlock = useApp((s) => s.addBlock);
  const removeBlock = useApp((s) => s.removeBlock);
  const layout = useApp((s) => s.layout);
  const paneCapacityLimit = useApp((s) => s.paneCapacityLimit);
  const workspaces = useApp((s) => s.workspaces);
  const selectedWorkspaceId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const updateBlock = useApp((s) => s.updateBlock);
  const setTheme = useApp((s) => s.setTheme);
  const theme = useApp((s) => s.theme);
  const activeBlockId = useApp((s) => s.activeBlockId);
  const toggleRightRail = useApp((s) => s.toggleRightRail);
  const setRightRailTab = useApp((s) => s.setRightRailTab);

  useEffect(() => {
    const selectedBlockId =
      activeBlockId && layout?.blocks.some((block) => block.id === activeBlockId)
        ? activeBlockId
        : undefined;
    const focusedBlockId = (() => {
      if (selectedBlockId) return selectedBlockId;
      return layout?.blocks[0]?.id;
    })();
    const selectedWorkspace = workspaces.find((w) => w.id === selectedWorkspaceId);
    const canAddPane = !layout || paneCapacityLimit === null || layout.blocks.length < paneCapacityLimit;
    const openWorkflow = (kind: WorkspaceKind, tab: RightRailTab) => {
      const ws = workspaces.find((workspace) => workspaceMatchesKind(workspace, kind));
      if (ws) selectWorkspace(ws.id);
      setRightRailTab(tab);
      window.dispatchEvent(new Event(LOOM_REFRESH_RUNS));
    };

    const bindings: Binding[] = [
      {
        combo: "ctrl+k",
        description: "Toggle command palette",
        run: () => (isPaletteOpen ? closePalette() : openPalette()),
      },
      {
        combo: "ctrl+t",
        description: "Add Terminal pane",
        run: () => {
          if (canAddPane) addBlock("terminal");
        },
      },
      {
        combo: "ctrl+w",
        description: "Close selected pane",
        run: () => {
          const target =
            layout?.blocks.find((block) => block.id === selectedBlockId) ??
            layout?.blocks[layout.blocks.length - 1];
          if (target) removeBlock(target.id);
        },
      },
      {
        combo: "ctrl+n",
        description: "New workspace",
        run: () => openPalette(),
      },
      {
        combo: "ctrl+shift+o",
        description: "Switch to previous workspace",
        run: () => {
          if (workspaces.length < 2) return;
          const idx = workspaces.findIndex((w) => w.id === selectedWorkspaceId);
          if (idx < 0) {
            selectWorkspace(workspaces[0].id);
            return;
          }
          const prev = workspaces[(idx - 1 + workspaces.length) % workspaces.length];
          selectWorkspace(prev.id);
        },
      },
      {
        combo: "ctrl+shift+n",
        description: "Open new Loom window",
        run: () => {
          ipc.window.open(selectedWorkspaceId ?? undefined).catch(() => {});
        },
      },
      {
        combo: "ctrl+shift+l",
        description: "Cycle theme",
        run: () =>
          setTheme(
            theme === "system" ? "light" : theme === "light" ? "dark" : "system"
          ),
      },
      {
        combo: "ctrl+alt+f",
        description: "Toggle full-row span on selected pane",
        run: () => {
          if (!focusedBlockId || !layout) return;
          const blk = layout.blocks.find((b) => b.id === focusedBlockId);
          if (!blk) return;
          updateBlock(blk.id, { fullRowSpan: !blk.fullRowSpan });
        },
      },
      {
        combo: "ctrl+alt+i",
        description: "Toggle inspector",
        run: () => toggleRightRail(),
      },
      {
        combo: "ctrl+alt+r",
        description: "Refresh Runs",
        run: () => {
          setRightRailTab("timeline");
          window.dispatchEvent(new Event(LOOM_REFRESH_RUNS));
        },
      },
      {
        combo: "ctrl+alt+5",
        description: "Open Runs timeline",
        run: () => openWorkflow("runs", "timeline"),
      },
      {
        combo: "ctrl+alt+6",
        description: "Open Review queue",
        run: () => openWorkflow("review", "diff"),
      },
      {
        combo: "ctrl+alt+7",
        description: "Open Project memory",
        run: () => setRightRailTab("memory"),
      },
    ];

    // Ctrl+1..9 → jump to workspace n
    for (let i = 0; i < 9; i++) {
      bindings.push({
        combo: `ctrl+${i + 1}`,
        description: `Switch to workspace ${i + 1}`,
        run: () => {
          const ws = workspaces[i];
          if (ws) selectWorkspace(ws.id);
        },
      });
    }

    // Ctrl+Alt+1..4 → jump to canonical rooms: Prompt, Ideas, Review, Runs.
    ROOM_KINDS.forEach((kind, i) => {
      bindings.push({
        combo: `ctrl+alt+${i + 1}`,
        description: `Open ${ROOM_META[kind].label} room`,
        run: () => {
          const ws = workspaces.find((workspace) => workspaceMatchesKind(workspace, kind));
          if (ws) selectWorkspace(ws.id);
        },
      });
    });

    // Ctrl+Shift+1..9 -> add pane of nth kind for the active workspace.
    panelsForKind(selectedWorkspace?.kindRaw).forEach((kind, i) => {
      bindings.push({
        combo: `ctrl+shift+${i + 1}`,
        description: `Add ${kind} pane`,
        run: () => {
          if (canAddPane) addBlock(kind);
        },
      });
    });

    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape" && isPaletteOpen) {
        e.preventDefault();
        closePalette();
        return;
      }
      for (const b of bindings) {
        if (matches(e, b.combo)) {
          e.preventDefault();
          b.run();
          return;
        }
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [
    isPaletteOpen,
    openPalette,
    closePalette,
    addBlock,
    paneCapacityLimit,
    removeBlock,
    layout,
    workspaces,
    selectedWorkspaceId,
    selectWorkspace,
    updateBlock,
    setTheme,
    theme,
    activeBlockId,
    toggleRightRail,
    setRightRailTab,
  ]);
}

export type { Panel };
