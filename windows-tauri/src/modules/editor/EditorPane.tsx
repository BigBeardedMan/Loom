import { useEffect, useState } from "react";
import Editor from "@monaco-editor/react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { surface, text } from "../../lib/theme";
import { ipc, on, type FsNode, type Workspace } from "../../lib/ipc";
import { FileTree } from "./FileTree";

type Props = { workspace: Workspace; blockId?: string };

// Mirrors Loom/Editor/EditorPaneView.swift.
// File tree on the left, Monaco on the right; saves via Ctrl+S; reloads on
// external file changes via the Rust `notify` watcher.
export function EditorPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [tree, setTree] = useState<FsNode | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [content, setContent] = useState("");
  const [dirty, setDirty] = useState(false);
  const [externalChange, setExternalChange] = useState(false);

  useEffect(() => {
    if (!workspace.folderPath) {
      setTree(null);
      return;
    }
    ipc.fs.walk(workspace.folderPath, 6, false).then(setTree).catch(() => setTree(null));

    let watchId: string | null = null;
    let unlistenChange: (() => void) | null = null;
    (async () => {
      try {
        watchId = await ipc.fs.watchStart(workspace.folderPath);
        unlistenChange = await on<{ paths: string[] }>(
          `fs://${watchId}/change`,
          (ev) => {
            if (!selected) return;
            if (ev.paths.includes(selected)) setExternalChange(true);
          }
        );
      } catch {}
    })();
    return () => {
      if (unlistenChange) unlistenChange();
      if (watchId) ipc.fs.watchStop(watchId).catch(() => {});
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.folderPath]);

  useEffect(() => {
    if (!blockId) return;
    setBlockStatus(blockId, dirty ? "active" : "idle");
  }, [dirty, blockId, setBlockStatus]);

  const openFile = async (path: string) => {
    try {
      const t = await ipc.fs.read(path);
      setContent(t);
      setSelected(path);
      setDirty(false);
      setExternalChange(false);
    } catch (e) {
      console.error(e);
    }
  };

  const save = async () => {
    if (!selected) return;
    await ipc.fs.write(selected, content);
    setDirty(false);
  };

  const reload = async () => {
    if (!selected) return;
    const t = await ipc.fs.read(selected);
    setContent(t);
    setDirty(false);
    setExternalChange(false);
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
    <div className="flex h-full" style={{ background: surface.panel }}>
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
        {tree && <FileTree node={tree} depth={0} onOpen={openFile} selected={selected} />}
      </div>
      <div className="flex flex-1 flex-col min-w-0">
        {selected && (
          <div
            className="flex items-center gap-2 flex-none"
            style={{
              padding: "6px 12px",
              background: surface.inset,
              borderBottom: `1px solid ${surface.hairline}`,
            }}
          >
            <span
              className="truncate font-mono"
              style={{ fontSize: 11, color: text.muted, flex: 1 }}
            >
              {selected.split(/[\\/]/).pop()}
            </span>
            {externalChange && (
              <button
                onClick={reload}
                style={{
                  padding: "3px 8px",
                  borderRadius: 4,
                  fontSize: 11,
                  fontWeight: 500,
                  background: "var(--color-ws-orange)",
                  color: "#fff",
                  border: "none",
                  display: "flex",
                  alignItems: "center",
                  gap: 4,
                }}
                title="File changed on disk"
              >
                <Icons.refresh size={11} strokeWidth={2.2} />
                Reload
              </button>
            )}
            <button
              onClick={save}
              disabled={!dirty}
              style={{
                fontSize: 11,
                fontWeight: 500,
                color: dirty ? text.primary : text.tertiary,
                padding: "3px 8px",
                borderRadius: 4,
                background: dirty ? surface.softPanel : "transparent",
                display: "flex",
                alignItems: "center",
                gap: 4,
                cursor: dirty ? "pointer" : "default",
                border: "none",
              }}
            >
              <Icons.save size={11} strokeWidth={2} />
              {dirty ? "Save" : "Saved"}
            </button>
          </div>
        )}
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
  );
}
