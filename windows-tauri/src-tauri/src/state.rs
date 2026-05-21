use crate::db::Db;
use crate::terminal::{SessionRegistry, TerminalTranscriptStore};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::oneshot;

pub struct AppState {
    pub db: Db,
    pub data_dir: PathBuf,
    pub logs_dir: PathBuf,
    pub terminals: Arc<SessionRegistry>,
    pub terminal_transcripts: Arc<TerminalTranscriptStore>,
    pub cancellers: Mutex<HashMap<String, oneshot::Sender<()>>>,
}

impl AppState {
    pub fn new(db: Db, data_dir: PathBuf, logs_dir: PathBuf) -> Self {
        let transcript_dir = data_dir.join("Terminal History");
        Self {
            db,
            data_dir,
            logs_dir,
            terminals: Arc::new(SessionRegistry::new()),
            terminal_transcripts: Arc::new(TerminalTranscriptStore::new(transcript_dir)),
            cancellers: Mutex::new(HashMap::new()),
        }
    }
}
