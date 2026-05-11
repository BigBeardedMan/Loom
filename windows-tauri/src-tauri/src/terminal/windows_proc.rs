#![cfg(target_os = "windows")]

//! Walks a process tree to detect when a CLI agent (claude.exe, codex.exe,
//! gemini.exe, ollama.exe) is the foreground descendant of a given shell PID.
//! This is the Windows replacement for the macOS `tcgetpgrp`-based detection
//! in Loom's terminal foreground-command logic.

use std::collections::HashMap;
use std::ffi::OsString;
use std::os::windows::ffi::OsStringExt;
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
};

const AGENT_BINARIES: &[&str] = &[
    "claude.exe",
    "codex.exe",
    "gemini.exe",
    "ollama.exe",
    "node.exe",
    "python.exe",
    "python3.exe",
];

pub fn active_descendant_command(root_pid: u32) -> Option<String> {
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) }.ok()?;
    if snapshot.is_invalid() {
        return None;
    }
    let result = walk(snapshot, root_pid);
    unsafe { CloseHandle(snapshot) }.ok();
    result
}

fn walk(snapshot: HANDLE, root_pid: u32) -> Option<String> {
    let mut entry = PROCESSENTRY32W::default();
    entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;

    let mut by_parent: HashMap<u32, Vec<(u32, String)>> = HashMap::new();

    unsafe {
        if Process32FirstW(snapshot, &mut entry).is_err() {
            return None;
        }
        loop {
            let exe = wide_to_string(&entry.szExeFile);
            by_parent
                .entry(entry.th32ParentProcessID)
                .or_default()
                .push((entry.th32ProcessID, exe));
            entry.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
            if Process32NextW(snapshot, &mut entry).is_err() {
                break;
            }
        }
    }

    let mut stack = vec![root_pid];
    while let Some(pid) = stack.pop() {
        let Some(children) = by_parent.get(&pid) else {
            continue;
        };
        for (cpid, exe) in children {
            let lower = exe.to_ascii_lowercase();
            if AGENT_BINARIES.iter().any(|b| *b == lower.as_str()) {
                return Some(exe.clone());
            }
            stack.push(*cpid);
        }
    }
    None
}

fn wide_to_string(buf: &[u16]) -> String {
    let len = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    OsString::from_wide(&buf[..len])
        .to_string_lossy()
        .into_owned()
}
