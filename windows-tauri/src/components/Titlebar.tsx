import { getCurrentWindow } from "@tauri-apps/api/window";
import { open as openExternal } from "@tauri-apps/plugin-shell";
import { useApp } from "../lib/store";
import { LoomLogoMark } from "./LoomLogoMark";
import { UpdatePill } from "./UpdatePill";
import { Icons } from "../lib/icons";
import { surface, text, workspaceColorVar } from "../lib/theme";
import type { Panel as PanelType } from "../lib/store";

const win = getCurrentWindow();

type UsageTool = "claude" | "codex" | "gemini";
const USAGE_TOOLS: { id: UsageTool; label: string; color: string }[] = [
  { id: "claude", label: "Claude Usage", color: workspaceColorVar.orange },
  { id: "codex", label: "Codex Usage", color: workspaceColorVar.green },
  { id: "gemini", label: "Gemini Usage", color: workspaceColorVar.blue },
];

const PANEL_META: Record<PanelType, { label: string; icon: keyof typeof Icons }> = {
  terminal: { label: "Terminal", icon: "terminal" },
  editor: { label: "Editor", icon: "textCursor" },
  tasks: { label: "Tasks", icon: "checkCircle" },
  agent: { label: "Agent", icon: "sparkles" },
  notes: { label: "Notes", icon: "lightbulb" },
  preview: { label: "Preview", icon: "eye" },
  commands: { label: "Commands", icon: "listBulletRect" },
};

// Mirrors Loom/Workspace/WorkspaceView.swift topBar (lines 97-138):
// logo / usageTabs / spacer / addBlockStrip / updatePill.
export function Titlebar() {
  const updatePill = useApp((s) => s.updatePill);
  const activePanels = useApp((s) => s.activePanels);
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const workspace = workspaces.find((w) => w.id === selectedId);

  return (
    <div
      className="titlebar flex items-center gap-3 px-2 no-select flex-none"
      style={{
        background: "transparent",
        borderBottom: `1px solid ${surface.hairline}`,
      }}
    >
      <TrafficLights />

      <a
        href="#"
        data-no-drag
        onClick={(e) => {
          e.preventDefault();
          openExternal("https://github.com/BigBeardedMan/Loom").catch(() => {});
        }}
        className="flex items-center gap-1.5"
        style={{
          padding: "3px 8px",
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
          Loom
        </span>
      </a>

      <div className="flex items-center gap-1.5">
        {USAGE_TOOLS.map((t) => (
          <UsageChip key={t.id} label={t.label} color={t.color} />
        ))}
      </div>

      <div className="flex-1" />

      {workspace && <AddBlockStrip activePanels={activePanels} workspace={workspace} />}

      {updatePill && <UpdatePill version={updatePill.version} />}
    </div>
  );
}

function UsageChip({ label, color }: { label: string; color: string }) {
  return (
    <button
      data-no-drag
      className="flex items-center gap-1.5 transition-colors"
      style={{
        padding: "4px 10px",
        borderRadius: 999,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 30%)",
        border: `1px solid ${surface.hairline}`,
        color: text.primary,
        fontSize: 12,
        fontWeight: 600,
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = surface.softPanel as string;
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background =
          "color-mix(in srgb, " + surface.softPanel + ", transparent 30%)";
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
      {label}
    </button>
  );
}

function AddBlockStrip({
  activePanels,
  workspace,
}: {
  activePanels: PanelType[];
  workspace: { kindRaw: string };
}) {
  const available = panelsForKind(workspace.kindRaw);

  return (
    <div
      data-no-drag
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
        const active = activePanels.includes(p);
        return (
          <button
            key={p}
            className="flex items-center gap-1 transition-colors"
            style={{
              padding: "3px 8px",
              borderRadius: 999,
              background: active ? surface.softPanel : "transparent",
              color: active ? text.primary : text.muted,
              fontSize: 11,
              fontWeight: 600,
            }}
            onMouseEnter={(e) => {
              if (!active) {
                e.currentTarget.style.background = surface.softPanel as string;
                e.currentTarget.style.color = text.primary as string;
              }
            }}
            onMouseLeave={(e) => {
              if (!active) {
                e.currentTarget.style.background = "transparent";
                e.currentTarget.style.color = text.muted as string;
              }
            }}
            title={`Add ${meta.label} block`}
          >
            <Icons.plus size={9} strokeWidth={2.5} />
            <Icon size={10} strokeWidth={2} />
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

function TrafficLights() {
  return (
    <div className="flex items-center gap-2" data-no-drag>
      <button
        onClick={() => win.close()}
        className="window-control"
        style={{ background: "#FF5F57" }}
        aria-label="Close"
      >
        <Icons.close size={8} color="#4D0000" strokeWidth={3} />
      </button>
      <button
        onClick={() => win.minimize()}
        className="window-control"
        style={{ background: "#FFBD2E" }}
        aria-label="Minimize"
      >
        <Icons.minimize size={8} color="#995A00" strokeWidth={3} />
      </button>
      <button
        onClick={async () => {
          const maxed = await win.isMaximized();
          if (maxed) win.unmaximize();
          else win.maximize();
        }}
        className="window-control"
        style={{ background: "#28C840" }}
        aria-label="Maximize"
      >
        <Icons.plus size={8} color="#006500" strokeWidth={3} />
      </button>
    </div>
  );
}
