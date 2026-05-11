import { Command } from "cmdk";
import {
  modal,
  radius,
  surface,
  text,
  workspaceColorVar,
  type WorkspaceColor,
} from "../../lib/theme";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";

// Mirrors Loom/Workspace/CommandPalette.swift.
// 560x420 sheet, .regularMaterial backdrop, sectioned list with selection ring.
export function CommandPalette() {
  const isOpen = useApp((s) => s.isPaletteOpen);
  const closePalette = useApp((s) => s.closePalette);
  const workspaces = useApp((s) => s.workspaces);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const openSettings = useApp((s) => s.openSettings);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center"
      style={{
        paddingTop: 120,
        background: "rgba(0, 0, 0, 0.40)",
        backdropFilter: "blur(20px) saturate(180%)",
        WebkitBackdropFilter: "blur(20px) saturate(180%)",
      }}
      onClick={closePalette}
    >
      <Command
        className="overflow-hidden flex flex-col"
        style={{
          width: modal.commandPalette.width,
          maxHeight: modal.commandPalette.height,
          background: surface.panel,
          border: `1px solid ${surface.hairline}`,
          borderRadius: radius.panel,
          boxShadow: "0 24px 48px rgba(0, 0, 0, 0.45)",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div
          className="flex items-center gap-2 flex-none"
          style={{
            padding: "12px 14px",
            borderBottom: `1px solid ${surface.hairline}`,
          }}
        >
          <Icons.search size={14} strokeWidth={2} color={text.muted as string} />
          <Command.Input
            autoFocus
            placeholder="Switch workspace, run a command…"
            className="w-full focus:outline-none"
            style={{
              background: "transparent",
              fontSize: 16,
              color: text.primary,
              border: "none",
            }}
          />
        </div>
        <Command.List className="scrollbar-thin flex-1 overflow-y-auto" style={{ padding: 6 }}>
          <Command.Empty
            className="text-center"
            style={{ padding: 32, fontSize: 12, color: text.tertiary }}
          >
            Nothing matches.
          </Command.Empty>

          <Command.Group
            heading="Workspaces"
            className="section-header"
            style={{ padding: "10px 14px 4px" }}
          >
            {workspaces.map((ws) => (
              <Command.Item
                key={ws.id}
                value={`workspace ${ws.name}`}
                onSelect={() => {
                  selectWorkspace(ws.id);
                  closePalette();
                }}
                className="flex cursor-pointer items-center gap-2"
                style={{
                  padding: "7px 14px",
                  fontSize: 13,
                  fontWeight: 500,
                  color: text.muted,
                  borderRadius: 6,
                }}
              >
                <span
                  className="inline-block flex-none rounded-full"
                  style={{
                    width: 9,
                    height: 9,
                    background: workspaceColorVar[ws.colorName as WorkspaceColor],
                  }}
                />
                <span className="flex-1 truncate">{ws.name}</span>
                <span
                  className="font-mono truncate"
                  style={{ fontSize: 11, color: text.tertiary, maxWidth: 200 }}
                >
                  {ws.folderPath || ""}
                </span>
              </Command.Item>
            ))}
          </Command.Group>

          <Command.Group
            heading="Actions"
            className="section-header"
            style={{ padding: "10px 14px 4px" }}
          >
            <Command.Item
              value="settings"
              onSelect={() => {
                openSettings();
                closePalette();
              }}
              className="flex cursor-pointer items-center gap-2"
              style={{
                padding: "7px 14px",
                fontSize: 13,
                fontWeight: 500,
                color: text.muted,
                borderRadius: 6,
              }}
            >
              <Icons.settings size={12} strokeWidth={1.8} />
              Open Settings
            </Command.Item>
          </Command.Group>
        </Command.List>
        <style>{`
          [cmdk-item][aria-selected="true"] {
            background: color-mix(in srgb, var(--color-loom-accent) 18%, transparent) !important;
            color: var(--color-loom-text) !important;
          }
        `}</style>
      </Command>
    </div>
  );
}
