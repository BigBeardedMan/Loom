use crate::db::endpoints::{self, LocalEndpoint};
use crate::state::AppState;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;
use tauri::State;
use tokio::process::Command;
use tokio::time::timeout;

const DEFAULT_LMSTUDIO_BASE_URL: &str = "http://localhost:1234/v1";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioModel {
    pub id: String,
    pub loaded: bool,
    pub context_length: Option<i64>,
    pub quantization: Option<String>,
    pub architecture: Option<String>,
    pub trained_for_tool_use: Option<bool>,
    pub schema_supported: Option<bool>,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioRuntimeStatus {
    pub cli_installed: bool,
    pub server_reachable: bool,
    pub state: String,
    pub models: Vec<LmStudioModel>,
    pub recommended_model_id: Option<String>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioPrepareArgs {
    pub endpoint_id: String,
    #[serde(default)]
    pub preferred_model: Option<String>,
    #[serde(default = "default_context_target")]
    pub context_target: i64,
    #[serde(default = "default_true")]
    pub auto_scale: bool,
}

#[tauri::command]
pub async fn lmstudio_models(
    state: State<'_, AppState>,
    endpoint_id: String,
) -> Result<Vec<LmStudioModel>, String> {
    let endpoint = endpoint(&state, &endpoint_id)?;
    fetch_models(&endpoint.base_url).await
}

#[tauri::command]
pub async fn lmstudio_runtime_status(
    state: State<'_, AppState>,
    endpoint_id: Option<String>,
) -> Result<LmStudioRuntimeStatus, String> {
    let endpoint = endpoint_id
        .as_deref()
        .and_then(|id| endpoints::get(&state.db, id).ok().flatten())
        .or_else(|| first_lmstudio_endpoint(&state));
    runtime_status(endpoint.as_ref(), None).await
}

#[tauri::command]
pub async fn lmstudio_prepare(
    state: State<'_, AppState>,
    args: LmStudioPrepareArgs,
) -> Result<LmStudioRuntimeStatus, String> {
    let endpoint = endpoint(&state, &args.endpoint_id)?;
    let cli = match lms_binary() {
        Some(path) => path,
        None => {
            return runtime_status(
                Some(&endpoint),
                Some("`lms` CLI not found on PATH.".to_string()),
            )
            .await;
        }
    };

    let base_url = endpoint.base_url.trim();
    if !server_is_up(base_url).await {
        if let Err(error) = start_server(&cli, base_url).await {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not start LM Studio server: {error}")),
            )
            .await;
        }
        if !wait_for_server(base_url, Duration::from_secs(10)).await {
            return runtime_status(
                Some(&endpoint),
                Some("LM Studio server did not become reachable after start.".to_string()),
            )
            .await;
        }
    }

    let models = fetch_models(base_url).await.unwrap_or_default();
    let Some(target) = choose_model(&models, args.preferred_model.as_deref()) else {
        return runtime_status(
            Some(&endpoint),
            Some("No local LM Studio models were found.".to_string()),
        )
        .await;
    };

    if args.auto_scale {
        let _ = run_lms(
            &cli,
            ["unload", target.id.as_str()],
            Duration::from_secs(45),
        )
        .await;
        let context = args.context_target.max(4_096).to_string();
        let load_args = [
            "load",
            target.id.as_str(),
            "-y",
            "-c",
            context.as_str(),
            "--parallel",
            "1",
            "--gpu",
            "max",
        ];
        if let Err(error) = run_lms(&cli, load_args, Duration::from_secs(180)).await {
            let fallback = run_lms(
                &cli,
                ["load", target.id.as_str(), "-y"],
                Duration::from_secs(120),
            )
            .await;
            if fallback.is_err() {
                return runtime_status(
                    Some(&endpoint),
                    Some(format!("Could not load {}: {error}", target.id)),
                )
                .await;
            }
        }
    } else if let Err(error) = run_lms(
        &cli,
        ["load", target.id.as_str(), "-y"],
        Duration::from_secs(120),
    )
    .await
    {
        return runtime_status(
            Some(&endpoint),
            Some(format!("Could not load {}: {error}", target.id)),
        )
        .await;
    }

    runtime_status(Some(&endpoint), None).await
}

pub async fn fetch_models(base_url: &str) -> Result<Vec<LmStudioModel>, String> {
    let client = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(4))
        .build()
        .map_err(|e| e.to_string())?;

    if let Ok(models) = fetch_native_models(&client, base_url).await {
        if !models.is_empty() {
            return Ok(sort_models(models));
        }
    }

    fetch_openai_models(&client, base_url)
        .await
        .map(sort_models)
}

