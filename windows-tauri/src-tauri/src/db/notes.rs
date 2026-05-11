use super::{now_ms, Db};
use anyhow::Result;
use rusqlite::{params, Row};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IdeaNote {
    pub id: String,
    pub workspace_id: String,
    pub title: String,
    pub body: String,
    pub created_at: i64,
    pub updated_at: i64,
}

impl IdeaNote {
    fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get(0)?,
            workspace_id: row.get(1)?,
            title: row.get(2)?,
            body: row.get(3)?,
            created_at: row.get(4)?,
            updated_at: row.get(5)?,
        })
    }
}

pub fn list(db: &Db, workspace_id: &str) -> Result<Vec<IdeaNote>> {
    let conn = db.pool().get()?;
    let mut stmt = conn.prepare(
        "SELECT id, workspace_id, title, body, created_at, updated_at FROM idea_notes \
         WHERE workspace_id = ?1 ORDER BY updated_at DESC",
    )?;
    let rows = stmt
        .query_map(params![workspace_id], IdeaNote::from_row)?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteInput {
    pub id: Option<String>,
    pub workspace_id: String,
    pub title: String,
    #[serde(default)]
    pub body: String,
}

pub fn upsert(db: &Db, input: NoteInput) -> Result<IdeaNote> {
    let conn = db.pool().get()?;
    let now = now_ms();
    if let Some(id) = input.id {
        conn.execute(
            "UPDATE idea_notes SET title = ?1, body = ?2, updated_at = ?3 WHERE id = ?4",
            params![input.title, input.body, now, id],
        )?;
        let mut stmt = conn.prepare(
            "SELECT id, workspace_id, title, body, created_at, updated_at FROM idea_notes WHERE id = ?1",
        )?;
        let mut rows = stmt.query(params![id])?;
        if let Some(row) = rows.next()? {
            return Ok(IdeaNote::from_row(row)?);
        }
    }
    let id = Uuid::new_v4().to_string();
    let note = IdeaNote {
        id: id.clone(),
        workspace_id: input.workspace_id,
        title: input.title,
        body: input.body,
        created_at: now,
        updated_at: now,
    };
    conn.execute(
        "INSERT INTO idea_notes (id, workspace_id, title, body, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![
            note.id, note.workspace_id, note.title, note.body, note.created_at, note.updated_at
        ],
    )?;
    Ok(note)
}

pub fn delete(db: &Db, id: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute("DELETE FROM idea_notes WHERE id = ?1", params![id])?;
    Ok(())
}
