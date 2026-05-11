import { useEffect, useState } from "react";
import CodeMirror from "@uiw/react-codemirror";
import { markdown } from "@codemirror/lang-markdown";
import { EditorView } from "@codemirror/view";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, type IdeaNote, type Workspace } from "../../lib/ipc";

type Props = { workspace: Workspace; blockId?: string };

// Mirrors Loom/Notes/NotesPaneView.swift.
// Tab strip at top, editor below. Inky background, yellow lightbulb on active tab.
export function NotesPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [notes, setNotes] = useState<IdeaNote[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const load = async () => {
    const list = await ipc.notes.list(workspace.id);
    setNotes(list);
    if (list.length === 0) setSelectedId(null);
    else if (!selectedId || !list.find((n) => n.id === selectedId))
      setSelectedId(list[0].id);
  };

  useEffect(() => {
    setSelectedId(null);
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.id]);

  const selected = notes.find((n) => n.id === selectedId);

  const createNote = async () => {
    const note = await ipc.notes.upsert({
      workspaceId: workspace.id,
      title: "New note",
      body: "",
    });
    await load();
    setSelectedId(note.id);
  };

  const updateTitle = async (title: string) => {
    if (!selected) return;
    const updated = await ipc.notes.upsert({
      id: selected.id,
      workspaceId: workspace.id,
      title,
      body: selected.body,
    });
    setNotes((prev) => prev.map((n) => (n.id === updated.id ? updated : n)));
  };

  const updateBody = async (body: string) => {
    if (!selected) return;
    if (blockId) setBlockStatus(blockId, "active");
    const updated = await ipc.notes.upsert({
      id: selected.id,
      workspaceId: workspace.id,
      title: selected.title,
      body,
    });
    setNotes((prev) => prev.map((n) => (n.id === updated.id ? updated : n)));
    if (blockId)
      setTimeout(() => setBlockStatus(blockId, "idle"), 600);
  };

  const removeNote = async (id: string) => {
    await ipc.notes.delete(id);
    await load();
  };

  return (
    <div className="flex h-full flex-col" style={{ background: "#050608" }}>
      <div
        className="flex items-center gap-1 flex-none"
        style={{
          padding: "6px",
          background: "rgba(0, 0, 0, 0.32)",
          borderBottom: "1px solid rgba(255, 255, 255, 0.10)",
        }}
      >
        <div className="scrollbar-thin flex flex-1 gap-1 overflow-x-auto">
          {notes.map((note) => (
            <Tab
              key={note.id}
              note={note}
              active={selectedId === note.id}
              onClick={() => setSelectedId(note.id)}
              onClose={() => removeNote(note.id)}
            />
          ))}
        </div>
        <button
          onClick={createNote}
          aria-label="New note"
          style={{
            color: "rgba(255, 255, 255, 0.55)",
            padding: 4,
            borderRadius: 4,
          }}
        >
          <Icons.plus size={13} strokeWidth={2.2} />
        </button>
      </div>

      <div className="flex-1 min-h-0">
        {selected ? (
          <div className="flex h-full flex-col">
            <input
              value={selected.title}
              onChange={(e) => updateTitle(e.target.value)}
              className="flex-none focus:outline-none"
              style={{
                background: "transparent",
                color: "rgba(255, 255, 255, 0.9)",
                fontSize: 14,
                fontWeight: 600,
                padding: "14px 16px 6px",
                border: "none",
              }}
              placeholder="Untitled note"
            />
            <div className="flex-1 min-h-0">
              <CodeMirror
                value={selected.body}
                onChange={updateBody}
                extensions={[markdown(), notesEditorTheme]}
                theme="none"
                height="100%"
                style={{ height: "100%" }}
                basicSetup={{
                  lineNumbers: false,
                  foldGutter: false,
                  highlightActiveLine: false,
                  autocompletion: false,
                }}
              />
            </div>
          </div>
        ) : (
          <div
            className="flex h-full items-center justify-center"
            style={{ color: "rgba(255, 255, 255, 0.45)", fontSize: 12 }}
          >
            <div className="flex flex-col items-center gap-2">
              <Icons.lightbulb size={28} strokeWidth={1.2} />
              <span style={{ fontSize: 13, fontWeight: 500 }}>No note selected</span>
              <span style={{ fontSize: 11 }}>Click + to capture an idea.</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function Tab({
  note,
  active,
  onClick,
  onClose,
}: {
  note: IdeaNote;
  active: boolean;
  onClick: () => void;
  onClose: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="group flex items-center gap-1.5 flex-none"
      style={{
        padding: "5px 10px",
        borderRadius: 6,
        background: active ? "rgba(255, 255, 255, 0.10)" : "transparent",
        border: `1px solid ${active ? "rgba(255, 255, 255, 0.18)" : "transparent"}`,
        color: active ? "white" : "rgba(255, 255, 255, 0.6)",
        fontSize: 11,
        fontWeight: 500,
        maxWidth: 200,
      }}
    >
      <Icons.lightbulb
        size={10}
        strokeWidth={2}
        color={active ? "var(--color-ws-yellow)" : "rgba(255, 255, 255, 0.45)"}
      />
      <span className="truncate">{note.title || "Untitled"}</span>
      <span
        onClick={(e) => {
          e.stopPropagation();
          onClose();
        }}
        className="invisible rounded p-0.5 group-hover:visible"
        style={{ color: "rgba(255, 255, 255, 0.45)" }}
      >
        <Icons.close size={9} strokeWidth={2.5} />
      </span>
    </button>
  );
}

const notesEditorTheme = EditorView.theme(
  {
    "&": {
      backgroundColor: "transparent",
      color: "rgba(255, 255, 255, 0.86)",
      fontSize: "13px",
      height: "100%",
    },
    ".cm-scroller": {
      fontFamily: "var(--font-mono)",
      padding: "8px 16px 12px",
    },
    ".cm-content": { caretColor: "var(--color-ws-blue)" },
    ".cm-cursor": { borderLeftColor: "var(--color-ws-blue)" },
    "&.cm-focused .cm-selectionBackground, ::selection": {
      backgroundColor: "rgba(45, 128, 245, 0.30)",
    },
    ".cm-gutters": { display: "none" },
    ".cm-activeLine": { backgroundColor: "transparent" },
  },
  { dark: true }
);