pub async fn server_is_up(base_url: &str) -> bool {
    let Ok(client) = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_millis(1500))
        .build()
    else {
        return false;
    };
    client
        .get(openai_models_url(base_url))
        .send()
        .await
        .map(|response| response.status().is_success())
        .unwrap_or(false)
}

pub fn openai_models_url(base_url: &str) -> String {
    format!("{}/models", openai_api_root(base_url))
}

pub fn chat_completions_url(base_url: &str) -> String {
    format!("{}/chat/completions", openai_api_root(base_url))
}

pub fn native_models_url(base_url: &str) -> String {
    format!("{}/models", native_api_root(base_url))
}

pub fn openai_api_root(base_url: &str) -> String {
    let trimmed = clean_base_url(base_url);
    if trimmed.ends_with("/v1") {
        trimmed
    } else {
        format!("{trimmed}/v1")
    }
}

pub fn native_api_root(base_url: &str) -> String {
    let trimmed = clean_base_url(base_url);
    let without_v1 = trimmed.strip_suffix("/v1").unwrap_or(&trimmed);
    format!("{without_v1}/api/v0")
}

pub fn choose_model<'a>(
    models: &'a [LmStudioModel],
    preferred_model: Option<&str>,
) -> Option<&'a LmStudioModel> {
    if let Some(preferred) = preferred_model.map(str::trim).filter(|s| !s.is_empty()) {
        if let Some(model) = models.iter().find(|model| model.id == preferred) {
            return Some(model);
        }
    }
    models
        .iter()
        .min_by(|lhs, rhs| model_rank(lhs).cmp(&model_rank(rhs)))
}

async fn runtime_status(
    endpoint: Option<&LocalEndpoint>,
    last_error: Option<String>,
) -> Result<LmStudioRuntimeStatus, String> {
    let cli_installed = lms_binary().is_some();
    let Some(endpoint) = endpoint else {
        return Ok(LmStudioRuntimeStatus {
            cli_installed,
            server_reachable: false,
            state: "no-endpoint".to_string(),
            models: Vec::new(),
            recommended_model_id: None,
            last_error: last_error
                .or_else(|| Some("No LM Studio endpoint is configured.".to_string())),
        });
    };

    let server_reachable = server_is_up(&endpoint.base_url).await;
    let models = if server_reachable {
        fetch_models(&endpoint.base_url).await.unwrap_or_default()
    } else {
        Vec::new()
    };
    let recommended_model_id =
        choose_model(&models, endpoint.default_model.trim().into()).map(|model| model.id.clone());
    let state = if !cli_installed {
        "missing-cli"
    } else if server_reachable {
        "running"
    } else {
        "stopped"
    }
    .to_string();

    Ok(LmStudioRuntimeStatus {
        cli_installed,
        server_reachable,
        state,
        models,
        recommended_model_id,
        last_error,
    })
}

fn endpoint(state: &State<'_, AppState>, endpoint_id: &str) -> Result<LocalEndpoint, String> {
    let endpoint = endpoints::get(&state.db, endpoint_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("endpoint {endpoint_id} not found"))?;
    if endpoint.kind != "lmstudio" {
        return Err(format!(
            "endpoint {} is not an LM Studio endpoint",
            endpoint.name
        ));
    }
    Ok(endpoint)
}

fn first_lmstudio_endpoint(state: &State<'_, AppState>) -> Option<LocalEndpoint> {
    endpoints::list(&state.db)
        .ok()?
        .into_iter()
        .find(|endpoint| endpoint.kind == "lmstudio")
}

