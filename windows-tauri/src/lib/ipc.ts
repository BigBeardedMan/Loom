import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export type Workspace = {
  id: string;
  name: string;
  folderPath: string;
  colorName: WorkspaceColor;
  kindRaw: WorkspaceKind;
  previewUrl: string;
  taskBadge: number;
  lastOpenedAt: number;
  createdAt: number;
};

export type WorkspaceColor =
  | "orange"
  | "green"
  | "blue"
  | "pink"
  | "yellow"
  | "purple";

export type WorkspaceKind = "code" | "ideas" | "review" | "build";

export type WorkspaceInput = {
  name: string;
  folderPath?: string;
  colorName?: WorkspaceColor;
  kindRaw?: WorkspaceKind;
  previewUrl?: string;
};

export type WorkspacePatch = Partial<{
  name: string;
  folderPath: string;
  colorName: WorkspaceColor;
  kindRaw: WorkspaceKind;
  previewUrl: string;
  taskBadge: number;
}>;

export type KanbanBoard = {
  id: string;
  workspaceId: string;
  name: string;
  createdAt: number;
  columns: KanbanColumn[];
};

export type KanbanColumn = {
  id: string;
  boardId: string;
  name: string;
  position: number;
  cards: KanbanCard[];
};

export type KanbanCard = {
  id: string;
  columnId: string;
  title: string;
  instructions: string;
  taskKnowledge: string;
  statusRaw: string;
  agentName: string;
  projectPath: string;
  createdAt: number;
  updatedAt: number;
};

export type IdeaNote = {
  id: string;
  workspaceId: string;
  title: string;
  body: string;
  createdAt: number;
  updatedAt: number;
};

export type FsNode = {
  name: string;
  path: string;
  isDir: boolean;
  size: number;
  modifiedMs: number;
  children?: FsNode[];
};

export type SessionInfo = {
  id: string;
  shell: string;
  pid: number;
  cwd: string | null;
};

export type SpawnOptions = {
  workspaceId?: string;
  shell?: string;
  cwd?: string;
  cols: number;
  rows: number;
  args?: string[];
  env?: [string, string][];
};

export type AgentDescriptor = {
  name: string;
  scope: "project" | "user" | "builtin";
  description: string;
  tools: string[];
  model: string | null;
  color: string | null;
};

export type McpServer = {
  name: string;
  command: string;
  args: string[];
  kind: string;
};

