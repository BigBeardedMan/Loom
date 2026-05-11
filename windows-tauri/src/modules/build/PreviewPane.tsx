import { useEffect, useRef, useState } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import { ipc, type Workspace } from "../../lib/ipc";

type Props = { workspace: Workspace; blockId?: string };

const LOAD_TIMEOUT_MS = 8000;

function defaultUrlFor(workspace: Workspace, autoIndex: number): string {
  if (workspace.previewUrl) return workspace.previewUrl;
  return `http://localhost:${3000 + autoIndex}`;
}

// Mirrors Loom/Build/PreviewPaneView.swift.
// URL bar with back/forward/refresh; iframe with white background and a
// load-failure overlay when navigation times out or the iframe errors.
export function PreviewPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const layout = useApp((s) => s.layout);
  const block = layout?.blocks.find((b) => b.id === blockId);
  const autoIndex = block?.autoPreviewIndex ?? 0;
  const [url, setUrl] = useState(defaultUrlFor(workspace, autoIndex));
  const [draft, setDraft] = useState(url);
  const [loadState, setLoadState] = useState<"loading" | "ok" | "error">("loading");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const frameRef = useRef<HTMLIFrameElement>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const fresh = defaultUrlFor(workspace, autoIndex);
    setUrl(fresh);
    setDraft(fresh);
  }, [workspace.id, workspace.previewUrl, autoIndex]);

  useEffect(() => {
    setLoadState("loading");
    setErrorMessage(null);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      setLoadState("error");
      setErrorMessage(`Could not reach ${url} within ${LOAD_TIMEOUT_MS / 1000} s.`);
    }, LOAD_TIMEOUT_MS);
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [url]);

  const reload = () => {
    if (frameRef.current) {
      setLoadState("loading");
      setErrorMessage(null);
      frameRef.current.src = url;
    }
  };

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
          onClick={reload}
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

      <div className="relative flex-1 min-h-0">
        <iframe
          ref={frameRef}
          src={url}
          className="h-full w-full border-0 bg-white"
          title={`Preview ${workspace.name}`}
          onLoad={() => {
            if (timerRef.current) clearTimeout(timerRef.current);
            setLoadState("ok");
          }}
          onError={() => {
            if (timerRef.current) clearTimeout(timerRef.current);
            setLoadState("error");
            setErrorMessage(`The preview at ${url} could not be loaded.`);
          }}
        />
        {loadState === "error" && (
          <div
            className="absolute inset-0 flex items-center justify-center"
            style={{
              background: "rgba(5,6,8,0.92)",
              color: "rgba(255,255,255,0.85)",
              padding: 24,
            }}
          >
            <div
              style={{
                maxWidth: 360,
                background: "rgba(255,255,255,0.04)",
                border: "1px solid rgba(255,255,255,0.08)",
                borderRadius: 10,
                padding: 18,
                textAlign: "center",
              }}
            >
              <Icons.failedCircle
                size={28}
                strokeWidth={1.4}
                style={{ color: "rgb(242,99,46)" }}
              />
              <div style={{ fontSize: 13, fontWeight: 600, marginTop: 8 }}>
                Preview unavailable
              </div>
              <div
                style={{
                  fontSize: 11,
                  color: "rgba(255,255,255,0.55)",
                  marginTop: 4,
                  wordBreak: "break-all",
                  fontFamily: "var(--font-mono)",
                }}
              >
                {url}
              </div>
              {errorMessage && (
                <div
                  style={{
                    fontSize: 11,
                    color: "rgba(255,255,255,0.5)",
                    marginTop: 8,
                  }}
                >
                  {errorMessage}
                </div>
              )}
              <button
                onClick={reload}
                style={{
                  marginTop: 12,
                  padding: "5px 12px",
                  fontSize: 11,
                  fontWeight: 600,
                  borderRadius: 6,
                  background: "var(--color-loom-accent)",
                  color: "white",
                  border: 0,
                }}
              >
                Retry
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
