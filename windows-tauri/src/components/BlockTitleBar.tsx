import type { ReactNode } from "react";
import { Icons } from "../lib/icons";
import { surface, text, workspaceColorVar } from "../lib/theme";
import type { Panel } from "../lib/store";

type Status = "idle" | "active" | "warning";

type Props = {
  kind: Panel;
  title: string;
  status?: Status;
  variant?: "light" | "dark";
  onClose?: () => void;
  dragHandleProps?: Record<string, unknown>;
  right?: ReactNode;
};

const PANEL_META: Record<
  Panel,
  { icon: keyof typeof Icons; color: string }
> = {
  terminal: { icon: "terminal", color: workspaceColorVar.green },
  editor: { icon: "textCursor", color: workspaceColorVar.blue },
  tasks: { icon: "checkCircle", color: workspaceColorVar.orange },
  agent: { icon: "sparkles", color: workspaceColorVar.purple },
  notes: { icon: "lightbulb", color: workspaceColorVar.yellow },
  preview: { icon: "eye", color: workspaceColorVar.pink },
  commands: { icon: "listBulletRect", color: workspaceColorVar.blue },
};

const STATUS_COLOR: Record<Status, string> = {
  idle: "transparent",
  active: "var(--color-ws-green)",
  warning: "var(--color-ws-orange)",
};

// Mirrors the SwiftUI block title bar in Loom/Workspace/WorkspaceView.swift
// (lines 535-565): icon left + title + status dot + close (×) + drag handle.
export function BlockTitleBar({
  kind,
  title,
  status = "idle",
  variant = "light",
  onClose,
  dragHandleProps,
  right,
}: Props) {
  const meta = PANEL_META[kind];
  const Icon = Icons[meta.icon];
  const bg = variant === "dark" ? "rgba(0, 0, 0, 0.32)" : "rgba(0, 0, 0, 0.16)";
  const border = variant === "dark" ? "rgba(255, 255, 255, 0.10)" : surface.hairline;

  return (
    <div
      className="flex items-center gap-2 flex-none"
      style={{
        padding: "8px 12px",
        background: bg,
        borderBottom: `1px solid ${border}`,
      }}
    >
      <Icon size={11} strokeWidth={2.2} color={meta.color} />
      <span
        className="truncate"
        style={{
          fontSize: 12,
          fontWeight: 600,
          color: variant === "dark" ? "rgba(255,255,255,0.94)" : text.primary,
        }}
      >
        {title}
      </span>
      <span
        style={{
          width: 7,
          height: 7,
          borderRadius: 999,
          background: STATUS_COLOR[status],
          boxShadow:
            status === "active"
              ? "0 0 8px var(--color-ws-green)"
              : "none",
          transition: "background 180ms ease-out, box-shadow 180ms ease-out",
        }}
        aria-label={`Status: ${status}`}
      />

      <div className="ml-auto flex items-center gap-1">
        {right}
        {onClose && (
          <button
            onClick={onClose}
            aria-label="Close block"
            style={{
              padding: 2,
              borderRadius: 4,
              color:
                variant === "dark"
                  ? "rgba(255,255,255,0.55)"
                  : text.muted,
            }}
          >
            <Icons.close size={11} strokeWidth={2.2} />
          </button>
        )}
        {dragHandleProps && (
          <button
            {...dragHandleProps}
            aria-label="Drag block"
            style={{
              padding: 2,
              borderRadius: 4,
              cursor: "grab",
              color:
                variant === "dark"
                  ? "rgba(255,255,255,0.45)"
                  : text.tertiary,
            }}
          >
            <Icons.gridDrag size={11} strokeWidth={2} />
          </button>
        )}
      </div>
    </div>
  );
}
