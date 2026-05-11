import { useEffect } from "react";
import { useApp } from "./lib/store";
import { WorkspaceSidebar } from "./modules/workspace/WorkspaceSidebar";
import { WorkspaceView } from "./modules/workspace/WorkspaceView";
import { CommandPalette } from "./modules/workspace/CommandPalette";
import { SettingsModal } from "./modules/settings/SettingsModal";
import { Titlebar } from "./components/Titlebar";
import { ipc } from "./lib/ipc";

function App() {
  const loadWorkspaces = useApp((s) => s.loadWorkspaces);
  const setUpdatePill = useApp((s) => s.setUpdatePill);
  const openPalette = useApp((s) => s.openPalette);
  const closePalette = useApp((s) => s.closePalette);
  const isPaletteOpen = useApp((s) => s.isPaletteOpen);

  useEffect(() => {
    loadWorkspaces();
  }, [loadWorkspaces]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const isMod = e.ctrlKey || e.metaKey;
      if (isMod && (e.key === "k" || e.key === "K")) {
        e.preventDefault();
        if (isPaletteOpen) closePalette();
        else openPalette();
      }
      if (e.key === "Escape" && isPaletteOpen) {
        e.preventDefault();
        closePalette();
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [openPalette, closePalette, isPaletteOpen]);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;
    const tick = async () => {
      try {
        const info = await ipc.update.check();
        if (info && typeof info === "object" && "version" in info) {
          setUpdatePill({ version: (info as { version: string }).version });
        } else {
          setUpdatePill(null);
        }
      } catch {}
    };
    tick();
    timer = setInterval(tick, 60_000);
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [setUpdatePill]);

  return (
    <div className="flex h-full w-full flex-col bg-loom-bg text-loom-text">
      <Titlebar />
      <div className="flex flex-1 min-h-0">
        <WorkspaceSidebar />
        <main className="flex-1 min-w-0 min-h-0">
          <WorkspaceView />
        </main>
      </div>
      <CommandPalette />
      <SettingsModal />
    </div>
  );
}

export default App;
