import { useEffect, useState } from "react";
import Editor from "@monaco-editor/react";
import { File, FolderOpen, Save } from "lucide-react";
import { ipc, type FsNode, type Workspace } from "../../lib/ipc";

export function EditorPane({ workspace }: { workspace: Workspace }) {
  const [tree, setTree] = useState<FsNode | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [content, setContent] = useState<string>("");
  const [dirty, setDirty] = useState(false);

  useEffect(() => {
    if (!workspace.folderPath) {
      setTree(null);
      return;
    }
    ipc.fs.walk(workspace.folderPath, 6, false).then(setTree).catch(() => setTree(null));
  }, [workspace.folderPath]);

  const openFile = async (path: string) => {
    try {
      const text = await ipc.fs.read(path);
      setContent(text);
      setSelected(path);
      setDirty(false);
    } catch (e) {
      console.error(e);
    }
  };

  const save = async () => {
    if (!selected) return;
    await ipc.fs.write(selected, content);
    setDirty(false);
  };

  useEffect(() => {
    const onSave = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && (e.key === "s" || e.key === "S")) {
        e.preventDefault();
        save();
      }
    };
    window.addEventListener("keydown", onSave);
    return () => window.removeEventListener("keydown", onSave);
  });

  return (
    <div className="flex h-full flex-col bg-loom-bg">
      <div className="flex items-center justify-between border-b border-loom-border bg-loom-panel px-3 py-1.5 text-xs">
        <span className="font-medium uppercase tracking-wider text-loom-text-mute">
          Editor
        </span>
        {selected && (
          <button
            onClick={save}
            disabled={!dirty}
            className="flex items-center gap-1 rounded-md px-2 py-0.5 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text disabled:opacity-50"
          >
            <Save className="h-3 w-3" />
            Save
          </button>
        )}
      </div>

      <div className="flex flex-1 min-h-0">
        <div className="scrollbar-thin w-48 overflow-y-auto border-r border-loom-border bg-loom-panel text-xs">
          {!tree && (
            <div className="px-3 py-4 text-loom-text-mute">
              {workspace.folderPath
                ? "Loading…"
                : "No folder attached to this workspace."}
            </div>
          )}
          {tree && (
            <FileTree node={tree} depth={0} onOpen={openFile} selected={selected} />
          )}
        </div>
        <div className="flex-1 min-w-0">
          {selected ? (
            <Editor
              theme="vs-dark"
              path={selected}
              value={content}
              onChange={(v) => {
                setContent(v ?? "");
                setDirty(true);
              }}
              options={{
                minimap: { enabled: false },
                fontSize: 13,
                fontFamily: 'ui-monospace, "Cascadia Code", Menlo, monospace',
                wordWrap: "on",
                automaticLayout: true,
              }}
            />
          ) : (
            <div className="flex h-full items-center justify-center text-sm text-loom-text-mute">
              Select a file to edit.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function FileTree({
  node,
  depth,
  onOpen,
  selected,
}: {
  node: FsNode;
  depth: number;
  onOpen: (p: string) => void;
  selected: string | null;
}) {
  const [open, setOpen] = useState(depth < 1);
  if (!node.isDir) {
    return (
      <div
        className={`flex cursor-pointer items-center gap-1 px-2 py-0.5 hover:bg-loom-panel-elev ${
          selected === node.path ? "bg-loom-panel-elev text-loom-text" : "text-loom-text-dim"
        }`}
        style={{ paddingLeft: 8 + depth * 12 }}
        onClick={() => onOpen(node.path)}
      >
        <File className="h-3 w-3 flex-none" />
        <span className="truncate">{node.name}</span>
      </div>
    );
  }
  return (
    <div>
      <div
        className="flex cursor-pointer items-center gap-1 px-2 py-0.5 text-loom-text-dim hover:bg-loom-panel-elev"
        style={{ paddingLeft: 8 + depth * 12 }}
        onClick={() => setOpen((v) => !v)}
      >
        <FolderOpen className="h-3 w-3 flex-none" />
        <span className="truncate">{node.name}</span>
      </div>
      {open &&
        node.children?.map((child) => (
          <FileTree
            key={child.path}
            node={child}
            depth={depth + 1}
            onOpen={onOpen}
            selected={selected}
          />
        ))}
    </div>
  );
}
