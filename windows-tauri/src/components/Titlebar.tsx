import { useApp } from "../lib/store";
import { ipc } from "../lib/ipc";
import { LoomLogoMark } from "./LoomLogoMark";
import { UpdatePill } from "./UpdatePill";
import { Icons } from "../lib/icons";
import { useDictation } from "../lib/dictation";
import { radius, surface, text, topbar, workspaceColorVar } from "../lib/theme";
import { toolBrandColor, toolLabel } from "../lib/usage";
import type { Panel as PanelType } from "../lib/store";

type UsageTool = "claude" | "codex" | "lmstudio";

const PANEL_META: Record<
  PanelType,
  { label: string; icon: keyof typeof Icons; color: string }
> = {
  terminal: { label: "Terminal", icon: "terminal", color: workspaceColorVar.green },
  editor: { label: "Editor", icon: "textCursor", color: workspaceColorVar.blue },
  tasks: { label: "Tasks", icon: "checkCircle", color: workspaceColorVar.orange },
  agent: { label: "Agent", icon: "sparkles", color: workspaceColorVar.purple },
  notes: { label: "Notes", icon: "lightbulb", color: workspaceColorVar.yellow },
  preview: { label: "Preview", icon: "eye", color: workspaceColorVar.pink },
  commands: { label: "Commands", icon: "listBulletRect", color: workspaceColorVar.blue },
};

// Mirrors Loom/Workspace/WorkspaceView.swift topBar (lines 97-238).
// No window controls here: Windows draws its own chrome above this bar.
export function Titlebar() {
  const updatePill = useApp((s) => s.updatePill);
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const addBlock = useApp((s) => s.addBlock);
  const layout = useApp((s) => s.layout);
  const selectedUsageTool = useApp((s) => s.selectedUsageTool);
  const setUsageTool = useApp((s) => s.setUsageTool);
  const openPalette = useApp((s) => s.openPalette);
  const openSettings = useApp((s) => s.openSettings);
  const workspace = workspaces.find((w) => w.id === selectedId);
  const dictation = useDictation();

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
          padding: "4px 9px 4px 8px",
          minHeight: 34,
          borderRadius: radius.row,
          background: surface.softPanel,
          border: `1px solid ${surface.hairline}`,
          textDecoration: "none",
        }}
        title="Open Loom on GitHub"
      >
        <LoomLogoMark size={19} />
        <span className="flex flex-col leading-none">
          <span style={{ fontSize: 12, fontWeight: 700, color: text.primary }}>
            Loom
          </span>
          <span style={{ marginTop: 2, fontSize: 9, fontWeight: 700, color: text.muted }}>
            Testing Edition
          </span>
        </span>
      </a>

      <div
        aria-hidden="true"
        style={{ width: 1, height: 24, background: surface.hairline }}
      />

      <button
        onClick={openPalette}
        className="flex items-center gap-2 transition-colors"
        style={{
          minHeight: 30,
          padding: "4px 10px",
          borderRadius: radius.control,
          background: "color-mix(in srgb, " + surface.softPanel + ", transparent 30%)",
          border: `1px solid ${surface.hairline}`,
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
            padding: "1px 5px",
            borderRadius: 5,
            background: surface.inset,
            color: text.tertiary,
            fontSize: 10,
            fontFamily: "var(--font-mono)",
            fontWeight: 700,
          }}
        >
          Ctrl K
        </span>
      </button>

      <button
        onClick={openSettings}
        className="flex items-center gap-2 transition-colors"
        style={{
          minHeight: 30,
          padding: "4px 10px",
          borderRadius: radius.control,
          background: "color-mix(in srgb, " + surface.softPanel + ", transparent 30%)",
          border: `1px solid ${surface.hairline}`,
          color: text.primary,
          fontSize: 12,
          fontWeight: 600,
        }}
        title="Open Settings"
        aria-label="Open Settings"
      >
        <Icons.settings size={13} strokeWidth={2.2} color={text.muted as string} />
        Settings
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
          onAdd={(k) => addBlock(k)}
        />
      ) : null}

      <button
        onClick={dictation.toggle}
        className="flex items-center gap-1.5 transition-colors"
        style={{
          minHeight: 30,
          padding: "4px 10px",
          borderRadius: 999,
          background: dictation.isActive ? workspaceColorVar.purple : surface.softPanel,
          border: `1px solid ${surface.hairline}`,
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
        {dictation.isActive ? "Listening" : "Dictate"}
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
        border: `1px solid ${color}`,
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
  onAdd,
}: {
  workspaceKind: string;
  activeKinds: PanelType[];
  onAdd: (k: PanelType) => void;
}) {
  const available = panelsForKind(workspaceKind);

  return (
    <div
      className="flex items-center gap-1"
      style={{
        padding: "3px 5px",
        borderRadius: 999,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 40%)",
        border: `1px solid ${surface.hairline}`,
      }}
    >
      {available.map((p) => {
        const meta = PANEL_META[p];
        const Icon = Icons[meta.icon];
        const used = activeKinds.includes(p);
        return (
          <button
            key={p}
            onClick={() => onAdd(p)}
            className="flex items-center gap-1 transition-colors"
            style={{
              padding: "3px 8px",
              borderRadius: 999,
              background: "transparent",
              color: text.primary,
              fontSize: 11,
              fontWeight: 600,
              opacity: used ? 0.55 : 1,
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = surface.softPanel as string;
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = "transparent";
            }}
            title={`Add ${meta.label} block`}
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

function panelsForKind(kind: string): PanelType[] {
  switch (kind) {
    case "code":
      return ["terminal", "editor", "tasks", "agent", "commands"];
    case "ideas":
      return ["notes", "agent"];
    case "review":
    case "build":
      return ["preview", "agent"];
    default:
      return [];
  }
}
