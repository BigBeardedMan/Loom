import { useEffect, useState } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { markdown } from "@codemirror/lang-markdown";
import { oneDark } from "@codemirror/theme-one-dark";
import { Plus, Trash2 } from "lucide-react";
import { ipc, type IdeaNote, type Workspace } from "../../lib/ipc";

export function NotesPane({ workspace }: { workspace: Workspace }) {
  const [notes, setNotes] = useState<IdeaNote[]>([]);
  const [selected, setSelected] = useState<IdeaNote | null>(null);

  const load = async () => {
    const list = await ipc.notes.list(workspace.id);
    setNotes(list);
    if (!selected && list.length > 0) setSelected(list[0]);
    if (selected && !list.find((n) => n.id === selected.id))
      setSelected(list[0] ?? null);
  };

  useEffect(() => {
    setSelected(null);
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.id]);

  const createNote = async () => {
    const note = await ipc.notes.upsert({
      workspaceId: workspace.id,
      title: "New note",
      body: "",
    });
    await load();
    setSelected(note);
  };

  const updateBody = async (body: string) => {
    if (!selected) return;
    const updated = await ipc.notes.upsert({
      id: selected.id,
      workspaceId: workspace.id,
      title: selected.title,
      body,
    });
    setSelected(updated);
    setNotes((prev) => prev.map((n) => (n.id === updated.id ? updated : n)));
  };

  const updateTitle = async (title: string) => {
    if (!selected) return;
    const updated = await ipc.notes.upsert({
      id: selected.id,
      workspaceId: workspace.id,
      title,
      body: selected.body,
    });
    setSelected(updated);
    setNotes((prev) => prev.map((n) => (n.id === updated.id ? updated : n)));
  };

  const remove = async (id: string) => {
    await ipc.notes.delete(id);
    await load();
  };

  return (
    <div className="flex h-full bg-loom-bg">
      <div className="flex w-56 flex-col border-r border-loom-border bg-loom-panel">
        <div className="flex items-center justify-between border-b border-loom-border px-3 py-1.5">
          <span className="text-xs font-medium uppercase tracking-wider text-loom-text-mute">
            Notes
          </span>
          <button
            onClick={createNote}
            className="rounded p-1 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text"
            aria-label="New note"
          >
            <Plus className="h-3.5 w-3.5" />
          </button>
        </div>
        <div className="scrollbar-thin flex-1 overflow-y-auto p-1">
          {notes.length === 0 && (
            <div className="px-2 py-4 text-center text-xs text-loom-text-mute">
              No notes yet.
            </div>
          )}
          {notes.map((n) => (
            <div
              key={n.id}
              className={`group flex cursor-pointer items-center gap-1 rounded px-2 py-1 text-xs ${
                selected?.id === n.id
                  ? "bg-loom-panel-elev text-loom-text"
                  : "text-loom-text-dim hover:bg-loom-panel-elev"
              }`}
              onClick={() => setSelected(n)}
            >
              <span className="flex-1 truncate">{n.title || "Untitled"}</span>
              <button
                className="invisible rounded p-0.5 text-loom-text-mute hover:text-loom-text group-hover:visible"
                onClick={(e) => {
                  e.stopPropagation();
                  remove(n.id);
                }}
              >
                <Trash2 className="h-3 w-3" />
              </button>
            </div>
          ))}
        </div>
      </div>
      <div className="flex flex-1 flex-col">
        {selected ? (
          <>
            <input
              value={selected.title}
              onChange={(e) => updateTitle(e.target.value)}
              className="border-b border-loom-border bg-transparent px-4 py-2 text-base text-loom-text outline-none"
            />
            <div className="flex-1 min-h-0">
              <CodeMirror
                value={selected.body}
                onChange={updateBody}
                extensions={[markdown()]}
                theme={oneDark}
                height="100%"
                style={{ height: "100%" }}
                basicSetup={{
                  lineNumbers: false,
                  foldGutter: false,
                  highlightActiveLine: false,
                }}
              />
            </div>
          </>
        ) : (
          <div className="flex flex-1 items-center justify-center text-sm text-loom-text-mute">
            Create a note to begin.
          </div>
        )}
      </div>
    </div>
  );
}
