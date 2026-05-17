import { useApp } from "../lib/store";
import { ipc } from "../lib/ipc";
import { LoomLogoMark } from "./LoomLogoMark";
import { UpdatePill } from "./UpdatePill";
import { Icons } from "../lib/icons";
import { surface, text, workspaceColorVar } from "../lib/theme";
import type { Panel as PanelType } from "../lib/store";

type UsageTool = "claude" | "codex" | "gemini";
const USAGE_TOOLS: { id: UsageTool; label: string; color: string }[] = [
  { id: "claude", label: "Claude Usage", color: workspaceColorVar.orange },
  { id: "codex", label: "Codex Usage", color: workspaceColorVar.green },
  { id: "gemini", label: "Gemini Usage", color: workspaceColorVar.blue },
];

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
  const setUsageTool = useApp((s) => s.setUsageTool);
  const selectedUsageTool = useApp((s) => s.selectedUsageTool);
  const workspace = workspaces.find((w) => w.id === selectedId);

  return (
    <div
      className="flex items-center gap-3 px-3 py-2 no-select flex-none"
      style={{
        background: "transparent",
        borderBottom: `1px solid ${surface.hairline}`,
      }}
    >
      <a
        href="#"
        onClick={(e) => {
          e.preventDefault();
          ipc.shell.open("https://github.com/BigBeardedMan/Loom").catch(() => {});
        }}
        className="flex items-center gap-1.5"
        style={{
          padding: "4px 10px",
          borderRadius: 8,
          background: surface.softPanel,
          border: `1px solid ${surface.hairline}`,
          textDecoration: "none",
        }}
        title="Open Loom on GitHub"
      >
        <LoomLogoMark size={18} />
        <span
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: text.primary,
            letterSpacing: -0.1,
          }}
        >
          Loom Testing Edition
        </span>
      </a>

      <div className="flex items-center gap-1.5">
        {USAGE_TOOLS.map((t) => (
          <UsageChip
            key={t.id}
            id={t.id}
            label={t.label}
            color={t.color}
            active={selectedUsageTool === t.id}
            onClick={() =>
              setUsageTool(selectedUsageTool === t.id ? null : t.id)
            }
          />
        ))}
      </div>

      <div className="flex-1" />

      {workspace && !selectedUsageTool && (
        <AddBlockStrip
          workspaceKind={workspace.kindRaw}
          activeKinds={layout?.blocks.map((b) => b.kind) ?? []}
          onAdd={(k) => addBlock(k)}
        />
      )}

      {updatePill && <UpdatePill version={updatePill.version} />}
    </div>
  );
}

function UsageChip({
  label,
  color,
  active,
  onClick,
}: {
  id: UsageTool;
  label: string;
  color: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-1.5 transition-colors"
      style={{
        padding: "4px 10px",
        borderRadius: 999,
        background: active ? color : surface.softPanel,
        border: `1px solid ${surface.hairline}`,
        color: active ? "#fff" : text.primary,
        fontSize: 12,
        fontWeight: 600,
      }}
      title={active ? "Click a workspace to return" : `Open ${label} dashboard`}
    >
      <span
        style={{
          width: 7,
          height: 7,
          borderRadius: 999,
          background: active ? "#fff" : color,
          display: "inline-block",
        }}
      />
      {label}
    </button>
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