async fn fetch_native_models(
    client: &Client,
    base_url: &str,
) -> Result<Vec<LmStudioModel>, String> {
    let response = client
        .get(native_models_url(base_url))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let decoded = response
        .json::<NativeModelsResponse>()
        .await
        .map_err(|e| e.to_string())?;
    Ok(decoded.data.into_iter().map(LmStudioModel::from).collect())
}

async fn fetch_openai_models(
    client: &Client,
    base_url: &str,
) -> Result<Vec<LmStudioModel>, String> {
    let response = client
        .get(openai_models_url(base_url))
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let decoded = response
        .json::<OpenAIModelsResponse>()
        .await
        .map_err(|e| e.to_string())?;
    Ok(decoded
        .data
        .into_iter()
        .map(|entry| LmStudioModel::fallback(entry.id))
        .collect())
}

fn sort_models(mut models: Vec<LmStudioModel>) -> Vec<LmStudioModel> {
    models.sort_by(|lhs, rhs| model_rank(lhs).cmp(&model_rank(rhs)));
    models
}

fn model_rank(model: &LmStudioModel) -> (i32, i32, i32, String) {
    let tool = model.trained_for_tool_use == Some(true);
    let coder = is_coder_model(&model.id)
        || model
            .architecture
            .as_deref()
            .map(is_coder_model)
            .unwrap_or(false);
    (
        if model.loaded { 0 } else { 1 },
        if tool { 0 } else { 1 },
        if coder { 0 } else { 1 },
        model.id.to_ascii_lowercase(),
    )
}

fn is_coder_model(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    ["qwen", "deepseek", "codestral", "coder", "code", "gpt-oss"]
        .iter()
        .any(|needle| lower.contains(needle))
}

fn clean_base_url(base_url: &str) -> String {
    let trimmed = base_url.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        DEFAULT_LMSTUDIO_BASE_URL.to_string()
    } else {
        trimmed.to_string()
    }
}

fn default_context_target() -> i64 {
    65_536
}

fn default_true() -> bool {
    true
}

fn lms_binary() -> Option<PathBuf> {
    let names = ["lms", "lms.exe", "lms.cmd", "lms.bat"];
    for name in names {
        if let Ok(path) = which::which(name) {
            return Some(path);
        }
    }

    let mut candidates = Vec::new();
    if let Some(home) = std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME")) {
        let home = PathBuf::from(home);
        candidates.push(home.join(".lmstudio").join("bin").join("lms.exe"));
        candidates.push(home.join(".lmstudio").join("bin").join("lms.cmd"));
        candidates.push(home.join(".lmstudio").join("bin").join("lms"));
    }

    candidates.into_iter().find(|path| path.exists())
}

async fn start_server(cli: &PathBuf, base_url: &str) -> Result<String, String> {
    let port = reqwest::Url::parse(&openai_api_root(base_url))
        .ok()
        .and_then(|url| url.port())
        .unwrap_or(1234)
        .to_string();

    let server_start = run_lms(
        cli,
        ["server", "start", "--port", port.as_str()],
        Duration::from_secs(30),
    )
    .await;
    if server_start.is_ok() {
        return server_start;
    }

    run_lms(cli, ["daemon", "up"], Duration::from_secs(30)).await
}

async fn wait_for_server(base_url: &str, duration: Duration) -> bool {
    let started = std::time::Instant::now();
    while started.elapsed() < duration {
        if server_is_up(base_url).await {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(350)).await;
    }
    server_is_up(base_url).await
}

async fn run_lms<I, S>(cli: &PathBuf, args: I, duration: Duration) -> Result<String, String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut command = Command::new(cli);
    for arg in args {
        command.arg(OsString::from(arg.as_ref()));
    }
    let output = timeout(duration, command.output())
        .await
        .map_err(|_| "lms command timed out".to_string())?
        .map_err(|e| e.to_string())?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        Err(if stderr.is_empty() { stdout } else { stderr })
    }
}

#[derive(Debug, Deserialize)]
struct NativeModelsResponse {
    data: Vec<NativeModelEntry>,
}

