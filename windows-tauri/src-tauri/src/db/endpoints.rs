// SQLite-backed CRUD for the local_endpoints table.
// Mirrors the macOS Settings → Providers data model.

use super::{now_ms, Db};
use anyhow::Result;
use rusqlite::{params, Row};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalEndpoint {
    pub id: String,
    pub name: String,
    pub base_url: String,
    pub kind: String, // "ollama" | "openai-compat"
    pub default_model: String,
    pub requires_auth: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EndpointInput {
    #[serde(default)]
    pub id: Option<String>,
    pub name: String,
    pub base_url: String,
    pub kind: String,
    #[serde(default)]
    pub default_model: String,
    #[serde(default)]
    pub requires_auth: bool,
}

impl LocalEndpoint {
    fn from_row(row: &Row) -> rusqlite::Result<Self> {
        let requires_auth_int: i64 = row.get(5)?;
        Ok(Self {
            id: row.get(0)?,
            name: row.get(1)?,
            base_url: row.get(2)?,
            kind: row.get(3)?,
            default_model: row.get(4)?,
            requires_auth: requires_auth_int != 0,
            created_at: row.get(6)?,
            updated_at: row.get(7)?,
        })
    }
}

pub fn list(db: &Db) -> Result<Vec<LocalEndpoint>> {
    let conn = db.pool().get()?;
    let mut stmt = conn.prepare(
        "SELECT id, name, base_url, kind, default_model, requires_auth, created_at, updated_at \
         FROM local_endpoints ORDER BY name",
    )?;
    let rows = stmt.query_map([], LocalEndpoint::from_row)?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

pub fn upsert(db: &Db, input: EndpointInput) -> Result<LocalEndpoint> {
    let conn = db.pool().get()?;
    let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let now = now_ms();
    let requires_auth: i64 = if input.requires_auth { 1 } else { 0 };

    let existing: Option<i64> = conn
        .query_row(
            "SELECT created_at FROM local_endpoints WHERE id = ?",
            params![&id],
            |r| r.get(0),
        )
        .ok();

    if let Some(created_at) = existing {
        conn.execute(
            "UPDATE local_endpoints SET name = ?, base_url = ?, kind = ?, default_model = ?, \
             requires_auth = ?, updated_at = ? WHERE id = ?",
            params![
                &input.name,
                &input.base_url,
                &input.kind,
                &input.default_model,
                requires_auth,
                now,
                &id,
            ],
        )?;
        Ok(LocalEndpoint {
            id,
            name: input.name,
            base_url: input.base_url,
            kind: input.kind,
            default_model: input.default_model,
            requires_auth: input.requires_auth,
            created_at,
            updated_at: now,
        })
    } else {
        conn.execute(
            "INSERT INTO local_endpoints (id, name, base_url, kind, default_model, \
             requires_auth, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            params![
                &id,
                &input.name,
                &input.base_url,
                &input.kind,
                &input.default_model,
                requires_auth,
                now,
                now,
            ],
        )?;
        Ok(LocalEndpoint {
            id,
            name: input.name,
            base_url: input.base_url,
            kind: input.kind,
            default_model: input.default_model,
            requires_auth: input.requires_auth,
            created_at: now,
            updated_at: now,
        })
    }
}

pub fn delete(db: &Db, id: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute("DELETE FROM local_endpoints WHERE id = ?", params![id])?;
    Ok(())
}

pub fn get(db: &Db, id: &str) -> Result<Option<LocalEndpoint>> {
    let conn = db.pool().get()?;
    let endpoint = conn
        .query_row(
            "SELECT id, name, base_url, kind, default_model, requires_auth, created_at, updated_at \
             FROM local_endpoints WHERE id = ?",
            params![id],
            LocalEndpoint::from_row,
        )
        .ok();
    Ok(endpoint)
}
