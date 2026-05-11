import { getCurrentWindow } from "@tauri-apps/api/window";
import { useApp } from "../lib/store";
import { LoomLogoMark } from "./LoomLogoMark";
import { UpdatePill } from "./UpdatePill";
import { Icons } from "../lib/icons";
import { text } from "../lib/theme";

const win = getCurrentWindow();

// Mirrors the hidden-titlebar macOS chrome: traffic lights on the left,
// drag region across the middle, Update pill + Settings on the right.
export function Titlebar() {
  const updatePill = useApp((s) => s.updatePill);
  const openSettings = useApp((s) => s.openSettings);

  return (
    <div
      className="titlebar flex items-center gap-3 px-3 no-select"
      style={{
        background: "transparent",
        borderBottom: "1px solid var(--color-loom-hairline)",
      }}
    >
      <TrafficLights />

      <div className="flex items-center gap-1.5">
        <LoomLogoMark size={18} />
        <span
          style={{
            fontSize: 13,
            fontWeight: 600,
            color: text.primary,
            letterSpacing: -0.1,
          }}
        >
          Loom
        </span>
      </div>

      <div className="flex-1" />

      {updatePill && <UpdatePill version={updatePill.version} />}

      <button
        data-no-drag
        onClick={openSettings}
        className="rounded-md p-1.5"
        style={{
          color: text.muted,
          transition: "color 120ms ease-out, background 120ms ease-out",
        }}
        onMouseEnter={(e) => {
          e.currentTarget.style.color = text.primary as string;
          e.currentTarget.style.background = "var(--color-loom-soft-panel)";
        }}
        onMouseLeave={(e) => {
          e.currentTarget.style.color = text.muted as string;
          e.currentTarget.style.background = "transparent";
        }}
        aria-label="Settings"
      >
        <Icons.settings size={15} strokeWidth={1.8} />
      </button>
    </div>
  );
}

function TrafficLights() {
  return (
    <div className="flex items-center gap-2" data-no-drag>
      <button
        onClick={() => win.close()}
        className="window-control"
        style={{ background: "#FF5F57" }}
        aria-label="Close"
      >
        <Icons.close size={8} color="#4D0000" strokeWidth={3} />
      </button>
      <button
        onClick={() => win.minimize()}
        className="window-control"
        style={{ background: "#FFBD2E" }}
        aria-label="Minimize"
      >
        <Icons.minimize size={8} color="#995A00" strokeWidth={3} />
      </button>
      <button
        onClick={async () => {
          const maxed = await win.isMaximized();
          if (maxed) win.unmaximize();
          else win.maximize();
        }}
        className="window-control"
        style={{ background: "#28C840" }}
        aria-label="Maximize"
      >
        <Icons.plus size={8} color="#006500" strokeWidth={3} />
      </button>
    </div>
  );
}
