import { useEffect, useState } from "react";
import { open as openExternal } from "@tauri-apps/plugin-shell";
import { ipc, on, type UpdateInfo } from "../../lib/ipc";
import { Icons } from "../../lib/icons";

type Step = "info" | "downloading" | "ready" | "error";

type Props = {
  info: UpdateInfo;
  onClose: () => void;
};

export function UpdateModal({ info, onClose }: Props) {
  const [step, setStep] = useState<Step>("info");
  const [progress, setProgress] = useState({ downloaded: 0, total: info.sizeBytes });
  const [error, setError] = useState<string | null>(null);
  const [stagedPath, setStagedPath] = useState<string | null>(null);

  useEffect(() => {
    let off: (() => void) | undefined;
    on<{ downloaded: number; total: number }>("update/progress", (p) => {
      setProgress(p);
    }).then((u) => {
      off = u;
    });
    return () => off?.();
  }, []);

  const download = async () => {
    setStep("downloading");
    setError(null);
    try {
      const path = await ipc.update.downloadAndStage(info.downloadUrl, info.assetName);
      setStagedPath(path);
      setStep("ready");
    } catch (e) {
      setError(String(e));
      setStep("error");
    }
  };

  const install = async () => {
    if (!stagedPath) return;
    try {
      await ipc.update.runInstaller(stagedPath, true);
    } catch (e) {
      setError(String(e));
      setStep("error");
    }
  };

  const pct = progress.total > 0 ? Math.min(100, Math.round((progress.downloaded / progress.total) * 100)) : 0;

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.45)", zIndex: 60 }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: 440,
          background: "var(--color-loom-panel)",
          color: "var(--color-loom-text)",
          border: "1px solid var(--color-loom-hairline)",
          borderRadius: 14,
          padding: 22,
          boxShadow: "0 20px 50px rgba(0,0,0,0.45)",
        }}
      >
        <header className="flex items-center gap-2" style={{ marginBottom: 12 }}>
          <Icons.updateAvailable size={18} strokeWidth={2.2} style={{ color: "var(--color-ws-green)" }} />
          <h2 style={{ fontSize: 15, fontWeight: 600 }}>
            Loom {info.version} available
          </h2>
        </header>
        <p style={{ fontSize: 12, color: "rgba(255,255,255,0.65)", marginBottom: 12 }}>
          You're currently running v{info.currentVersion}. Download {fmtBytes(info.sizeBytes)} for{" "}
          {info.assetName.includes("arm64") ? "ARM64" : "x64"}.{" "}
          <button
            onClick={() => openExternal(info.releaseNotesUrl).catch(() => {})}
            style={{
              color: "rgb(120, 170, 245)",
              fontSize: 12,
              textDecoration: "underline",
              background: "none",
              border: 0,
              padding: 0,
            }}
          >
            Release notes
          </button>
          .
        </p>

        {info.notes && step === "info" && (
          <pre
            className="scrollbar-thin"
            style={{
              fontSize: 11,
              fontFamily: "var(--font-mono)",
              color: "rgba(255,255,255,0.6)",
              background: "rgba(255,255,255,0.04)",
              border: "1px solid rgba(255,255,255,0.06)",
              borderRadius: 8,
              padding: "8px 10px",
              maxHeight: 140,
              overflow: "auto",
              whiteSpace: "pre-wrap",
              marginBottom: 14,
            }}
          >
            {info.notes}
          </pre>
        )}

        {step === "downloading" && (
          <div style={{ marginBottom: 14 }}>
            <div
              style={{
                height: 6,
                borderRadius: 999,
                background: "rgba(255,255,255,0.08)",
                overflow: "hidden",
              }}
            >
              <div
                style={{
                  width: `${pct}%`,
                  height: "100%",
                  background: "var(--color-ws-green)",
                  transition: "width 120ms ease-out",
                }}
              />
            </div>
            <div
              style={{
                marginTop: 6,
                fontSize: 11,
                color: "rgba(255,255,255,0.55)",
                fontFamily: "var(--font-mono)",
              }}
            >
              {fmtBytes(progress.downloaded)} / {fmtBytes(progress.total)} ({pct}%)
            </div>
          </div>
        )}

        {step === "ready" && (
          <p style={{ fontSize: 12, color: "rgba(255,255,255,0.7)", marginBottom: 14 }}>
            Download complete. Installing will close Loom and run the NSIS installer. The wizard
            will offer to relaunch Loom when it finishes.
          </p>
        )}

        {step === "error" && (
          <div
            style={{
              padding: "10px 12px",
              background: "rgba(242,70,32,0.15)",
              border: "1px solid rgba(242,70,32,0.4)",
              borderRadius: 8,
              fontSize: 12,
              color: "rgba(255,160,140,0.9)",
              marginBottom: 14,
              whiteSpace: "pre-wrap",
              fontFamily: "var(--font-mono)",
            }}
          >
            {error}
          </div>
        )}

        <footer className="flex justify-end gap-2">
          <button
            onClick={onClose}
            style={{
              padding: "6px 14px",
              fontSize: 12,
              fontWeight: 500,
              borderRadius: 8,
              background: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.10)",
              color: "rgba(255,255,255,0.85)",
            }}
          >
            {step === "ready" ? "Install later" : "Cancel"}
          </button>
          {step === "info" && (
            <button
              onClick={download}
              style={{
                padding: "6px 14px",
                fontSize: 12,
                fontWeight: 600,
                borderRadius: 8,
                background: "var(--color-ws-green)",
                color: "white",
                border: 0,
              }}
            >
              Download
            </button>
          )}
          {step === "ready" && (
            <button
              onClick={install}
              style={{
                padding: "6px 14px",
                fontSize: 12,
                fontWeight: 600,
                borderRadius: 8,
                background: "var(--color-ws-green)",
                color: "white",
                border: 0,
              }}
            >
              Install now
            </button>
          )}
          {step === "error" && (
            <button
              onClick={() => openExternal(info.releaseNotesUrl).catch(() => {})}
              style={{
                padding: "6px 14px",
                fontSize: 12,
                fontWeight: 600,
                borderRadius: 8,
                background: "var(--color-ws-green)",
                color: "white",
                border: 0,
              }}
            >
              Open release page
            </button>
          )}
        </footer>
      </div>
    </div>
  );
}

function fmtBytes(n: number): string {
  if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB";
  if (n >= 1024) return (n / 1024).toFixed(0) + " KB";
  return n + " B";
}
