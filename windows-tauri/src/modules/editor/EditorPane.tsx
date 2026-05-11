import { useEffect, useState } from "react";
import Editor from "@monaco-editor/react";
import { Icons } from "../../lib/icons";
import { PaneTitleBar } from "../../components/PaneTitleBar";
import { surface, text } from "../../lib/theme";
import { ipc, type FsNode, type Workspace } from "../../lib/ipc";
import { FileTree } from "./FileTree";

// Mirrors Loom/Editor/EditorPaneView.swift.
// PaneTitleBar header, FileTree sidebar, Monaco editor right.
export function EditorPane({ workspace }: { workspace: Workspace }) {
  const [tree, setTree] = useState<FsNode | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [content, setContent] = useState("");
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
      const t = await ipc.fs.read(path);
      setContent(t);
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

  const filename = selected?.split(/[\\/]/).pop();

  return (
    <div className="flex h-full flex-col" style={{ background: surface.panel }}>
      <PaneTitleBar
        icon={<Icons.textCursor size={11} strokeWidth={2} color="var(--color-ws-blue)" />}
        title="Editor"
        subtitle={filename}
        right={
          selected && (
            <button
              onClick={save}
              disabled={!dirty}
              style={{
                fontSize: 11,
                fontWeight: 500,
                color: dirty ? text.primary : text.tertiary,
                padding: "2px 8px",
                borderRadius: 4,
                background: dirty ? surface.softPanel : "transparent",
                display: "flex",
                alignItems: "center",
                gap: 4,
                cursor: dirty ? "pointer" : "default",
              }}
            >
              <Icons.save size={11} strokeWidth={2} />
              Save
            </button>
          )
        }
      />

      <div className="flex flex-1 min-h-0">
        <div
          className="scrollbar-thin overflow-y-auto flex-none"
          style={{
            width: 200,
            background: surface.inset,
            borderRight: `1px solid ${surface.hairline}`,
            paddingTop: 4,
            paddingBottom: 4,
          }}
        >
          {!tree && (
            <div style={{ padding: 12, fontSize: 11, color: text.tertiary }}>
              {workspace.folderPath ? "Loading…" : "No folder attached."}
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
                fontFamily: "var(--font-mono), monospace",
                wordWrap: "on",
                automaticLayout: true,
                scrollBeyondLastLine: false,
                renderLineHighlight: "none",
                padding: { top: 8, bottom: 8 },
              }}
            />
          ) : (
            <div
              className="flex h-full items-center justify-center"
              style={{ fontSize: 12, color: text.tertiary }}
            >
              Select a file to edit.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
