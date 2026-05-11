import { useState } from "react";
import { Icons } from "../../lib/icons";
import {
  useApp,
  workspaceKindLabel,
} from "../../lib/store";
import {
  ipc,
  type Workspace,
  type WorkspaceColor as IpcColor,
  type WorkspaceKind as IpcKind,
} from "../../lib/ipc";
import {
  radius,
  sidebar,
  surface,
  text,
  workspaceColorVar,
  type WorkspaceColor,
} from "../../lib/theme";
import { WorkspaceDot } from "../../components/WorkspaceDot";

const COLORS: WorkspaceColor[] = [
  "blue",
  "green",
  "orange",
  "pink",
  "purple",
  "yellow",
];

const KINDS: { value: IpcKind; label: string }[] = [
  { value: "code", label: workspaceKindLabel.code },
  { value: "ideas", label: workspaceKindLabel.ideas },
  { value: "review", label: workspaceKindLabel.review },
];

// Mirrors Loom/Workspace/WorkspaceSidebarView.swift.
// 240 px wide, 12/14 padding, hairline right border, sectioned rows.
export function WorkspaceSidebar() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const createWorkspace = useApp((s) => s.createWorkspace);
  const deleteWorkspace = useApp((s) => s.deleteWorkspace);
  const [creating, setCreating] = useState(false);

  return (
    <aside
      className="flex h-full flex-col flex-none"
      style={{
        width: sidebar.width,
        background: surface.panel,
        borderRight: `1px solid ${surface.hairline}`,
      }}
    >
      <div
        className="flex items-center justify-between flex-none"
        style={{
          padding: `${sidebar.paddingV - 4}px ${sidebar.paddingH}px`,
          borderBottom: `1px solid ${surface.hairline}`,
        }}
      >
        <span className="section-header">Workspaces</span>
        <button
          onClick={() => setCreating(true)}
          className="rounded-md p-1 transition-colors"
          style={{ color: text.muted }}
          onMouseEnter={(e) => {
            e.currentTarget.style.color = text.primary as string;
            e.currentTarget.style.background = surface.softPanel as string;
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.color = text.muted as string;
            e.currentTarget.style.background = "transparent";
          }}
          aria-label="New workspace"
        >
          <Icons.plus size={13} strokeWidth={2.2} />
        </button>
      </div>

      <div
        className="scrollbar-thin flex-1 overflow-y-auto"
        style={{
          padding: `${sidebar.paddingV - 6}px ${sidebar.paddingH - 4}px`,
        }}
      >
        {workspaces.length === 0 && !creating && (
          <div
            className="text-center"
            style={{
              padding: "24px 8px",
              fontSize: 11,
              color: text.tertiary,
            }}
          >
            No workspaces yet. Click + to create one.
          </div>
        )}
        <div className="flex flex-col gap-1">
          {workspaces.map((ws) => (
            <WorkspaceRow
              key={ws.id}
              workspace={ws}
              selected={ws.id === selectedId}
              onSelect={() => selectWorkspace(ws.id)}
              onDelete={() => deleteWorkspace(ws.id)}
            />
          ))}
        </div>
      </div>

      {creating && (
        <NewWorkspaceForm
          onCreate={async (input) => {
            await createWorkspace(
              input.name,
              input.folderPath,
              input.color as IpcColor,
              input.kind
            );
            setCreating(false);
          }}
          onCancel={() => setCreating(false)}
        />
      )}
    </aside>
  );
}

function WorkspaceRow({
  workspace,
  selected,
  onSelect,
  onDelete,
}: {
  workspace: Workspace;
  selected: boolean;
  onSelect: () => void;
  onDelete: () => void;
}) {
  const tint = workspaceColorVar[workspace.colorName as WorkspaceColor];
  return (
    <div
      className="group flex items-center gap-2 cursor-pointer transition-colors"
      onClick={onSelect}
      style={{
        padding: `${sidebar.rowPaddingV}px ${sidebar.rowPaddingH}px`,
        borderRadius: radius.row,
        background: selected ? `color-mix(in srgb, ${tint} 13%, transparent)` : "transparent",
        border: `1px solid ${
          selected ? `color-mix(in srgb, ${tint} 65%, transparent)` : surface.hairline
        }`,
        color: selected ? text.primary : text.muted,
      }}
      onMouseEnter={(e) => {
        if (!selected) {
          e.currentTarget.style.background = surface.softPanel as string;
          e.currentTarget.style.color = text.primary as string;
        }
      }}
      onMouseLeave={(e) => {
        if (!selected) {
          e.currentTarget.style.background = "transparent";
          e.currentTarget.style.color = text.muted as string;
        }
      }}
    >
      <WorkspaceDot color={workspace.colorName as WorkspaceColor} />
      <KindIcon kind={workspace.kindRaw} />
      <span
        className="truncate flex-1"
        style={{ fontSize: 12, fontWeight: 500 }}
      >
        {workspace.name}
      </span>
      {workspace.taskBadge > 0 && (
        <span
          className="font-mono"
          style={{
            background: surface.softPanel,
            borderRadius: 999,
            padding: "2px 6px",
            fontSize: 10,
            fontWeight: 700,
            color: text.muted,
          }}
        >
          {workspace.taskBadge}
        </span>
      )}
      <button
        className="invisible rounded p-0.5 group-hover:visible"
        onClick={(e) => {
          e.stopPropagation();
          if (confirm(`Delete workspace "${workspace.name}"?`)) onDelete();
        }}
        style={{ color: text.tertiary }}
        aria-label="Delete workspace"
      >
        <Icons.trash size={11} strokeWidth={2} />
      </button>
    </div>
  );
}

