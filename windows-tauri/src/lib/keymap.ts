// Mirrors the macOS Loom keyboard shortcut surface.
// Single central place that the App-level keydown handler reads from.

import { useEffect } from "react";
import { useApp, type Panel } from "./store";

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

// Order matches macOS LoomApp.swift add-block menu — Cmd+Shift+1..7.
const ADD_BLOCK_ORDER: Panel[] = [
  "terminal",
  "editor",
  "tasks",
  "agent",
  "notes",
  "preview",
  "commands",
];

export function useGlobalKeymap() {
  const openPalette = useApp((s) => s.openPalette);
  const closePalette = useApp((s) => s.closePalette);
  const isPaletteOpen = useApp((s) => s.isPaletteOpen);
  const addBlock = useApp((s) => s.addBlock);
  const removeBlock = useApp((s) => s.removeBlock);
  const layout = useApp((s) => s.layout);
  const workspaces = useApp((s) => s.workspaces);
  const selectedWorkspaceId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const updateBlock = useApp((s) => s.updateBlock);
  const setTheme = useApp((s) => s.setTheme);
  const theme = useApp((s) => s.theme);

  useEffect(() => {
    const focusedBlockId = (() => {
      // Cheap heuristic: rely on document.activeElement being inside a block
      // when keystrokes fire. We pick the first block as a fallback so users
      // can still toggle full-row span without focus tracking.
      return layout?.blocks[0]?.id;
    })();

    const bindings: Binding[] = [
      {
        combo: "ctrl+k",
        description: "Toggle command palette",
        run: () => (isPaletteOpen ? closePalette() : openPalette()),
      },
      {
        combo: "ctrl+t",
        description: "Add Terminal block",
        run: () => addBlock("terminal"),
      },
      {
        combo: "ctrl+w",
        description: "Close last block",
        run: () => {
          const last = layout?.blocks[layout.blocks.length - 1];
          if (last) removeBlock(last.id);
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
        combo: "ctrl+shift+l",
        description: "Cycle theme",
        run: () =>
          setTheme(
            theme === "system" ? "light" : theme === "light" ? "dark" : "system"
          ),
      },
      {
        combo: "ctrl+alt+f",
        description: "Toggle full-row span on first block",
        run: () => {
          if (!focusedBlockId || !layout) return;
          const blk = layout.blocks.find((b) => b.id === focusedBlockId);
          if (!blk) return;
          updateBlock(blk.id, { fullRowSpan: !blk.fullRowSpan });
        },
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

    // Ctrl+Shift+1..7 → add block of nth kind (matches macOS Cmd+Shift+N order).
    ADD_BLOCK_ORDER.forEach((kind, i) => {
      bindings.push({
        combo: `ctrl+shift+${i + 1}`,
        description: `Add ${kind} block`,
        run: () => addBlock(kind),
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
    removeBlock,
    layout,
    workspaces,
    selectedWorkspaceId,
    selectWorkspace,
    updateBlock,
    setTheme,
    theme,
  ]);
}

export type { Panel };
