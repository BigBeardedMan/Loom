import { useState } from "react";
import { Icons } from "../../lib/icons";
import type { FsNode } from "../../lib/ipc";
import { surface, text } from "../../lib/theme";

type Props = {
  node: FsNode;
  depth: number;
  onOpen: (path: string) => void;
  selected: string | null;
};

// Mirrors Loom/Editor/FileTreeView.swift recursive folder renderer.
export function FileTree({ node, depth, onOpen, selected }: Props) {
  const [open, setOpen] = useState(depth < 1);

  if (!node.isDir) {
    const isSelected = selected === node.path;
    return (
      <div
        className="flex cursor-pointer items-center gap-1.5"
        style={{
          paddingLeft: 10 + depth * 12,
          paddingRight: 8,
          paddingTop: 2,
          paddingBottom: 2,
          fontSize: 11,
          background: isSelected ? surface.softPanel : "transparent",
          color: isSelected ? text.primary : text.muted,
          transition: "background 80ms ease-out",
        }}
        onMouseEnter={(e) => {
          if (!isSelected) e.currentTarget.style.background = surface.softPanel as string;
        }}
        onMouseLeave={(e) => {
          if (!isSelected) e.currentTarget.style.background = "transparent";
        }}
        onClick={() => onOpen(node.path)}
      >
        <Icons.file size={11} strokeWidth={1.6} color={text.tertiary as string} />
        <span className="truncate">{node.name}</span>
      </div>
    );
  }

  return (
    <div>
      <div
        className="flex cursor-pointer items-center gap-1.5"
        style={{
          paddingLeft: 10 + depth * 12,
          paddingRight: 8,
          paddingTop: 2,
          paddingBottom: 2,
          fontSize: 11,
          color: text.muted,
        }}
        onClick={() => setOpen((v) => !v)}
      >
        {open ? (
          <Icons.chevronDown size={11} strokeWidth={2} color={text.tertiary as string} />
        ) : (
          <Icons.chevronRight size={11} strokeWidth={2} color={text.tertiary as string} />
        )}
        <Icons.folderOpen size={11} strokeWidth={1.6} color="var(--color-ws-blue)" />
        <span className="truncate">{node.name}</span>
      </div>
      {open &&
        node.children?.map((child) => (
          <FileTree
            key={child.path}
            node={child}
            depth={depth + 1}
            onOpen={onOpen}
            selected={selected}
          />
        ))}
    </div>
  );
}
