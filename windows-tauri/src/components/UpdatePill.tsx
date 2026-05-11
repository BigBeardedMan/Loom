import { useState } from "react";
import { ipc } from "../lib/ipc";
import { Icons } from "../lib/icons";
import { shadow } from "../lib/theme";

type Props = { version: string };

// Mirrors the green update pill in Loom/App/LoomApp.swift (or UpdatePill view).
// Capsule, green bg, white text, drop shadow, swaps icon while applying.
export function UpdatePill({ version }: Props) {
  const [applying, setApplying] = useState(false);
  const Icon = applying ? Icons.updateApplying : Icons.updateAvailable;

  const apply = async () => {
    if (applying) return;
    setApplying(true);
    try {
      await ipc.update.apply();
    } catch {
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
        padding: "6px 10px",
        fontSize: 12,
        fontWeight: 600,
        transition: "opacity 180ms ease-in-out, transform 180ms ease-in-out",
      }}
    >
      <Icon
        className={applying ? "animate-spin" : ""}
        size={11}
        strokeWidth={2.5}
      />
      <span>{applying ? "Updating…" : `Update to ${version}`}</span>
    </button>
  );
}
