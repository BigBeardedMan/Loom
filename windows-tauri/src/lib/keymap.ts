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

export function useGlobalKeymap() {
  const openPalette = useApp((s) => s.openPalette);
  const closePalette = useApp((s) => s.closePalette);
  const isPaletteOpen = useApp((s) => s.isPaletteOpen);
  const addBlock = useApp((s) => s.addBlock);
  const removeBlock = useApp((s) => s.removeBlock);
  const layout = useApp((s) => s.layout);
  const workspaces = useApp((s) => s.workspaces);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const setTheme = useApp((s) => s.setTheme);
  const theme = useApp((s) => s.theme);

  useEffect(() => {
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
        combo: "ctrl+shift+l",
        description: "Cycle theme",
        run: () =>
          setTheme(
            theme === "system" ? "light" : theme === "light" ? "dark" : "system"
          ),
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
    selectWorkspace,
    setTheme,
    theme,
  ]);
}

export type { Panel };