#[derive(Debug, Deserialize)]
struct NativeModelEntry {
    id: String,
    state: Option<String>,
    loaded: Option<bool>,
    max_context_length: Option<i64>,
    loaded_context_length: Option<i64>,
    quantization: Option<String>,
    arch: Option<String>,
    architecture: Option<String>,
    trained_for_tool_use: Option<bool>,
    #[serde(rename = "trainedForToolUse")]
    trained_for_tool_use_camel: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct OpenAIModelsResponse {
    data: Vec<OpenAIModelEntry>,
}

#[derive(Debug, Deserialize)]
struct OpenAIModelEntry {
    id: String,
}

impl From<NativeModelEntry> for LmStudioModel {
    fn from(entry: NativeModelEntry) -> Self {
        let loaded = entry.loaded.unwrap_or_else(|| {
            entry
                .state
                .as_deref()
                .map(|state| state.eq_ignore_ascii_case("loaded"))
                .unwrap_or(false)
        });
        let context_length = entry.loaded_context_length.or(entry.max_context_length);
        let architecture = entry.arch.or(entry.architecture);
        let trained_for_tool_use = entry
            .trained_for_tool_use
            .or(entry.trained_for_tool_use_camel);
        let mut model = Self {
            id: entry.id,
            loaded,
            context_length,
            quantization: entry.quantization,
            architecture,
            trained_for_tool_use,
            schema_supported: None,
            detail: String::new(),
        };
        model.detail = model_detail(&model);
        model
    }
}

impl LmStudioModel {
    fn fallback(id: String) -> Self {
        Self {
            id,
            loaded: false,
            context_length: None,
            quantization: None,
            architecture: None,
            trained_for_tool_use: None,
            schema_supported: None,
            detail: String::new(),
        }
    }
}

fn model_detail(model: &LmStudioModel) -> String {
    let mut bits = Vec::new();
    if model.loaded {
        bits.push("loaded".to_string());
    }
    if let Some(context) = model.context_length {
        bits.push(format_context(context));
    }
    if let Some(quantization) = model.quantization.as_deref().filter(|s| !s.is_empty()) {
        bits.push(quantization.to_string());
    }
    if let Some(architecture) = model.architecture.as_deref().filter(|s| !s.is_empty()) {
        bits.push(architecture.to_string());
    }
    match model.trained_for_tool_use {
        Some(true) => bits.push("tools".to_string()),
        Some(false) => bits.push("no tools".to_string()),
        None => {}
    }
    bits.join(" · ")
}

fn format_context(context: i64) -> String {
    if context >= 1000 {
        format!("{}k ctx", context / 1000)
    } else {
        format!("{context} ctx")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lmstudio_urls_strip_v1_for_native_api() {
        assert_eq!(
            native_models_url("http://localhost:1234/v1"),
            "http://localhost:1234/api/v0/models"
        );
        assert_eq!(
            native_models_url("http://localhost:1234/v1/"),
            "http://localhost:1234/api/v0/models"
        );
        assert_eq!(
            native_models_url("http://localhost:1234"),
            "http://localhost:1234/api/v0/models"
        );
    }

    #[test]
    fn chat_url_accepts_root_or_v1_base_url() {
        assert_eq!(
            chat_completions_url("http://localhost:1234"),
            "http://localhost:1234/v1/chat/completions"
        );
        assert_eq!(
            chat_completions_url("http://localhost:1234/v1"),
            "http://localhost:1234/v1/chat/completions"
        );
    }

    #[test]
    fn chooses_loaded_tool_coder_model_first() {
        let models = vec![
            LmStudioModel::fallback("alpha-chat".to_string()),
            LmStudioModel {
                id: "qwen3-coder".to_string(),
                loaded: true,
                context_length: Some(65_536),
                quantization: Some("Q4_K_M".to_string()),
                architecture: Some("qwen".to_string()),
                trained_for_tool_use: Some(true),
                schema_supported: None,
                detail: String::new(),
            },
        ];
        assert_eq!(
            choose_model(&models, None).map(|m| m.id.as_str()),
            Some("qwen3-coder")
        );
        assert_eq!(
            choose_model(&models, Some("alpha-chat")).map(|m| m.id.as_str()),
            Some("alpha-chat")
        );
    }
}
