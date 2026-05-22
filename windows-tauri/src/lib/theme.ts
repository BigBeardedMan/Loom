// Mirrors Loom/App/LoomTheme.swift and Loom/Workspace/WorkspaceModel.swift.
// Single source of truth for tokens consumed from React components.
// Any visual constant referenced in more than one place lives here.

export type WorkspaceColor =
  | "orange"
  | "green"
  | "blue"
  | "pink"
  | "yellow"
  | "purple";

export const workspaceColorHex: Record<WorkspaceColor, string> = {
  orange: "#F2632E",
  green: "#3BDB75",
  blue: "#2E80F5",
  pink: "#F2338C",
  yellow: "#F5C433",
  purple: "#9E66F2",
};

export const workspaceColorVar: Record<WorkspaceColor, string> = {
  orange: "var(--color-ws-orange)",
  green: "var(--color-ws-green)",
  blue: "var(--color-ws-blue)",
  pink: "var(--color-ws-pink)",
  yellow: "var(--color-ws-yellow)",
  purple: "var(--color-ws-purple)",
};

export const surface = {
  panel: "var(--color-loom-panel)",
  softPanel: "var(--color-loom-soft-panel)",
  inset: "var(--color-loom-inset)",
  hairline: "var(--color-loom-hairline)",
  terminal: "var(--color-loom-terminal)",
  bgFrom: "var(--color-loom-bg-from)",
  bgTo: "var(--color-loom-bg-to)",
};

export const text = {
  primary: "var(--color-loom-text)",
  muted: "var(--color-loom-text-muted)",
  tertiary: "var(--color-loom-text-tertiary)",
};

export const radius = {
  panel: 12,
  row: 8,
  control: 7,
};

export const shadow = {
  panel: "0 10px 22px rgba(0, 0, 0, 0.30)",
  panelDrag: "0 18px 34px rgba(0, 0, 0, 0.55)",
  pill: "0 4px 10px rgba(59, 219, 117, 0.44)",
};

export const sidebar = {
  width: 268,
  paddingH: 12,
  paddingV: 12,
  rowPaddingH: 10,
  rowPaddingV: 9,
};

export const paneTitleBar = {
  paddingH: 12,
  paddingV: 9,
  titleSize: 12,
  titleWeight: 600,
};

export const workspaceDot = {
  size: 9,
};

export const cockpit = {
  gap: 12,
  outerPadding: 12,
  minBlockWidth: 140,
  minBlockHeight: 160,
};

export const topbar = {
  height: 38,
  gap: 10,
};

export const modal = {
  commandPalette: { width: 560, height: 420 },
  settings: { width: 620, height: 460 },
};

export const fonts = {
  sans: "var(--font-sans)",
  mono: "var(--font-mono)",
};
