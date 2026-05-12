// Cross-restart crash reporting.
//
// `panic = "abort"` means a Rust panic kills the process via __fastfail
// (Windows exception 0xc0000409), giving the user a cryptic native dialog.
// We catch panics first via `std::panic::set_hook`, dump the info to
// `<app_data>/logs/panic.log`, then let abort proceed. On next launch the
// app checks for that file and surfaces the contents in an in-app modal
// with a "Report on GitHub" deep-link.

use chrono::Local;
use parking_lot::Mutex;
use serde::Serialize;
use std::fmt::Write;
use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

static PANIC_LOG_PATH: OnceLock<PathBuf> = OnceLock::new();
static PENDING_REPORT: Mutex<Option<CrashReport>> = Mutex::new(None);

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CrashReport {
    pub version: String,
    pub arch: String,
    pub timestamp: String,
    pub body: String,
}

pub fn install_hook() {
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let mut msg = String::new();
        let _ = writeln!(msg, "Loom panic at {}", Local::now().to_rfc3339());
        let _ = writeln!(msg, "Version: {}", env!("LOOM_BUILD_CODE"));
        let _ = writeln!(msg, "Arch: {}", std::env::consts::ARCH);
        let _ = writeln!(
            msg,
            "Thread: {}",
            std::thread::current().name().unwrap_or("<unnamed>")
        );
        if let Some(loc) = info.location() {
            let _ = writeln!(msg, "Location: {}:{}", loc.file(), loc.line());
        }
        let payload = info.payload();
        if let Some(s) = payload.downcast_ref::<&str>() {
            let _ = writeln!(msg, "Message: {}", s);
        } else if let Some(s) = payload.downcast_ref::<String>() {
            let _ = writeln!(msg, "Message: {}", s);
        } else {
            let _ = writeln!(msg, "Message: <non-string payload>");
        }
        let bt = std::backtrace::Backtrace::force_capture();
        let _ = writeln!(msg, "\nBacktrace:\n{}", bt);

        if let Some(path) = PANIC_LOG_PATH.get() {
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = fs::write(path, &msg);
        }
        eprintln!("{}", msg);

        prev(info);
    }));
}

pub fn set_log_dir(dir: PathBuf) {
    let path = dir.join("panic.log");
    let _ = PANIC_LOG_PATH.set(path);
}

/// Called during `setup` after the log dir is known. If a panic.log exists
/// from a prior run, read it, archive the file so we don't replay forever,
/// and stash the body so the frontend can fetch it via `crash_get_last`.
pub fn consume_prior_crash() {
    let Some(path) = PANIC_LOG_PATH.get() else {
        return;
    };
    if !path.exists() {
        return;
    }
    let Ok(body) = fs::read_to_string(path) else {
        return;
    };
    // Archive so we don't show the same crash twice.
    let archived = path.with_file_name(format!(
        "panic-{}.log",
        Local::now().format("%Y%m%dT%H%M%S")
    ));
    let _ = fs::rename(path, &archived);

    let report = CrashReport {
        version: env!("LOOM_BUILD_CODE").to_string(),
        arch: std::env::consts::ARCH.to_string(),
        timestamp: Local::now().to_rfc3339(),
        body,
    };
    *PENDING_REPORT.lock() = Some(report);
}

#[tauri::command]
pub fn crash_get_last() -> Option<CrashReport> {
    PENDING_REPORT.lock().take()
}

/// Lets the frontend forward an in-page JS panic to the same staging path
/// so the user sees a consistent "next launch" experience even when the
/// panic was on the React side.
#[tauri::command]
pub fn crash_record_frontend(message: String) -> Result<(), String> {
    let report = CrashReport {
        version: env!("LOOM_BUILD_CODE").to_string(),
        arch: std::env::consts::ARCH.to_string(),
        timestamp: Local::now().to_rfc3339(),
        body: format!("[frontend] {message}"),
    };
    let Some(path) = PANIC_LOG_PATH.get() else {
        return Err("log path not initialized".into());
    };
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    fs::write(path, &report.body).map_err(|e| e.to_string())?;
    Ok(())
}
