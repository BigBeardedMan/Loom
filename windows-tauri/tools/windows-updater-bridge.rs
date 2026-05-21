#![cfg_attr(windows, windows_subsystem = "windows")]

use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::thread;
use std::time::Duration;

const REPO: &str = "BigBeardedMan/Loom";

struct Logger {
    file: Option<fs::File>,
}

impl Logger {
    fn new() -> Self {
        let path = env::temp_dir().join(format!("loom-update-bridge-{}.log", std::process::id()));
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .ok();
        let mut logger = Self { file };
        logger.line(format_args!(
            "=== loom update bridge pid={} ===",
            std::process::id()
        ));
        logger.line(format_args!("log={}", path.display()));
        logger
    }

    fn line(&mut self, args: std::fmt::Arguments<'_>) {
        if let Some(file) = &mut self.file {
            let _ = writeln!(file, "{args}");
            let _ = file.flush();
        }
    }
}

fn main() -> ExitCode {
    let strict = env::var("LOOM_BRIDGE_STRICT").ok().as_deref() == Some("1");
    let mut logger = Logger::new();
    let code = match run(&mut logger) {
        Ok(()) => 0,
        Err(err) => {
            logger.line(format_args!("bridge failed: {err}"));
            1
        }
    };

    if strict {
        ExitCode::from(code)
    } else {
        // Old installed helpers open GitHub when the staged updater exits
        // non-zero. The bridge logs failures but returns success so the app
        // never falls through to that browser fallback.
        ExitCode::SUCCESS
    }
}

fn run(logger: &mut Logger) -> Result<(), String> {
    let exe = env::current_exe().map_err(|e| format!("current_exe: {e}"))?;
    let name = exe
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| "bridge executable has no UTF-8 file name".to_string())?;
    let (version, arch) = parse_bridge_name(name)?;
    logger.line(format_args!(
        "bridge asset={name} version={version} arch={arch}"
    ));

    close_loom_processes(logger);
    thread::sleep(Duration::from_secs(2));

    let installer = resolve_installer(&version, &arch, logger)?;
    run_real_installer(&installer, logger)
}

fn parse_bridge_name(name: &str) -> Result<(String, String), String> {
    let stem = name
        .strip_suffix("-setup.exe")
        .or_else(|| name.strip_suffix("-SETUP.EXE"))
        .ok_or_else(|| format!("unexpected bridge name: {name}"))?;
    let (prefix, arch) = stem
        .rsplit_once('_')
        .ok_or_else(|| format!("bridge name is missing arch: {name}"))?;
    if arch != "x64" && arch != "arm64" {
        return Err(format!("unexpected bridge arch: {arch}"));
    }
    let (_, version) = prefix
        .rsplit_once('_')
        .ok_or_else(|| format!("bridge name is missing version: {name}"))?;
    if !is_semver(version) {
        return Err(format!("unexpected bridge version: {version}"));
    }
    Ok((version.to_string(), arch.to_string()))
}

fn is_semver(version: &str) -> bool {
    let mut parts = version.split('.');
    let Some(major) = parts.next() else {
        return false;
    };
    let Some(minor) = parts.next() else {
        return false;
    };
    let Some(patch) = parts.next() else {
        return false;
    };
    parts.next().is_none()
        && !major.is_empty()
        && !minor.is_empty()
        && !patch.is_empty()
        && major.chars().all(|c| c.is_ascii_digit())
        && minor.chars().all(|c| c.is_ascii_digit())
        && patch.chars().all(|c| c.is_ascii_digit())
}

fn resolve_installer(version: &str, arch: &str, logger: &mut Logger) -> Result<PathBuf, String> {
    if let Ok(path) = env::var("LOOM_BRIDGE_LOCAL_INSTALLER") {
        let path = PathBuf::from(path);
        if path.is_file() {
            logger.line(format_args!("using local installer={}", path.display()));
            return Ok(path);
        }
        return Err(format!(
            "LOOM_BRIDGE_LOCAL_INSTALLER is not a file: {}",
            path.display()
        ));
    }

    let name = format!("Loom.Testing.Edition_{version}_{arch}-setup.exe");
    let url = format!("https://github.com/{REPO}/releases/download/testing-{version}/{name}");
    let target = env::temp_dir().join(format!("loom-real-installer-{}-{name}", std::process::id()));
    logger.line(format_args!("downloading real installer from {url}"));
    download(&url, &target, logger)?;
    let size = fs::metadata(&target)
        .map_err(|e| format!("metadata {}: {e}", target.display()))?
        .len();
    if size == 0 {
        return Err(format!(
            "downloaded installer is empty: {}",
            target.display()
        ));
    }
    logger.line(format_args!(
        "downloaded {} bytes to {}",
        size,
        target.display()
    ));
    Ok(target)
}

