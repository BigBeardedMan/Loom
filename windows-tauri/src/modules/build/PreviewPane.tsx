import { useEffect, useRef, useState } from "react";
import { RefreshCw, ArrowRight } from "lucide-react";
import { ipc, type Workspace } from "../../lib/ipc";

export function PreviewPane({ workspace }: { workspace: Workspace }) {
  const [url, setUrl] = useState(workspace.previewUrl || "http://localhost:3000");
  const [navTarget, setNavTarget] = useState(url);
  const frameRef = useRef<HTMLIFrameElement>(null);

  useEffect(() => {
    setUrl(workspace.previewUrl || "http://localhost:3000");
    setNavTarget(workspace.previewUrl || "http://localhost:3000");
  }, [workspace.id]);

  const persist = async (next: string) => {
    setUrl(next);
    await ipc.workspace.update(workspace.id, { previewUrl: next });
  };

  return (
    <div className="flex h-full flex-col bg-loom-bg">
      <div className="flex items-center gap-1 border-b border-loom-border bg-loom-panel px-2 py-1.5">
        <input
          value={navTarget}
          onChange={(e) => setNavTarget(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") persist(navTarget);
          }}
          className="flex-1 rounded-md border border-loom-border bg-loom-bg px-2 py-1 text-xs text-loom-text focus:border-loom-accent focus:outline-none"
          placeholder="http://localhost:…"
        />
        <button
          onClick={() => persist(navTarget)}
          className="rounded p-1.5 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text"
          aria-label="Go"
        >
          <ArrowRight className="h-4 w-4" />
        </button>
        <button
          onClick={() => {
            if (frameRef.current) frameRef.current.src = url;
          }}
          className="rounded p-1.5 text-loom-text-dim hover:bg-loom-panel-elev hover:text-loom-text"
          aria-label="Reload"
        >
          <RefreshCw className="h-4 w-4" />
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
