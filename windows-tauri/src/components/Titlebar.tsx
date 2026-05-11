import { useApp } from "../lib/store";
import { Settings, RefreshCw } from "lucide-react";
import { ipc } from "../lib/ipc";

export function Titlebar() {
  const updatePill = useApp((s) => s.updatePill);
  const openSettings = useApp((s) => s.openSettings);

  return (
    <div className="titlebar flex items-center justify-between border-b border-loom-border bg-loom-panel px-4">
      <div className="flex items-center gap-2 no-select">
        <div className="h-5 w-5 rounded bg-gradient-to-br from-loom-accent to-purple-500" />
        <span className="text-sm font-medium tracking-tight">Loom</span>
      </div>

      <div className="flex items-center gap-2">
        {updatePill && (
          <button
            className="flex items-center gap-1.5 rounded-md border border-loom-border bg-loom-panel-elev px-2 py-1 text-xs text-loom-text-dim hover:bg-loom-border hover:text-loom-text"
            onClick={() => ipc.update.apply().catch(() => {})}
          >
            <RefreshCw className="h-3 w-3" />
            Update to {updatePill.version}
          </button>
        )}
        <button
          className="rounded-md p-1.5 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text"
          onClick={openSettings}
          aria-label="Settings"
        >
          <Settings className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