fn download(url: &str, target: &Path, logger: &mut Logger) -> Result<(), String> {
    let _ = fs::remove_file(target);

    let curl_status = Command::new("curl.exe")
        .args(["-fL", "--retry", "3", "--connect-timeout", "20", "-o"])
        .arg(target)
        .arg(url)
        .status();
    match curl_status {
        Ok(status) if status.success() => return Ok(()),
        Ok(status) => logger.line(format_args!("curl.exe exited with {status}")),
        Err(err) => logger.line(format_args!("curl.exe failed to start: {err}")),
    }

    let script = format!(
        "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '{}' -OutFile '{}'",
        ps_quote(url),
        ps_quote(&target.to_string_lossy())
    );
    let status = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"])
        .arg(script)
        .status()
        .map_err(|e| format!("powershell download failed to start: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("powershell download exited with {status}"))
    }
}

fn close_loom_processes(logger: &mut Logger) {
    for name in ["loom.exe", "Loom Testing Edition.exe"] {
        let status = Command::new("taskkill")
            .args(["/IM", name, "/T", "/F"])
            .status();
        logger.line(format_args!("taskkill {name}: {:?}", status.ok()));
    }
}

fn run_real_installer(installer: &Path, logger: &mut Logger) -> Result<(), String> {
    let updater_args = ["/S", "/R", "/UPDATE", "/ARGS"];
    let legacy_args = ["/S"];

    let updater = run_installer_mode(installer, &updater_args, "updater", logger)?;
    if updater == 0 {
        return Ok(());
    }

    let legacy = run_installer_mode(installer, &legacy_args, "legacy", logger)?;
    if legacy == 0 {
        return Ok(());
    }

    if env::var("LOOM_BRIDGE_DISABLE_ELEVATION").ok().as_deref() != Some("1") {
        let elevated = run_elevated(installer, &updater_args, logger)?;
        if elevated == 0 {
            return Ok(());
        }
        return Err(format!(
            "installer failed: updater={updater}, legacy={legacy}, elevated={elevated}"
        ));
    }

    Err(format!(
        "installer failed: updater={updater}, legacy={legacy}, elevation disabled"
    ))
}

fn run_installer_mode(
    installer: &Path,
    args: &[&str],
    label: &str,
    logger: &mut Logger,
) -> Result<i32, String> {
    logger.line(format_args!(
        "running {label}: {} {}",
        installer.display(),
        args.join(" ")
    ));
    let status = Command::new(installer)
        .args(args)
        .status()
        .map_err(|e| format!("start {label} installer: {e}"))?;
    let code = status.code().unwrap_or(1);
    logger.line(format_args!("{label} exit code: {code}"));
    Ok(code)
}

fn run_elevated(installer: &Path, args: &[&str], logger: &mut Logger) -> Result<i32, String> {
    let arg_list = args
        .iter()
        .map(|arg| format!("'{}'", ps_quote(arg)))
        .collect::<Vec<_>>()
        .join(",");
    let script = format!(
        "$p = Start-Process -FilePath '{}' -ArgumentList @({}) -Verb RunAs -Wait -PassThru; exit $p.ExitCode",
        ps_quote(&installer.to_string_lossy()),
        arg_list
    );
    logger.line(format_args!("running elevated installer via powershell"));
    let status = Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"])
        .arg(script)
        .status()
        .map_err(|e| format!("start elevated installer: {e}"))?;
    let code = status.code().unwrap_or(1);
    logger.line(format_args!("elevated exit code: {code}"));
    Ok(code)
}

fn ps_quote(value: &str) -> String {
    value.replace('\'', "''")
}
