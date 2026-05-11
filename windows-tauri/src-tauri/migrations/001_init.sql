PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS workspaces (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  folder_path TEXT NOT NULL DEFAULT '',
  color_name TEXT NOT NULL DEFAULT 'blue',
  kind_raw TEXT NOT NULL DEFAULT 'code',
  preview_url TEXT NOT NULL DEFAULT '',
  task_badge INTEGER NOT NULL DEFAULT 0,
  last_opened_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_workspaces_last_opened ON workspaces(last_opened_at DESC);

CREATE TABLE IF NOT EXISTS kanban_boards (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_kanban_boards_workspace ON kanban_boards(workspace_id);

CREATE TABLE IF NOT EXISTS kanban_columns (
  id TEXT PRIMARY KEY,
  board_id TEXT NOT NULL REFERENCES kanban_boards(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_kanban_columns_board ON kanban_columns(board_id, position);

CREATE TABLE IF NOT EXISTS kanban_cards (
  id TEXT PRIMARY KEY,
  column_id TEXT NOT NULL REFERENCES kanban_columns(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  instructions TEXT NOT NULL DEFAULT '',
  task_knowledge TEXT NOT NULL DEFAULT '',
  status_raw TEXT NOT NULL DEFAULT 'todo',
  agent_name TEXT NOT NULL DEFAULT 'Loom Agent',
  project_path TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_kanban_cards_column ON kanban_cards(column_id);

CREATE TABLE IF NOT EXISTS idea_notes (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_idea_notes_workspace ON idea_notes(workspace_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS workspace_layouts (
  workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
  layout_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS settings_kv (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS local_endpoints (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  base_url TEXT NOT NULL,
  kind TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
