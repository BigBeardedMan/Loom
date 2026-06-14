import { Icons, type IconName } from "./icons";
import { workspaceColorVar } from "./theme";
import type { AgentGraphRunSummary, Workspace, WorkspaceKind } from "./ipc";
import type { Panel, RightRailTab } from "./store";
import type { Block } from "../modules/workspace/LayoutPersistence";

export const ROOM_KINDS: WorkspaceKind[] = ["code", "ideas", "review", "runs"];

export const ROOM_META: Record<
  WorkspaceKind,
  { label: string; icon: IconName; color: string }
> = {
  code: { label: "Prompt", icon: "terminal", color: workspaceColorVar.blue },
  ideas: { label: "Ideas", icon: "lightbulb", color: workspaceColorVar.pink },
  review: { label: "Review", icon: "diff", color: workspaceColorVar.orange },
  build: { label: "Review", icon: "diff", color: workspaceColorVar.orange },
  runs: { label: "Runs", icon: "workflow", color: workspaceColorVar.green },
};

export function workspaceMatchesKind(workspace: Pick<Workspace, "kindRaw">, kind: WorkspaceKind): boolean {
  if (kind === "review") return workspace.kindRaw === "review" || workspace.kindRaw === "build";
  return workspace.kindRaw === kind;
}

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

export const RIGHT_RAIL_COMMANDS: Array<{
  tab: RightRailTab;
  label: string;
  icon: IconName;
}> = [
  { tab: "files", label: "Files", icon: "folderFill" },
  { tab: "preview", label: "Preview", icon: "eye" },
  { tab: "timeline", label: "Timeline", icon: "workflow" },
  { tab: "tools", label: "Tools", icon: "tools" },
  { tab: "diff", label: "Diff", icon: "diff" },
  { tab: "memory", label: "Memory", icon: "brain" },
  { tab: "details", label: "Details", icon: "panelRight" },
];

type RailContext = {
  workspace?: Workspace | null;
  blocks?: Pick<Block, "kind">[];
  runs?: Pick<AgentGraphRunSummary, "gitBranch" | "gitDirty" | "toolEventCount">[];
  hasMemoryFiles?: boolean;
};

export function railTabsForContext({
  workspace = null,
  blocks = [],
  runs = [],
  hasMemoryFiles = false,
}: RailContext = {}) {
  const tabs: typeof RIGHT_RAIL_COMMANDS = [];
  const byId = new Map(RIGHT_RAIL_COMMANDS.map((tab) => [tab.tab, tab]));
  const add = (id: RightRailTab) => {
    const tab = byId.get(id);
    if (tab && !tabs.some((item) => item.tab === id)) tabs.push(tab);
  };

  if (workspace?.folderPath) add("files");
  if (blocks.some((block) => block.kind === "preview")) add("preview");
  add("timeline");
  add("tools");
  if (
    workspace?.kindRaw === "review" ||
    workspace?.kindRaw === "runs" ||
    runs.some((run) => run.gitBranch || run.gitDirty !== undefined || (run.toolEventCount ?? 0) > 0)
  ) {
    add("diff");
  }
  if (
    workspace?.folderPath ||
    hasMemoryFiles ||
    workspace?.kindRaw === "runs" ||
    workspace?.kindRaw === "review" ||
    runs.length > 0
  ) {
    add("memory");
  }
  add("details");
  return tabs;
}

export function effectiveRailTab(tab: RightRailTab, context: RailContext = {}): RightRailTab {
  const available = railTabsForContext(context).map((item) => item.tab);
  return available.includes(tab) ? tab : available[0] ?? "details";
}

export function rightRailTabLabel(tab: RightRailTab): string {
  return RIGHT_RAIL_COMMANDS.find((item) => item.tab === tab)?.label ?? "Details";
}
