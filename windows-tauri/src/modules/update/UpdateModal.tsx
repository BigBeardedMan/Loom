import { useEffect, useRef, useState } from "react";
import { ipc, on, type UpdateInfo } from "../../lib/ipc";
import { Icons } from "../../lib/icons";

type Step = "downloading" | "installing" | "error";

type Props = {
  info: UpdateInfo;
  onClose: () => void;
};

// One-click in-place update. Clicking the green Update pill drops the user
// here: the modal kicks off the download immediately, then hands the staged
// NSIS installer to the silent updater helper, which closes Loom, installs,
// and relaunches. No NSIS wizard, no double-click.
export function UpdateModal({ info, onClose }: Props) {
  const [step, setStep] = useState<Step>("downloading");
  const [progress, setProgress] = useState({ downloaded: 0, total: info.sizeBytes });
  const [error, setError] = useState<string | null>(null);
  const started = useRef(false);

  useEffect(() => {
    let off: (() => void) | undefined;
    on<{ downloaded: number; total: number }>("update/progress", (p) => {
      setProgress(p);
    }).then((u) => {
      off = u;
    });
    return () => off?.();
  }, []);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    (async () => {
      try {
        const path = await ipc.update.downloadAndStage(
          info.downloadUrl,
          info.assetName
        );
        setStep("installing");
        // Hand the installer to the silent relauncher. ipc returns once the
        // helper is spawned; Loom then exits and the helper takes over.
        await ipc.update.runInstaller(path, true);
      } catch (e) {
        setError(String(e));
        setStep("error");
      }
    })();
  }, [info.assetName, info.downloadUrl]);

  const pct =
    progress.total > 0
      ? Math.min(100, Math.round((progress.downloaded / progress.total) * 100))
      : 0;

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.45)", zIndex: 60 }}
      onClick={step === "error" ? onClose : undefined}
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
          <Icons.updateAvailable
            size={18}
            strokeWidth={2.2}
            style={{ color: "var(--color-ws-green)" }}
          />
          <h2 style={{ fontSize: 15, fontWeight: 600 }}>
            Updating Loom to {info.version}
          </h2>
        </header>

        <p style={{ fontSize: 12, color: "rgba(255,255,255,0.65)", marginBottom: 14 }}>
          {step === "downloading"
            ? `Downloading ${fmtBytes(info.sizeBytes)} for ${info.assetName.includes("arm64") ? "ARM64" : "x64"}…`
            : step === "installing"
              ? "Closing Loom and installing the new version. Loom will relaunch automatically."
              : "Update failed. Try again, or grab the latest build from the release page."}
        </p>

        {step !== "error" && (
          <div style={{ marginBottom: 16 }}>
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
                  width: step === "installing" ? "100%" : `${pct}%`,
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
              {step === "downloading"
                ? `${fmtBytes(progress.downloaded)} / ${fmtBytes(progress.total)} (${pct}%)`
                : "Installing…"}
            </div>
          </div>
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
          {step === "error" && (
            <>
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
                Close
              </button>
              <button
                onClick={() => ipc.shell.open(info.releaseNotesUrl).catch(() => {})}
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
            </>
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
