import { useState } from "react";
import {
  Plus,
  Folder,
  FolderOpen,
  Lightbulb,
  Eye,
  Trash2,
} from "lucide-react";
import {
  useApp,
  workspaceColorClass,
  workspaceKindLabel,
} from "../../lib/store";
import { ipc, type Workspace, type WorkspaceColor, type WorkspaceKind } from "../../lib/ipc";

export function WorkspaceSidebar() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const selectWorkspace = useApp((s) => s.selectWorkspace);
  const createWorkspace = useApp((s) => s.createWorkspace);
  const deleteWorkspace = useApp((s) => s.deleteWorkspace);
  const [creating, setCreating] = useState(false);

  return (
    <aside className="flex h-full w-60 flex-col border-r border-loom-border bg-loom-panel">
      <div className="flex items-center justify-between border-b border-loom-border px-3 py-2">
        <span className="text-xs font-medium uppercase tracking-wider text-loom-text-mute">
          Workspaces
        </span>
        <button
          className="rounded p-1 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text"
          onClick={() => setCreating(true)}
          aria-label="New workspace"
        >
          <Plus className="h-4 w-4" />
        </button>
      </div>

      <div className="scrollbar-thin flex-1 overflow-y-auto p-2">
        {workspaces.length === 0 && !creating && (
          <div className="px-2 py-6 text-center text-xs text-loom-text-mute">
            No workspaces yet. Click + to create one.
          </div>
        )}
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

      {creating && (
        <NewWorkspaceForm
          onCreate={async (input) => {
            await createWorkspace(
              input.name,
              input.folderPath,
              input.color,
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
  return (
    <div
      className={`group flex items-center gap-2 rounded-md px-2 py-1.5 cursor-pointer text-sm ${
        selected
          ? "bg-loom-panel-elev text-loom-text"
          : "text-loom-text-dim hover:bg-loom-panel-elev"
      }`}
      onClick={onSelect}
    >
      <div className={`h-2 w-2 rounded-full ${workspaceColorClass[workspace.colorName]}`} />
      <KindIcon kind={workspace.kindRaw} />
      <span className="truncate flex-1">{workspace.name}</span>
      {workspace.taskBadge > 0 && (
        <span className="rounded-full bg-loom-accent px-1.5 text-[10px] font-medium text-white">
          {workspace.taskBadge}
        </span>
      )}
      <button
        className="invisible rounded p-0.5 text-loom-text-mute hover:text-loom-text group-hover:visible"
        onClick={(e) => {
          e.stopPropagation();
          if (confirm(`Delete workspace "${workspace.name}"?`)) onDelete();
        }}
        aria-label="Delete workspace"
      >
        <Trash2 className="h-3 w-3" />
      </button>
    </div>
  );
}

function KindIcon({ kind }: { kind: Workspace["kindRaw"] }) {
  switch (kind) {
    case "code":
      return <FolderOpen className="h-3.5 w-3.5 text-loom-text-mute" />;
    case "ideas":
      return <Lightbulb className="h-3.5 w-3.5 text-loom-text-mute" />;
    case "review":
    case "build":
      return <Eye className="h-3.5 w-3.5 text-loom-text-mute" />;
    default:
      return <Folder className="h-3.5 w-3.5 text-loom-text-mute" />;
  }
}

const COLORS: WorkspaceColor[] = [
  "blue",
  "green",
  "orange",
  "pink",
  "purple",
  "yellow",
];
const KINDS: { value: WorkspaceKind; label: string }[] = [
  { value: "code", label: workspaceKindLabel.code },
  { value: "ideas", label: workspaceKindLabel.ideas },
  { value: "review", label: workspaceKindLabel.review },
];

function NewWorkspaceForm({
  onCreate,
  onCancel,
}: {
  onCreate: (input: {
    name: string;
    folderPath: string;
    color: WorkspaceColor;
    kind: WorkspaceKind;
  }) => Promise<void>;
  onCancel: () => void;
}) {
  const [name, setName] = useState("");
  const [folderPath, setFolderPath] = useState("");
  const [color, setColor] = useState<WorkspaceColor>("blue");
  const [kind, setKind] = useState<WorkspaceKind>("code");
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
    <div className="border-t border-loom-border bg-loom-panel-elev p-3">
      <div className="space-y-2">
        <input
          autoFocus
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Workspace name"
          className="w-full rounded-md border border-loom-border bg-loom-bg px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-loom-accent"
          onKeyDown={(e) => {
            if (e.key === "Enter") submit();
            if (e.key === "Escape") onCancel();
          }}
        />
        <div className="flex items-center gap-1">
          <button
            type="button"
            className="flex-1 truncate rounded-md border border-loom-border bg-loom-bg px-2 py-1 text-left text-xs text-loom-text-dim hover:text-loom-text"
            onClick={pickFolder}
          >
            {folderPath || "Pick folder…"}
          </button>
        </div>
        <div className="flex flex-wrap gap-1">
          {COLORS.map((c) => (
            <button
              key={c}
              type="button"
              className={`h-5 w-5 rounded-full ${workspaceColorClass[c]} ${
                color === c
                  ? "ring-2 ring-loom-text ring-offset-1 ring-offset-loom-panel-elev"
                  : ""
              }`}
              onClick={() => setColor(c)}
              aria-label={`Color ${c}`}
            />
          ))}
        </div>
        <div className="flex gap-1">
          {KINDS.map((k) => (
            <button
              key={k.value}
              type="button"
              className={`flex-1 rounded-md border px-2 py-1 text-xs ${
                kind === k.value
                  ? "border-loom-accent bg-loom-accent/10 text-loom-text"
                  : "border-loom-border text-loom-text-dim hover:text-loom-text"
              }`}
              onClick={() => setKind(k.value)}
            >
              {k.label}
            </button>
          ))}
        </div>
        <div className="flex gap-1 pt-1">
          <button
            type="button"
            className="flex-1 rounded-md border border-loom-border px-2 py-1 text-xs text-loom-text-dim hover:text-loom-text"
            onClick={onCancel}
            disabled={busy}
          >
            Cancel
          </button>
          <button
            type="button"
            className="flex-1 rounded-md bg-loom-accent px-2 py-1 text-xs text-white hover:opacity-90 disabled:opacity-50"
            onClick={submit}
            disabled={busy || !name.trim()}
          >
            Create
          </button>
        </div>
      </div>
    </div>
  );
}
