import { useEffect, useState, type ReactNode } from "react";
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
  onRename?: (next: string) => void;
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
// Double-clicking the title opens an inline rename input.
export function BlockTitleBar({
  kind,
  title,
  status = "idle",
  variant = "light",
  onClose,
  onRename,
  dragHandleProps,
  right,
}: Props) {
  const meta = PANEL_META[kind];
  const Icon = Icons[meta.icon];
  const bg = variant === "dark" ? "rgba(0, 0, 0, 0.32)" : "rgba(0, 0, 0, 0.16)";
  const border = variant === "dark" ? "rgba(255, 255, 255, 0.10)" : surface.hairline;

  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(title);
  useEffect(() => {
    setDraft(title);
  }, [title]);
  const commit = () => {
    setEditing(false);
    const next = draft.trim();
    if (next && next !== title && onRename) onRename(next);
    else setDraft(title);
  };
  const cancel = () => {
    setEditing(false);
    setDraft(title);
  };

  // The whole title bar is the drag handle when dragHandleProps is supplied.
  // Interactive children (rename input, close button, dedicated grip) call
  // stopPropagation on pointer events so they keep their own click behavior
  // without starting a block drag.
  const stopBarDrag = (e: React.PointerEvent | React.MouseEvent) => {
    e.stopPropagation();
  };
  const barHandleProps = dragHandleProps ?? {};

  return (
    <div
      className="flex items-center gap-2 flex-none"
      style={{
        padding: "8px 12px",
        background: bg,
        borderBottom: `1px solid ${border}`,
        cursor: dragHandleProps ? "grab" : "default",
        touchAction: dragHandleProps ? "none" : undefined,
        userSelect: "none",
      }}
      {...barHandleProps}
    >
      <Icon size={11} strokeWidth={2.2} color={meta.color} />
      {editing && onRename ? (
        <input
          autoFocus
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onPointerDown={stopBarDrag}
          onMouseDown={stopBarDrag}
          onKeyDown={(e) => {
            if (e.key === "Enter") commit();
            else if (e.key === "Escape") cancel();
          }}
          style={{
            flex: 1,
            background: "var(--color-loom-bg-from)",
            border: `1px solid ${border}`,
            borderRadius: 4,
            padding: "2px 6px",
            fontSize: 12,
            fontWeight: 600,
            color: variant === "dark" ? "rgba(255,255,255,0.94)" : text.primary,
            outline: "none",
          }}
        />
      ) : (
        <span
          className="truncate"
          onDoubleClick={onRename ? () => setEditing(true) : undefined}
          style={{
            fontSize: 12,
            fontWeight: 600,
            color: variant === "dark" ? "rgba(255,255,255,0.94)" : text.primary,
            cursor: dragHandleProps ? "grab" : onRename ? "text" : "default",
          }}
          title={onRename ? "Double-click to rename, drag to move" : undefined}
        >
          {title}
        </span>
      )}
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
            onPointerDown={stopBarDrag}
            onMouseDown={stopBarDrag}
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
          <span
            aria-hidden="true"
            style={{
              padding: 2,
              color:
                variant === "dark"
                  ? "rgba(255,255,255,0.45)"
                  : text.tertiary,
              pointerEvents: "none",
            }}
          >
            <Icons.gridDrag size={11} strokeWidth={2} />
          </span>
        )}
      </div>
    </div>
  );
}
