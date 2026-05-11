use super::{now_ms, Db};
use anyhow::Result;
use rusqlite::{params, Row};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Workspace {
    pub id: String,
    pub name: String,
    pub folder_path: String,
    pub color_name: String,
    pub kind_raw: String,
    pub preview_url: String,
    pub task_badge: i64,
    pub last_opened_at: i64,
    pub created_at: i64,
}

impl Workspace {
    fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get(0)?,
            name: row.get(1)?,
            folder_path: row.get(2)?,
            color_name: row.get(3)?,
            kind_raw: row.get(4)?,
            preview_url: row.get(5)?,
            task_badge: row.get(6)?,
            last_opened_at: row.get(7)?,
            created_at: row.get(8)?,
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceInput {
    pub name: String,
    #[serde(default)]
    pub folder_path: String,
    #[serde(default = "default_color")]
    pub color_name: String,
    #[serde(default = "default_kind")]
    pub kind_raw: String,
    #[serde(default)]
    pub preview_url: String,
}

fn default_color() -> String {
    "blue".into()
}

fn default_kind() -> String {
    "code".into()
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspacePatch {
    pub name: Option<String>,
    pub folder_path: Option<String>,
    pub color_name: Option<String>,
    pub kind_raw: Option<String>,
    pub preview_url: Option<String>,
    pub task_badge: Option<i64>,
}

pub fn list(db: &Db) -> Result<Vec<Workspace>> {
    let conn = db.pool().get()?;
    let mut stmt = conn.prepare(
        "SELECT id, name, folder_path, color_name, kind_raw, preview_url, task_badge, last_opened_at, created_at \
         FROM workspaces ORDER BY last_opened_at DESC",
    )?;
    let rows = stmt
        .query_map([], Workspace::from_row)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

pub fn get(db: &Db, id: &str) -> Result<Option<Workspace>> {
    let conn = db.pool().get()?;
    let mut stmt = conn.prepare(
        "SELECT id, name, folder_path, color_name, kind_raw, preview_url, task_badge, last_opened_at, created_at \
         FROM workspaces WHERE id = ?1",
    )?;
    let mut rows = stmt.query(params![id])?;
    if let Some(row) = rows.next()? {
        return Ok(Some(Workspace::from_row(row)?));
    }
    Ok(None)
}

pub fn create(db: &Db, input: WorkspaceInput) -> Result<Workspace> {
    let now = now_ms();
    let id = Uuid::new_v4().to_string();
    let ws = Workspace {
        id: id.clone(),
        name: input.name,
        folder_path: input.folder_path,
        color_name: input.color_name,
        kind_raw: input.kind_raw,
        preview_url: input.preview_url,
        task_badge: 0,
        last_opened_at: now,
        created_at: now,
    };
    let conn = db.pool().get()?;
    conn.execute(
        "INSERT INTO workspaces (id, name, folder_path, color_name, kind_raw, preview_url, task_badge, last_opened_at, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![
            ws.id, ws.name, ws.folder_path, ws.color_name, ws.kind_raw,
            ws.preview_url, ws.task_badge, ws.last_opened_at, ws.created_at
        ],
    )?;
    Ok(ws)
}

pub fn update(db: &Db, id: &str, patch: WorkspacePatch) -> Result<Option<Workspace>> {
    let conn = db.pool().get()?;
    let existing = get(db, id)?;
    let Some(mut ws) = existing else {
        return Ok(None);
    };
    if let Some(v) = patch.name {
        ws.name = v;
    }
    if let Some(v) = patch.folder_path {
        ws.folder_path = v;
    }
    if let Some(v) = patch.color_name {
        ws.color_name = v;
    }
    if let Some(v) = patch.kind_raw {
        ws.kind_raw = v;
    }
    if let Some(v) = patch.preview_url {
        ws.preview_url = v;
    }
    if let Some(v) = patch.task_badge {
        ws.task_badge = v;
    }
    conn.execute(
        "UPDATE workspaces SET name = ?1, folder_path = ?2, color_name = ?3, kind_raw = ?4, preview_url = ?5, task_badge = ?6 WHERE id = ?7",
        params![ws.name, ws.folder_path, ws.color_name, ws.kind_raw, ws.preview_url, ws.task_badge, ws.id],
    )?;
    Ok(Some(ws))
}

pub fn delete(db: &Db, id: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute("DELETE FROM workspaces WHERE id = ?1", params![id])?;
    Ok(())
}

pub fn touch_last_opened(db: &Db, id: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute(
        "UPDATE workspaces SET last_opened_at = ?1 WHERE id = ?2",
        params![now_ms(), id],
    )?;
    Ok(())
}

pub fn save_layout(db: &Db, workspace_id: &str, layout_json: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute(
        "INSERT INTO workspace_layouts (workspace_id, layout_json, updated_at) VALUES (?1, ?2, ?3) \
         ON CONFLICT(workspace_id) DO UPDATE SET layout_json = excluded.layout_json, updated_at = excluded.updated_at",
        params![workspace_id, layout_json, now_ms()],
    )?;
    Ok(())
}

pub fn get_layout(db: &Db, workspace_id: &str) -> Result<Option<String>> {
    let conn = db.pool().get()?;
    let mut stmt = conn.prepare("SELECT layout_json FROM workspace_layouts WHERE workspace_id = ?1")?;
    let mut rows = stmt.query(params![workspace_id])?;
    if let Some(row) = rows.next()? {
        let json: String = row.get(0)?;
        return Ok(Some(json));
    }
    Ok(None)
}
