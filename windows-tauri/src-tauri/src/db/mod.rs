pub mod kanban;
pub mod notes;
pub mod workspace;

use anyhow::{Context, Result};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite_migration::{Migrations, M};
use std::path::Path;

pub type DbPool = Pool<SqliteConnectionManager>;

#[derive(Clone)]
pub struct Db {
    pool: DbPool,
}

impl Db {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).with_context(|| format!("create db dir {parent:?}"))?;
        }
        let manager = SqliteConnectionManager::file(path).with_init(|c| {
            c.execute_batch("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;")
        });
        let pool = Pool::builder()
            .max_size(8)
            .build(manager)
            .context("build sqlite pool")?;

        Self::run_migrations(&pool)?;
        Ok(Self { pool })
    }

    fn run_migrations(pool: &DbPool) -> Result<()> {
        let migrations = Migrations::new(vec![
            M::up(include_str!("../../migrations/001_init.sql")),
            M::up(include_str!("../../migrations/002_command_history.sql")),
        ]);
        let mut conn = pool.get()?;
        migrations.to_latest(&mut conn).context("apply migrations")?;
        Ok(())
    }

    pub fn pool(&self) -> &DbPool {
        &self.pool
    }
}

pub fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
