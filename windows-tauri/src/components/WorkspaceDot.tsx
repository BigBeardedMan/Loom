import { workspaceColorVar, workspaceDot } from "../lib/theme";
import type { WorkspaceColor } from "../lib/theme";

type Props = {
  color: WorkspaceColor;
  size?: number;
};

// Mirrors the inline circle in Loom/Workspace/WorkspaceSidebarView.swift
// (9 px disc colored by WorkspaceColor case).
export function WorkspaceDot({ color, size = workspaceDot.size }: Props) {
  return (
    <span
      className="inline-block flex-none rounded-full"
      style={{
        width: size,
        height: size,
        background: workspaceColorVar[color],
        boxShadow: `0 0 0 1px rgba(255, 255, 255, 0.08)`,
      }}
    />
  );
}
