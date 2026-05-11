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
  orange: "#F24620",
  green: "#3ADB75",
  blue: "#2D80F5",
  pink: "#F23388",
  yellow: "#F5C533",
  purple: "#9E57F0",
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
  panel: 14,
  row: 8,
  control: 6,
};

export const shadow = {
  panel: "0 12px 18px rgba(0, 0, 0, 0.28)",
  panelDrag: "0 18px 28px rgba(0, 0, 0, 0.55)",
  pill: "0 4px 8px rgba(58, 219, 117, 0.5)",
};

export const sidebar = {
  width: 240,
  paddingH: 12,
  paddingV: 14,
  rowPaddingH: 10,
  rowPaddingV: 8,
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
  outerPadding: 14,
  minBlockWidth: 140,
  minBlockHeight: 160,
};

export const modal = {
  commandPalette: { width: 560, height: 420 },
  settings: { width: 620, height: 460 },
};

export const fonts = {
  sans: "var(--font-sans)",
  mono: "var(--font-mono)",
};
