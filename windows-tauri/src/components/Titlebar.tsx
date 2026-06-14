import { useEffect, useRef, useState } from "react";
import { useApp } from "../lib/store";
import { UpdatePill } from "./UpdatePill";
import { Icons } from "../lib/icons";
import { useDictation } from "../lib/dictation";
import { radius, surface, text, topbar, workspaceColorVar } from "../lib/theme";
import { toolBrandColor, toolLabel } from "../lib/usage";
import type { Panel as PanelType } from "../lib/store";
import { PANEL_META, panelsForKind } from "../lib/commands";

type UsageTool = "claude" | "codex" | "lmstudio";

// Mirrors the quiet macOS WorkspaceView top bar. Windows draws its own chrome
// above this row, so this stays focused on command/search and pane actions.
export function Titlebar() {
  const updatePill = useApp((s) => s.updatePill);
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const addBlock = useApp((s) => s.addBlock);
  const layout = useApp((s) => s.layout);
  const paneCapacityLimit = useApp((s) => s.paneCapacityLimit);
  const selectedUsageTool = useApp((s) => s.selectedUsageTool);
  const setUsageTool = useApp((s) => s.setUsageTool);
  const openPalette = useApp((s) => s.openPalette);
  const workspace = workspaces.find((w) => w.id === selectedId);
  const dictation = useDictation();
  const canAddPane = !layout || paneCapacityLimit === null || layout.blocks.length < paneCapacityLimit;

  return (
    <div
      className="flex items-center no-select flex-none"
      style={{
        minHeight: topbar.height,
        gap: topbar.gap,
      }}
    >
      <div
        className="flex min-w-0 items-center gap-2"
        style={{
          padding: "4px 2px",
          minHeight: 34,
          maxWidth: 280,
        }}
        title={workspace?.folderPath || workspace?.name || "No workspace"}
      >
        <span
          aria-hidden="true"
          style={{
            width: 7,
            height: 7,
            borderRadius: 999,
            background: workspace ? workspaceColorVar[workspace.colorName] : text.tertiary,
            flex: "none",
          }}
        />
        <span className="truncate" style={{ fontSize: 14, fontWeight: 750, color: text.primary }}>
          {workspace?.name ?? "No workspace"}
        </span>
        <Icons.moreHorizontal size={14} strokeWidth={2.2} color={text.tertiary as string} />
      </div>

      <button
        onClick={openPalette}
        className="flex items-center gap-2 transition-colors"
        style={{
          minHeight: 30,
          padding: "4px 7px",
          borderRadius: radius.control,
          background: "transparent",
          color: text.primary,
          fontSize: 12,
          fontWeight: 600,
        }}
        title="Open command palette (Ctrl+K)"
      >
        <Icons.search size={13} strokeWidth={2.2} color={text.muted as string} />
        Command
        <span
          style={{
            marginLeft: 2,
            padding: "1px 2px",
            color: text.tertiary,
            fontSize: 10,
            fontFamily: "var(--font-mono)",
            fontWeight: 700,
          }}
        >
          Ctrl K
        </span>
      </button>

      <div className="flex-1" />

      {selectedUsageTool ? (
        <SelectedUsageStatus
          tool={selectedUsageTool}
          onClose={() => setUsageTool(null)}
        />
      ) : workspace ? (
        <AddPaneMenu
          workspaceKind={workspace.kindRaw}
          activeKinds={layout?.blocks.map((b) => b.kind) ?? []}
          canAdd={canAddPane}
          onAdd={(k) => addBlock(k)}
        />
      ) : null}

      <button
        onClick={dictation.toggle}
        className="flex items-center gap-1.5 transition-colors"
        style={{
          minHeight: 30,
          padding: dictation.isActive ? "4px 10px" : "4px 0",
          borderRadius: 999,
          background: dictation.isActive ? workspaceColorVar.purple : "transparent",
          border: dictation.isActive ? `1px solid ${workspaceColorVar.purple}` : "1px solid transparent",
          color: dictation.isActive ? "#fff" : text.primary,
          fontSize: 12,
          fontWeight: 700,
        }}
        title={
          dictation.error ??
          (dictation.isActive
            ? dictation.liveTranscript || "Listening. Press F5 to insert or Esc to cancel."
            : "Start dictation (F5)")
        }
      >
        <Icons.mic size={13} strokeWidth={2.2} />
        {dictation.isActive ? "Listening" : null}
      </button>

      {updatePill && <UpdatePill version={updatePill.version} />}
    </div>
  );
}