export const ipc = {
  appVersion: () => invoke<string>("app_version"),

  workspace: {
    list: () => invoke<Workspace[]>("workspace_list"),
    create: (input: WorkspaceInput) =>
      invoke<Workspace>("workspace_create", { input }),
    update: (id: string, patch: WorkspacePatch) =>
      invoke<Workspace | null>("workspace_update", { id, patch }),
    delete: (id: string) => invoke<void>("workspace_delete", { id }),
    touchLastOpened: (id: string) =>
      invoke<void>("workspace_touch_last_opened", { id }),
    saveLayout: (workspaceId: string, layoutJson: string) =>
      invoke<void>("layout_save", { workspaceId, layoutJson }),
    getLayout: (workspaceId: string) =>
      invoke<string | null>("layout_get", { workspaceId }),
  },

  kanban: {
    getBoard: (workspaceId: string) =>
      invoke<KanbanBoard>("kanban_get_board", { workspaceId }),
    createCard: (input: {
      columnId: string;
      title: string;
      instructions?: string;
      taskKnowledge?: string;
      agentName?: string;
      projectPath?: string;
    }) => invoke<KanbanCard>("kanban_create_card", { input }),
    updateCard: (
      id: string,
      patch: Partial<{
        title: string;
        instructions: string;
        taskKnowledge: string;
        statusRaw: string;
        agentName: string;
        projectPath: string;
      }>
    ) => invoke<void>("kanban_update_card", { id, patch }),
    moveCard: (cardId: string, newColumnId: string) =>
      invoke<void>("kanban_move_card", { cardId, newColumnId }),
    deleteCard: (id: string) => invoke<void>("kanban_delete_card", { id }),
  },

  notes: {
    list: (workspaceId: string) =>
      invoke<IdeaNote[]>("note_list", { workspaceId }),
    upsert: (input: {
      id?: string;
      workspaceId: string;
      title: string;
      body?: string;
    }) => invoke<IdeaNote>("note_upsert", { input }),
    delete: (id: string) => invoke<void>("note_delete", { id }),
  },

  terminal: {
    spawn: (opts: SpawnOptions) => invoke<string>("terminal_spawn", { opts }),
    write: (sessionId: string, bytes: number[]) =>
      invoke<void>("terminal_write", { sessionId, bytes }),
    resize: (sessionId: string, cols: number, rows: number) =>
      invoke<void>("terminal_resize", { sessionId, cols, rows }),
    kill: (sessionId: string) => invoke<void>("terminal_kill", { sessionId }),
    list: () => invoke<SessionInfo[]>("terminal_list"),
    setCwd: (sessionId: string, cwd: string) =>
      invoke<void>("terminal_set_cwd", { sessionId, cwd }),
    foregroundCommand: (sessionId: string) =>
      invoke<string | null>("terminal_foreground_command", { sessionId }),
  },

  fs: {
    walk: (root: string, maxDepth?: number, showHidden?: boolean) =>
      invoke<FsNode>("fs_walk_tree", { root, maxDepth, showHidden }),
    read: (path: string) => invoke<string>("fs_read_file", { path }),
    write: (path: string, contents: string) =>
      invoke<void>("fs_write_file", { path, contents }),
    pickWorkspaceSeeds: (folder: string) =>
      invoke<string[]>("fs_pick_workspace_seed_files", { folder }),
    watchStart: (root: string) => invoke<string>("fs_watch_start", { root }),
    watchStop: (watchId: string) =>
      invoke<void>("fs_watch_stop", { watchId }),
    pickFolder: () => invoke<string | null>("dialog_pick_folder"),
  },

  agents: {
    cliSend: (args: {
      vendor: "claude" | "codex" | "gemini" | "ollama";
      prompt: string;
      cwd: string;
      agentName?: string;
      sessionId?: string;
      extraArgs?: string[];
    }) => invoke<string>("agent_cli_send", { args }),
    refresh: () => invoke<AgentDescriptor[]>("agent_registry_refresh"),
    httpSend: (args: {
      apiKey: string;
      model: string;
      messages: unknown[];
      system?: string;
      tools?: unknown[];
      maxTokens?: number;
      temperature?: number;
      anthropicBeta?: string[];
    }) => invoke<string>("agent_http_send", { args }),
    mcpList: () => invoke<McpServer[]>("mcp_list"),
    mcpAdd: (name: string, command: string, args: string[]) =>
      invoke<void>("mcp_add", { name, command, args }),
    mcpRemove: (name: string) => invoke<void>("mcp_remove", { name }),
  },

  keychain: {
    get: (service: string, account: string) =>
      invoke<string | null>("keychain_get", { service, account }),
    set: (service: string, account: string, value: string) =>
      invoke<void>("keychain_set", { service, account, value }),
    delete: (service: string, account: string) =>
      invoke<void>("keychain_delete", { service, account }),
  },

  shell: {
    installIntegration: () => invoke<string>("shell_integration_install"),
  },

  usage: {
    read: (tool: "claude" | "codex" | "gemini", timeframe: "day" | "week" | "month" | "year") =>
      invoke<CliToolUsage>("usage_read", { tool, timeframe }),
  },

  liveTasks: {
    list: (stalenessSecs?: number) =>
      invoke<LiveAgentTaskGroup[]>("live_tasks_list", { stalenessSecs }),
    setStaleness: (secs: number) =>
      invoke<void>("live_tasks_set_staleness", { secs }),
  },

  update: {
    getArch: () => invoke<string>("update_get_arch"),
    check: () => invoke<UpdateInfo | null>("update_check"),
    downloadAndStage: (assetUrl: string, assetName: string) =>
      invoke<string>("update_download_and_stage", { assetUrl, assetName }),
    runInstaller: (installerPath: string, exitApp: boolean) =>
      invoke<void>("update_run_installer", { installerPath, exitApp }),
  },
};

export type UsageBucket = {
  start: string;
  end: string;
  tokens: number;
  label: string;
};

export type ProjectUsage = {
  displayName: string;
  path: string;
  sessions: number;
  lastActivity: string;
};

export type ModelUsage = {
  model: string;
  tokens: number;
};

export type ProjectTokenSlice = {
  displayName: string;
  path: string;
  tokens: number;
};

export type PromptTopic = {
  keyword: string;
  count: number;
};

export type PromptPreview = {
  text: string;
  timestamp: string;
  project: string;
};

export type CliToolUsage = {
  tool: "claude" | "codex" | "gemini";
  isInstalled: boolean;
  activeSessions: number;
  sessionsToday: number;
  sessionsTotal: number;
  inputTokens: number;
  outputTokens: number;
  cachedTokens: number;
  lastActivity: string | null;
  models: string[];
  chartBuckets: UsageBucket[];
  topProjects: ProjectUsage[];
  tokensByModel: ModelUsage[];
  tokensByProject: ProjectTokenSlice[];
  topTopics: PromptTopic[];
  recentPrompts: PromptPreview[];
  hourlyDistribution: number[];
  promptCount: number;
};

export type LiveAgentTask = {
  id: string;
  source: "claude" | "codex" | "gemini";
  sessionId: string;
  taskId: string;
  subject: string;
  description: string;
  activeForm: string;
  status: "pending" | "in_progress" | "completed" | "cancelled" | "deleted";
  updatedAt: string;
};

export type LiveAgentTaskGroup = {
  id: string;
  sessionId: string;
  source: "claude" | "codex" | "gemini";
  lastActivity: string;
  headline: string | null;
  tasks: LiveAgentTask[];
};

export type UpdateInfo = {
  version: string;
  currentVersion: string;
  assetName: string;
  downloadUrl: string;
  sizeBytes: number;
  releaseNotesUrl: string;
  notes: string | null;
  publishedAt: string | null;
};

export async function on<T = unknown>(
  event: string,
  handler: (payload: T) => void
): Promise<UnlistenFn> {
  return listen<T>(event, (e) => handler(e.payload));
}
