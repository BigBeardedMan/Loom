CREATE TABLE IF NOT EXISTS command_history (
  id TEXT PRIMARY KEY,
  workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
  workspace_path TEXT NOT NULL DEFAULT '',
  command TEXT NOT NULL,
  cwd TEXT NOT NULL DEFAULT '',
  shell TEXT NOT NULL DEFAULT '',
  exit_code INTEGER,
  duration_ms INTEGER,
  output_path TEXT NOT NULL DEFAULT '',
  started_at INTEGER NOT NULL,
  ended_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_command_history_workspace ON command_history(workspace_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_command_history_started ON command_history(started_at DESC);