function KindIcon({ kind }: { kind: Workspace["kindRaw"] }) {
  const props = { size: 11, strokeWidth: 1.8, color: text.tertiary as string };
  switch (kind) {
    case "code":
      return <Icons.textCursor {...props} />;
    case "ideas":
      return <Icons.lightbulb {...props} />;
    case "review":
    case "build":
      return <Icons.eye {...props} />;
    default:
      return <Icons.folderFill {...props} />;
  }
}

function NewWorkspaceForm({
  onCreate,
  onCancel,
}: {
  onCreate: (input: {
    name: string;
    folderPath: string;
    color: WorkspaceColor;
    kind: IpcKind;
  }) => Promise<void>;
  onCancel: () => void;
}) {
  const [name, setName] = useState("");
  const [folderPath, setFolderPath] = useState("");
  const [color, setColor] = useState<WorkspaceColor>("blue");
  const [kind, setKind] = useState<IpcKind>("code");
  const [busy, setBusy] = useState(false);

  const pickFolder = async () => {
    const folder = await ipc.fs.pickFolder();
    if (folder) setFolderPath(folder as unknown as string);
  };

  const submit = async () => {
    if (!name.trim()) return;
    setBusy(true);
    try {
      await onCreate({ name: name.trim(), folderPath, color, kind });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div
      className="flex-none space-y-2"
      style={{
        padding: 12,
        borderTop: `1px solid ${surface.hairline}`,
        background: surface.softPanel,
      }}
    >
      <input
        autoFocus
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Workspace name"
        className="w-full focus:outline-none"
        style={{
          background: "var(--color-loom-bg-from)",
          border: `1px solid ${surface.hairline}`,
          borderRadius: radius.control,
          padding: "5px 8px",
          fontSize: 12,
          color: text.primary,
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter") submit();
          if (e.key === "Escape") onCancel();
        }}
      />
      <button
        type="button"
        onClick={pickFolder}
        className="w-full truncate text-left"
        style={{
          background: "var(--color-loom-bg-from)",
          border: `1px solid ${surface.hairline}`,
          borderRadius: radius.control,
          padding: "5px 8px",
          fontSize: 11,
          color: folderPath ? text.primary : text.muted,
        }}
      >
        {folderPath || "Pick folder…"}
      </button>
      <div className="flex flex-wrap gap-1.5">
        {COLORS.map((c) => (
          <button
            key={c}
            type="button"
            onClick={() => setColor(c)}
            aria-label={`Color ${c}`}
            style={{
              width: 18,
              height: 18,
              borderRadius: 999,
              background: workspaceColorVar[c],
              boxShadow: color === c
                ? `0 0 0 2px var(--color-loom-bg-from), 0 0 0 3px ${workspaceColorVar[c]}`
                : "0 0 0 1px rgba(255, 255, 255, 0.08)",
            }}
          />
        ))}
      </div>
      <div className="flex gap-1">
        {KINDS.map((k) => (
          <button
            key={k.value}
            type="button"
            onClick={() => setKind(k.value)}
            className="flex-1"
            style={{
              padding: "5px 8px",
              borderRadius: radius.control,
              fontSize: 11,
              border: `1px solid ${
                kind === k.value ? "var(--color-loom-accent)" : surface.hairline
              }`,
              background:
                kind === k.value
                  ? "color-mix(in srgb, var(--color-loom-accent) 12%, transparent)"
                  : "transparent",
              color: kind === k.value ? text.primary : text.muted,
            }}
          >
            {k.label}
          </button>
        ))}
      </div>
      <div className="flex gap-1 pt-1">
        <button
          type="button"
          onClick={onCancel}
          disabled={busy}
          className="flex-1"
          style={{
            padding: "5px 8px",
            borderRadius: radius.control,
            fontSize: 11,
            border: `1px solid ${surface.hairline}`,
            background: "transparent",
            color: text.muted,
          }}
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={submit}
          disabled={busy || !name.trim()}
          className="flex-1"
          style={{
            padding: "5px 8px",
            borderRadius: radius.control,
            fontSize: 11,
            border: "none",
            background: "var(--color-loom-accent)",
            color: "white",
            opacity: busy || !name.trim() ? 0.5 : 1,
          }}
        >
          Create
        </button>
      </div>
    </div>
  );
}