function SelectedUsageStatus({
  tool,
  onClose,
}: {
  tool: UsageTool;
  onClose: () => void;
}) {
  const color = toolBrandColor(tool);
  return (
    <div
      className="flex items-center gap-2"
      style={{
        padding: "4px 10px",
        borderRadius: 999,
        background: "color-mix(in srgb, " + color + ", transparent 82%)",
        border: `1px solid color-mix(in srgb, ${color} 48%, transparent)`,
        color: text.primary,
        fontSize: 12,
        fontWeight: 700,
      }}
    >
      <span
        style={{
          width: 7,
          height: 7,
          borderRadius: 999,
          background: color,
          display: "inline-block",
        }}
      />
      {toolLabel(tool)}
      <button
        onClick={onClose}
        aria-label="Close usage dashboard"
        style={{
          padding: 1,
          marginLeft: 1,
          borderRadius: 4,
          color: text.muted,
        }}
      >
        <Icons.close size={12} strokeWidth={2.2} />
      </button>
    </div>
  );
}

function AddPaneMenu({
  workspaceKind,
  activeKinds,
  canAdd,
  onAdd,
}: {
  workspaceKind: string;
  activeKinds: PanelType[];
  canAdd: boolean;
  onAdd: (k: PanelType) => void;
}) {
  const available = panelsForKind(workspaceKind);
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      if (menuRef.current?.contains(event.target as Node)) return;
      setOpen(false);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    window.addEventListener("pointerdown", onPointerDown);
    window.addEventListener("keydown", onKeyDown);
    return () => {
      window.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  return (
    <div
      ref={menuRef}
      className="relative flex items-center"
      style={{
        padding: 0,
      }}
    >
      <button
        type="button"
        onClick={() => {
          if (canAdd) setOpen((value) => !value);
        }}
        disabled={!canAdd}
        className="flex items-center justify-center transition-colors"
        style={{
          width: 28,
          height: 28,
          borderRadius: radius.control,
          background: open ? surface.softPanel : "transparent",
          color: canAdd ? text.primary : text.tertiary,
          opacity: canAdd ? 1 : 0.45,
        }}
        title={canAdd ? "Add pane" : "Pane limit reached"}
        aria-label="Add pane"
        aria-haspopup="menu"
        aria-expanded={open}
      >
        <Icons.plus size={15} strokeWidth={2.6} />
      </button>

      {open && (
        <div
          role="menu"
          className="absolute right-0 top-full z-50 mt-2"
          style={{
            minWidth: 184,
            padding: 5,
            borderRadius: 8,
            background: surface.panel,
            border: `1px solid ${surface.hairline}`,
            boxShadow: "0 16px 34px rgba(0,0,0,0.42)",
          }}
        >
          {available.map((p) => {
            const meta = PANEL_META[p];
            const Icon = Icons[meta.icon];
            const used = activeKinds.includes(p);
            return (
              <button
                key={p}
                type="button"
                role="menuitem"
                onClick={() => {
                  if (!canAdd) return;
                  onAdd(p);
                  setOpen(false);
                }}
                disabled={!canAdd}
                className="flex w-full items-center gap-2 text-left transition-colors"
                style={{
                  padding: "7px 8px",
                  borderRadius: 6,
                  background: "transparent",
                  color: canAdd ? text.primary : text.tertiary,
                  fontSize: 12,
                  fontWeight: 650,
                  opacity: canAdd ? (used ? 0.58 : 1) : 0.42,
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = surface.softPanel as string;
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = "transparent";
                }}
                title={canAdd ? `Add ${meta.label} pane` : "Pane limit reached"}
              >
                <Icon size={13} strokeWidth={2.1} color={meta.color} />
                <span className="flex-1">Add {meta.label}</span>
                {used && (
                  <span
                    style={{
                      color: text.tertiary,
                      fontSize: 10,
                      fontFamily: "var(--font-mono)",
                      fontWeight: 700,
                    }}
                  >
                    open
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
