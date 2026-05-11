import { useEffect, useRef, useState } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, type Workspace } from "../../lib/ipc";

type Props = { workspace: Workspace; blockId?: string };

// Mirrors Loom/Build/PreviewPaneView.swift.
// URL bar with back/forward/refresh; iframe with white background.
export function PreviewPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [url, setUrl] = useState(workspace.previewUrl || "http://localhost:3000");
  const [draft, setDraft] = useState(url);
  const frameRef = useRef<HTMLIFrameElement>(null);

  useEffect(() => {
    const fresh = workspace.previewUrl || "http://localhost:3000";
    setUrl(fresh);
    setDraft(fresh);
  }, [workspace.id, workspace.previewUrl]);

  const navigate = async (next: string) => {
    setUrl(next);
    await ipc.workspace.update(workspace.id, { previewUrl: next });
  };

  useEffect(() => {
    if (!blockId) return;
    setBlockStatus(blockId, "idle");
  }, [blockId, setBlockStatus]);

  return (
    <div className="flex h-full flex-col" style={{ background: "#050608" }}>
      <div
        className="flex items-center gap-1.5 flex-none"
        style={{
          padding: "8px 10px",
          background: "rgba(0, 0, 0, 0.32)",
          borderBottom: "1px solid rgba(255, 255, 255, 0.10)",
        }}
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") navigate(draft);
          }}
          placeholder="http://localhost:…"
          className="flex-1 focus:outline-none"
          style={{
            background: "rgba(255, 255, 255, 0.06)",
            border: "1px solid rgba(255, 255, 255, 0.10)",
            borderRadius: 6,
            padding: "5px 10px",
            fontSize: 12,
            fontFamily: "var(--font-mono)",
            color: "rgba(255, 255, 255, 0.9)",
          }}
        />
        <button
          onClick={() => navigate(draft)}
          aria-label="Go"
          style={{
            padding: 6,
            borderRadius: 4,
            color: "rgba(255, 255, 255, 0.55)",
          }}
        >
          <Icons.go size={14} strokeWidth={2} />
        </button>
        <button
          onClick={() => {
            if (frameRef.current) frameRef.current.src = url;
          }}
          aria-label="Reload"
          style={{
            padding: 6,
            borderRadius: 4,
            color: "rgba(255, 255, 255, 0.55)",
          }}
        >
          <Icons.refresh size={14} strokeWidth={2} />
        </button>
      </div>

      <iframe
        ref={frameRef}
        src={url}
        className="flex-1 border-0 bg-white"
        title={`Preview ${workspace.name}`}
      />
    </div>
  );
}
