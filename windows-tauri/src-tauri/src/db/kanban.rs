use super::{now_ms, Db};
use anyhow::Result;
use rusqlite::{params, Row};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KanbanBoard {
    pub id: String,
    pub workspace_id: String,
    pub name: String,
    pub created_at: i64,
    pub columns: Vec<KanbanColumn>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KanbanColumn {
    pub id: String,
    pub board_id: String,
    pub name: String,
    pub position: i64,
    pub cards: Vec<KanbanCard>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KanbanCard {
    pub id: String,
    pub column_id: String,
    pub title: String,
    pub instructions: String,
    pub task_knowledge: String,
    pub status_raw: String,
    pub agent_name: String,
    pub project_path: String,
    pub created_at: i64,
    pub updated_at: i64,
}

impl KanbanCard {
    fn from_row(row: &Row) -> rusqlite::Result<Self> {
        Ok(Self {
            id: row.get(0)?,
            column_id: row.get(1)?,
            title: row.get(2)?,
            instructions: row.get(3)?,
            task_knowledge: row.get(4)?,
            status_raw: row.get(5)?,
            agent_name: row.get(6)?,
            project_path: row.get(7)?,
            created_at: row.get(8)?,
            updated_at: row.get(9)?,
        })
    }
}

const DEFAULT_COLUMNS: &[(&str, &str)] = &[
    ("Todo", "todo"),
    ("In Progress", "inProgress"),
    ("In Review", "inReview"),
    ("Complete", "complete"),
    ("Cancelled", "cancelled"),
];

pub fn get_or_create_board(db: &Db, workspace_id: &str) -> Result<KanbanBoard> {
    let conn = db.pool().get()?;
    let board_id: Option<String> = conn
        .query_row(
            "SELECT id FROM kanban_boards WHERE workspace_id = ?1 ORDER BY created_at ASC LIMIT 1",
            params![workspace_id],
            |row| row.get(0),
        )
        .ok();
    let board_id = if let Some(id) = board_id {
        id
    } else {
        let id = Uuid::new_v4().to_string();
        conn.execute(
            "INSERT INTO kanban_boards (id, workspace_id, name, created_at) VALUES (?1, ?2, ?3, ?4)",
            params![id, workspace_id, "Tasks", now_ms()],
        )?;
        for (pos, (name, _status)) in DEFAULT_COLUMNS.iter().enumerate() {
            conn.execute(
                "INSERT INTO kanban_columns (id, board_id, name, position) VALUES (?1, ?2, ?3, ?4)",
                params![Uuid::new_v4().to_string(), id, name, pos as i64],
            )?;
        }
        id
    };
    drop(conn);
    load_board(db, &board_id)
}

fn load_board(db: &Db, board_id: &str) -> Result<KanbanBoard> {
    let conn = db.pool().get()?;
    let (workspace_id, name, created_at): (String, String, i64) = conn.query_row(
        "SELECT workspace_id, name, created_at FROM kanban_boards WHERE id = ?1",
        params![board_id],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;

    let mut col_stmt = conn.prepare(
        "SELECT id, board_id, name, position FROM kanban_columns WHERE board_id = ?1 ORDER BY position ASC",
    )?;
    let columns_meta: Vec<(String, String, String, i64)> = col_stmt
        .query_map(params![board_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(col_stmt);

    let mut card_stmt = conn.prepare(
        "SELECT id, column_id, title, instructions, task_knowledge, status_raw, agent_name, project_path, created_at, updated_at \
         FROM kanban_cards WHERE column_id = ?1 ORDER BY created_at ASC",
    )?;

    let mut columns = Vec::with_capacity(columns_meta.len());
    for (id, board_id, name, position) in columns_meta {
        let cards = card_stmt
            .query_map(params![id], KanbanCard::from_row)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        columns.push(KanbanColumn {
            id,
            board_id,
            name,
            position,
            cards,
        });
    }

    Ok(KanbanBoard {
        id: board_id.to_string(),
        workspace_id,
        name,
        created_at,
        columns,
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CardInput {
    pub column_id: String,
    pub title: String,
    #[serde(default)]
    pub instructions: String,
    #[serde(default)]
    pub task_knowledge: String,
    #[serde(default = "default_agent")]
    pub agent_name: String,
    #[serde(default)]
    pub project_path: String,
}

fn default_agent() -> String {
    "Loom Agent".into()
}

pub fn create_card(db: &Db, input: CardInput) -> Result<KanbanCard> {
    let now = now_ms();
    let card = KanbanCard {
        id: Uuid::new_v4().to_string(),
        column_id: input.column_id,
        title: input.title,
        instructions: input.instructions,
        task_knowledge: input.task_knowledge,
        status_raw: "todo".into(),
        agent_name: input.agent_name,
        project_path: input.project_path,
        created_at: now,
        updated_at: now,
    };
    let conn = db.pool().get()?;
    conn.execute(
        "INSERT INTO kanban_cards (id, column_id, title, instructions, task_knowledge, status_raw, agent_name, project_path, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
        params![
            card.id, card.column_id, card.title, card.instructions, card.task_knowledge,
            card.status_raw, card.agent_name, card.project_path, card.created_at, card.updated_at
        ],
    )?;
    Ok(card)
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CardPatch {
    pub title: Option<String>,
    pub instructions: Option<String>,
    pub task_knowledge: Option<String>,
    pub status_raw: Option<String>,
    pub agent_name: Option<String>,
    pub project_path: Option<String>,
}

pub fn update_card(db: &Db, id: &str, patch: CardPatch) -> Result<()> {
    let conn = db.pool().get()?;
    if let Some(v) = patch.title {
        conn.execute(
            "UPDATE kanban_cards SET title = ?1, updated_at = ?2 WHERE id = ?3",
            params![v, now_ms(), id],
        )?;
    }
    if let Some(v) = patch.instructions {
        conn.execute(
            "UPDATE kanban_cards SET instructions = ?1, updated_at = ?2 WHERE id = ?3",
            params![v, now_ms(), id],
        )?;
    }
    if let Some(v) = patch.task_knowledge {
        conn.execute(
            "UPDATE kanban_cards SET task_knowledge = ?1, updated_at = ?2 WHERE id = ?3",
            params![v, now_ms(), id],
        )?;
    }
    if let Some(v) = patch.status_raw {
        conn.execute(
            "UPDATE kanban_cards SET status_raw = ?1, updated_at = ?2 WHERE id = ?3",
            params![v, now_ms(), id],
        )?;
    }
    if let Some(v) = patch.agent_name {
        conn.execute(
            "UPDATE kanban_cards SET agent_name = ?1, updated_at = ?2 WHERE id = ?3",
            params![v, now_ms(), id],
        )?;
    }
    if let Some(v) = patch.project_path {
        conn.execute(
            "UPDATE kanban_cards SET project_path = ?1, updated_at = ?2 WHERE id = ?3",
            params![v, now_ms(), id],
        )?;
    }
    Ok(())
}

pub fn move_card(db: &Db, card_id: &str, new_column_id: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute(
        "UPDATE kanban_cards SET column_id = ?1, updated_at = ?2 WHERE id = ?3",
        params![new_column_id, now_ms(), card_id],
    )?;
    Ok(())
}

pub fn delete_card(db: &Db, id: &str) -> Result<()> {
    let conn = db.pool().get()?;
    conn.execute("DELETE FROM kanban_cards WHERE id = ?1", params![id])?;
    Ok(())
}
