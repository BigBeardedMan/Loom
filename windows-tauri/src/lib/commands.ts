import { Icons, type IconName } from "./icons";
import { workspaceColorVar } from "./theme";
import type { Panel } from "./store";

export const PANEL_META: Record<
  Panel,
  { label: string; icon: IconName; color: string }
> = {
  terminal: { label: "Terminal", icon: "terminal", color: workspaceColorVar.green },
  editor: { label: "Editor", icon: "textCursor", color: workspaceColorVar.blue },
  tasks: { label: "Runs", icon: "checkCircle", color: workspaceColorVar.orange },
  chat: { label: "Chat", icon: "chat", color: workspaceColorVar.blue },
  agent: { label: "Agent", icon: "sparkles", color: workspaceColorVar.purple },
  notes: { label: "Notes", icon: "lightbulb", color: workspaceColorVar.yellow },
  preview: { label: "Preview", icon: "eye", color: workspaceColorVar.pink },
  commands: { label: "Commands", icon: "listBulletRect", color: workspaceColorVar.blue },
};

export const PANEL_KINDS = Object.keys(PANEL_META) as Panel[];
const PANEL_KIND_SET = new Set<string>(PANEL_KINDS);

export function isPanelKind(kind: unknown): kind is Panel {
  return typeof kind === "string" && PANEL_KIND_SET.has(kind);
}

export function panelsForKind(kind?: string): Panel[] {
  switch (kind) {
    case "code":
      return ["terminal", "editor", "tasks", "agent", "commands"];
    case "ideas":
      return ["notes", "agent"];
    case "review":
    case "build":
      return ["preview", "agent"];
    case "runs":
      return ["tasks", "chat", "agent", "terminal", "commands"];
    default:
      return ["terminal", "editor", "tasks", "chat", "agent", "notes", "preview", "commands"];
  }
}

export const ADD_BLOCK_COMMANDS = panelsForKind().map((kind) => ({
  kind,
  label: PANEL_META[kind].label,
  icon: Icons[PANEL_META[kind].icon],
}));
