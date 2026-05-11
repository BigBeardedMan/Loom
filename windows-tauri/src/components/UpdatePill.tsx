import { useState } from "react";
import { ipc, type UpdateInfo } from "../lib/ipc";
import { Icons } from "../lib/icons";
import { shadow } from "../lib/theme";
import { UpdateModal } from "../modules/update/UpdateModal";

type Props = { version: string };

// Mirrors the green update pill in Loom/Workspace/WorkspaceView.swift.
// Click opens a two-step modal: download → confirm → run NSIS installer.
export function UpdatePill({ version }: Props) {
  const [checking, setChecking] = useState(false);
  const [info, setInfo] = useState<UpdateInfo | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const open = async () => {
    if (checking) return;
    setChecking(true);
    setNotice(null);
    try {
      const i = await ipc.update.check();
      if (i) {
        setInfo(i);
      } else {
        setNotice("Loom is up to date.");
        setTimeout(() => setNotice(null), 3000);
      }
    } catch (e) {
      setNotice(String(e));
      setTimeout(() => setNotice(null), 5000);
    } finally {
      setChecking(false);
    }
  };

  const Icon = checking ? Icons.updateApplying : Icons.updateAvailable;

  return (
    <>
      <button
        data-no-drag
        onClick={open}
        disabled={checking}
        className="flex items-center gap-1.5 text-white"
        style={{
          background: "var(--color-ws-green)",
          boxShadow: shadow.pill,
          borderRadius: 999,
          padding: "5px 10px",
          fontSize: 12,
          fontWeight: 600,
          transition: "opacity 180ms ease-in-out",
        }}
        title={notice ?? `Update available: Loom ${version}`}
      >
        <Icon className={checking ? "animate-spin" : ""} size={11} strokeWidth={2.5} />
        <span>{checking ? "Checking…" : "Update"}</span>
        {!checking && (
          <span
            style={{
              fontFamily: "var(--font-mono)",
              fontSize: 10,
              opacity: 0.85,
              fontWeight: 500,
            }}
          >
            v{version}
          </span>
        )}
      </button>
      {info && <UpdateModal info={info} onClose={() => setInfo(null)} />}
    </>
  );
}
