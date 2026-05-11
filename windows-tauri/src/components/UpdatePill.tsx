import { useState } from "react";
import { open as openExternal } from "@tauri-apps/plugin-shell";
import { ipc } from "../lib/ipc";
import { Icons } from "../lib/icons";
import { shadow } from "../lib/theme";

type Props = { version: string };

const RELEASES_URL = "https://github.com/BigBeardedMan/Loom/releases/latest";

// Mirrors the green update pill in Loom/Workspace/WorkspaceView.swift (lines 140-155).
// Tries the tauri-plugin-updater first; falls back to opening the GitHub
// release page if the in-app updater fails (e.g. missing signature).
export function UpdatePill({ version }: Props) {
  const [applying, setApplying] = useState(false);
  const Icon = applying ? Icons.updateApplying : Icons.updateAvailable;

  const apply = async () => {
    if (applying) return;
    setApplying(true);
    try {
      await ipc.update.apply();
    } catch (e) {
      console.warn("In-app update failed, opening release page", e);
      await openExternal(RELEASES_URL).catch(() => {});
      setApplying(false);
    }
  };

  return (
    <button
      data-no-drag
      onClick={apply}
      disabled={applying}
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
      title={`Update to Loom ${version}`}
    >
      <Icon
        className={applying ? "animate-spin" : ""}
        size={11}
        strokeWidth={2.5}
      />
      <span>{applying ? "Updating…" : "Update"}</span>
      {!applying && (
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
  );
}
