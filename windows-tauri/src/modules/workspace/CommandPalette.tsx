import { Command } from "cmdk";
import { useApp, workspaceColorClass } from "../../lib/store";

export function CommandPalette() {
  const isOpen = useApp((s) => s.isPaletteOpen);
  const closePalette = useApp((s) => s.closePalette);
  const workspaces = useApp((s) => s.workspaces);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const openSettings = useApp((s) => s.openSettings);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-black/50 pt-24"
      onClick={closePalette}
    >
      <Command
        className="w-[640px] max-w-[90vw] overflow-hidden rounded-xl border border-loom-border bg-loom-panel shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <Command.Input
          autoFocus
          placeholder="Switch workspace, run a command…"
          className="w-full border-b border-loom-border bg-transparent px-4 py-3 text-sm text-loom-text outline-none placeholder:text-loom-text-mute"
        />
        <Command.List className="scrollbar-thin max-h-[400px] overflow-y-auto p-1">
          <Command.Empty className="px-3 py-6 text-center text-sm text-loom-text-mute">
            Nothing matches.
          </Command.Empty>

          <Command.Group heading="Workspaces" className="px-1 py-1 text-xs text-loom-text-mute">
            {workspaces.map((ws) => (
              <Command.Item
                key={ws.id}
                value={`workspace ${ws.name}`}
                onSelect={() => {
                  selectWorkspace(ws.id);
                  closePalette();
                }}
                className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm text-loom-text-dim aria-selected:bg-loom-panel-elev aria-selected:text-loom-text"
              >
                <span
                  className={`h-2 w-2 rounded-full ${workspaceColorClass[ws.colorName]}`}
                />
                <span className="flex-1 truncate">{ws.name}</span>
              </Command.Item>
            ))}
          </Command.Group>

          <Command.Group heading="Actions" className="px-1 py-1 text-xs text-loom-text-mute">
            <Command.Item
              value="settings"
              onSelect={() => {
                openSettings();
                closePalette();
              }}
              className="cursor-pointer rounded-md px-2 py-1.5 text-sm text-loom-text-dim aria-selected:bg-loom-panel-elev aria-selected:text-loom-text"
            >
              Open Settings
            </Command.Item>
          </Command.Group>
        </Command.List>
      </Command>
    </div>
  );
}
