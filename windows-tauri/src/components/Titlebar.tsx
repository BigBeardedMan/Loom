import { useApp } from "../lib/store";
import { ipc } from "../lib/ipc";
import { LoomLogoMark } from "./LoomLogoMark";
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
      <a
        href="#"
        onClick={(e) => {
          e.preventDefault();
          ipc.shell.open("https://github.com/BigBeardedMan/Loom").catch(() => {});
        }}
        className="flex items-center gap-2"
        style={{
          padding: "4px 4px",
          minHeight: 34,
          textDecoration: "none",
        }}
        title="Open Loom Testing Edition on GitHub"
      >
        <LoomLogoMark size={19} />
        <span style={{ fontSize: 13, fontWeight: 800, color: text.primary }}>Loom</span>
        <span style={{ fontSize: 10, fontWeight: 700, color: text.tertiary }}>Testing</span>
      </a>

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
        <AddBlockStrip
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

function AddBlockStrip({
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

  return (
    <div
      className="flex items-center gap-1"
      style={{
        padding: "3px 2px",
        borderRadius: 999,
        background: "transparent",
      }}
    >
      {available.map((p) => {
        const meta = PANEL_META[p];
        const Icon = Icons[meta.icon];
        const used = activeKinds.includes(p);
        return (
          <button
            key={p}
            onClick={() => {
              if (canAdd) onAdd(p);
            }}
            disabled={!canAdd}
            className="flex items-center gap-1 transition-colors"
            style={{
              padding: "3px 8px",
              borderRadius: 999,
              background: "transparent",
              color: canAdd ? text.primary : text.tertiary,
              fontSize: 11,
              fontWeight: 600,
              opacity: canAdd ? (used ? 0.55 : 1) : 0.42,
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = surface.softPanel as string;
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = "transparent";
            }}
            title={canAdd ? `Add ${meta.label} pane` : "Pane limit reached"}
          >
            <Icons.plus size={9} strokeWidth={2.5} />
            <Icon size={10} strokeWidth={2} color={meta.color} />
            {meta.label}
          </button>
        );
      })}
    </div>
  );
}
