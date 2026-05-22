import type { CSSProperties, ReactNode } from "react";
import { radius, shadow, surface } from "../lib/theme";

type Props = {
  children: ReactNode;
  className?: string;
  dragging?: boolean;
  dropTarget?: boolean;
  style?: CSSProperties;
  noShadow?: boolean;
};

// Mirrors LoomPanel view in Loom/Workspace/WorkspaceView.swift (lines 480-560).
// 12 px rounded panel with hairline border and macOS-spec drop shadow.
// Drag state swaps shadow + adds scale + glow border.
export function LoomPanel({
  children,
  className = "",
  dragging = false,
  dropTarget = false,
  style,
  noShadow = false,
}: Props) {
  const border = dragging
    ? "var(--color-ws-orange)"
    : dropTarget
      ? "var(--color-ws-blue)"
      : surface.hairline;
  const borderWidth = dragging || dropTarget ? 1.5 : 1;

  return (
    <div
      className={`flex flex-col overflow-hidden ${className}`}
      style={{
        background: surface.panel,
        border: `${borderWidth}px solid ${border}`,
        borderRadius: radius.panel,
        boxShadow: noShadow
          ? "none"
          : dragging
            ? shadow.panelDrag
            : shadow.panel,
        transform: dragging ? "scale(1.015)" : "none",
        transition:
          "box-shadow 180ms ease-out, transform 180ms ease-out, border-color 120ms ease-out",
        ...style,
      }}
    >
      {children}
    </div>
  );
}
