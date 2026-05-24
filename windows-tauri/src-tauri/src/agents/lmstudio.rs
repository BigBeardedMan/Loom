use crate::db::endpoints::{self, LocalEndpoint};
use crate::state::AppState;
use keyring::Entry;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;
use tauri::State;
use tokio::process::Command;
use tokio::time::timeout;

const DEFAULT_LMSTUDIO_BASE_URL: &str = "http://localhost:1234/v1";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioModel {
    pub id: String,
    pub display_name: Option<String>,
    pub loaded: bool,
    pub context_length: Option<i64>,
    pub max_context_length: Option<i64>,
    pub quantization: Option<String>,
    pub architecture: Option<String>,
    pub trained_for_tool_use: Option<bool>,
    pub size_bytes: Option<i64>,
    pub format: Option<String>,
    pub publisher: Option<String>,
    pub loaded_instance_ids: Vec<String>,
    pub api_mode: String,
    pub schema_supported: Option<bool>,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioRuntimeStatus {
    pub cli_installed: bool,
    pub server_reachable: bool,
    pub state: String,
    pub api_mode: String,
    pub supports_v1: bool,
    pub supports_native_chat: bool,
    pub supports_streaming_events: bool,
    pub supports_stateful_chat: bool,
    pub supports_native_mcp: bool,
    pub supports_model_management: bool,
    pub supports_downloads: bool,
    pub supports_auth_token: bool,
    pub last_capability_error: Option<String>,
    pub models: Vec<LmStudioModel>,
    pub recommended_model_id: Option<String>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all(serialize = "camelCase", deserialize = "snake_case"))]
pub struct LmStudioDownloadStatus {
    pub job_id: Option<String>,
    pub status: String,
    pub total_size_bytes: Option<i64>,
    pub downloaded_bytes: Option<i64>,
    pub bytes_per_second: Option<i64>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub estimated_completion: Option<String>,
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

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioLoadArgs {
    pub endpoint_id: String,
    pub model: String,
    #[serde(default = "default_context_target")]
    pub context_target: i64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioUnloadArgs {
    pub endpoint_id: String,
    pub model: String,
    #[serde(default)]
    pub instance_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LmStudioDownloadArgs {
    pub endpoint_id: String,
    pub model: String,
    #[serde(default)]
    pub quantization: Option<String>,
}

#[tauri::command]
pub async fn lmstudio_models(
    state: State<'_, AppState>,
    endpoint_id: String,
) -> Result<Vec<LmStudioModel>, String> {
    let endpoint = endpoint(&state, &endpoint_id)?;
    fetch_models_with_auth(
        &endpoint.base_url,
        auth_token_for_endpoint(&endpoint).as_deref(),
    )
    .await
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
    let token = auth_token_for_endpoint(&endpoint);
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
    if !server_is_up_with_auth(base_url, token.as_deref()).await {
        if let Err(error) = start_server(&cli, base_url).await {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not start LM Studio server: {error}")),
            )
            .await;
        }
        if !wait_for_server(base_url, token.as_deref(), Duration::from_secs(10)).await {
            return runtime_status(
                Some(&endpoint),
                Some("LM Studio server did not become reachable after start.".to_string()),
            )
            .await;
        }
    }

    let models = fetch_models_with_auth(base_url, token.as_deref())
        .await
        .unwrap_or_default();
    let Some(target) = choose_model(&models, args.preferred_model.as_deref()) else {
        return runtime_status(
            Some(&endpoint),
            Some("No local LM Studio models were found.".to_string()),
        )
        .await;
    };

    let caps = capability_status(base_url, token.as_deref()).await;
    if caps.supports_model_management {
        if args.auto_scale && target.loaded {
            let unload_target = target
                .loaded_instance_ids
                .first()
                .map(String::as_str)
                .unwrap_or(target.id.as_str());
            let _ = unload_model_v1(base_url, unload_target, token.as_deref()).await;
        }
        if let Err(error) = load_model_v1(
            base_url,
            target.id.as_str(),
            args.context_target.max(4_096),
            token.as_deref(),
        )
        .await
        {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not load {}: {error}", target.id)),
            )
            .await;
        }
    } else if args.auto_scale {
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

#[tauri::command]
pub async fn lmstudio_load(
    state: State<'_, AppState>,
    args: LmStudioLoadArgs,
) -> Result<LmStudioRuntimeStatus, String> {
    let endpoint = endpoint(&state, &args.endpoint_id)?;
    let token = auth_token_for_endpoint(&endpoint);
    let context = args.context_target.max(4_096);
    let model = args.model.trim().to_string();
    if model.is_empty() {
        return runtime_status(Some(&endpoint), Some("No model was selected.".to_string())).await;
    }

    let caps = capability_status(&endpoint.base_url, token.as_deref()).await;
    if caps.supports_model_management {
        if let Err(error) =
            load_model_v1(&endpoint.base_url, &model, context, token.as_deref()).await
        {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not load {model}: {error}")),
            )
            .await;
        }
    } else {
        let cli = lms_binary().ok_or_else(|| "`lms` CLI not found on PATH.".to_string())?;
        let context = context.to_string();
        if let Err(error) = run_lms(
            &cli,
            ["load", model.as_str(), "-y", "-c", context.as_str()],
            Duration::from_secs(180),
        )
        .await
        {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not load {model}: {error}")),
            )
            .await;
        }
    }

    runtime_status(Some(&endpoint), None).await
}

#[tauri::command]
pub async fn lmstudio_unload(
    state: State<'_, AppState>,
    args: LmStudioUnloadArgs,
) -> Result<LmStudioRuntimeStatus, String> {
    let endpoint = endpoint(&state, &args.endpoint_id)?;
    let token = auth_token_for_endpoint(&endpoint);
    let model = args.model.trim().to_string();
    let instance_id = args
        .instance_id
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(model.as_str());
    if model.is_empty() {
        return runtime_status(Some(&endpoint), Some("No model was selected.".to_string())).await;
    }

    let caps = capability_status(&endpoint.base_url, token.as_deref()).await;
    if caps.supports_model_management {
        if let Err(error) = unload_model_v1(&endpoint.base_url, instance_id, token.as_deref()).await
        {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not unload {model}: {error}")),
            )
            .await;
        }
    } else {
        let cli = lms_binary().ok_or_else(|| "`lms` CLI not found on PATH.".to_string())?;
        if let Err(error) = run_lms(&cli, ["unload", model.as_str()], Duration::from_secs(45)).await
        {
            return runtime_status(
                Some(&endpoint),
                Some(format!("Could not unload {model}: {error}")),
            )
            .await;
        }
    }

    runtime_status(Some(&endpoint), None).await
}

#[tauri::command]
pub async fn lmstudio_download(
    state: State<'_, AppState>,
    args: LmStudioDownloadArgs,
) -> Result<LmStudioDownloadStatus, String> {
    let endpoint = endpoint(&state, &args.endpoint_id)?;
    download_model_v1(
        &endpoint.base_url,
        args.model.trim(),
        args.quantization
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty()),
        auth_token_for_endpoint(&endpoint).as_deref(),
    )
    .await
}

#[tauri::command]
pub async fn lmstudio_download_status(
    state: State<'_, AppState>,
    endpoint_id: String,
    job_id: String,
) -> Result<LmStudioDownloadStatus, String> {
    let endpoint = endpoint(&state, &endpoint_id)?;
    download_status_v1(
        &endpoint.base_url,
        job_id.trim(),
        auth_token_for_endpoint(&endpoint).as_deref(),
    )
    .await
}

pub async fn fetch_models(base_url: &str) -> Result<Vec<LmStudioModel>, String> {
    fetch_models_with_auth(base_url, None).await
}

pub async fn fetch_models_with_auth(
    base_url: &str,
    auth_token: Option<&str>,
) -> Result<Vec<LmStudioModel>, String> {
    let client = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(4))
        .build()
        .map_err(|e| e.to_string())?;

    if let Ok(models) = fetch_native_v1_models(&client, base_url, auth_token).await {
        if !models.is_empty() {
            return Ok(sort_models(models));
        }
    }

    if let Ok(models) = fetch_native_v0_models(&client, base_url, auth_token).await {
        if !models.is_empty() {
            return Ok(sort_models(models));
        }
    }

    fetch_openai_models(&client, base_url, auth_token)
        .await
        .map(sort_models)
}

pub async fn server_is_up_with_auth(base_url: &str, auth_token: Option<&str>) -> bool {
    let Ok(client) = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_millis(1500))
        .build()
    else {
        return false;
    };
    with_auth(client.get(openai_models_url(base_url)), auth_token)
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

pub fn native_chat_url(base_url: &str) -> String {
    format!("{}/chat", native_api_root(base_url, "v1"))
}

pub fn native_models_url(base_url: &str) -> String {
    format!("{}/models", native_api_root(base_url, "v1"))
}

pub fn native_v0_models_url(base_url: &str) -> String {
    format!("{}/models", native_api_root(base_url, "v0"))
}

pub fn openai_api_root(base_url: &str) -> String {
    let trimmed = clean_base_url(base_url);
    if trimmed.ends_with("/v1") {
        trimmed
    } else {
        format!("{trimmed}/v1")
    }
}

pub fn native_api_root(base_url: &str, version: &str) -> String {
    let trimmed = clean_base_url(base_url);
    let without_v1 = trimmed.strip_suffix("/v1").unwrap_or(&trimmed);
    format!("{without_v1}/api/{version}")
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
            api_mode: "none".to_string(),
            supports_v1: false,
            supports_native_chat: false,
            supports_streaming_events: false,
            supports_stateful_chat: false,
            supports_native_mcp: false,
            supports_model_management: false,
            supports_downloads: false,
            supports_auth_token: false,
            last_capability_error: None,
            models: Vec::new(),
            recommended_model_id: None,
            last_error: last_error
                .or_else(|| Some("No LM Studio endpoint is configured.".to_string())),
        });
    };

    let token = auth_token_for_endpoint(endpoint);
    let server_reachable = server_is_up_with_auth(&endpoint.base_url, token.as_deref()).await;
    let capabilities = if server_reachable {
        capability_status(&endpoint.base_url, token.as_deref()).await
    } else {
        CapabilityStatus {
            api_mode: if cli_installed {
                "offline"
            } else {
                "missing-cli"
            }
            .to_string(),
            supports_v1: false,
            supports_native_chat: false,
            supports_streaming_events: false,
            supports_stateful_chat: false,
            supports_native_mcp: false,
            supports_model_management: false,
            supports_downloads: false,
            supports_auth_token: token.as_deref().is_some_and(|t| !t.is_empty()),
            last_capability_error: None,
        }
    };
    let models = if server_reachable {
        fetch_models_with_auth(&endpoint.base_url, token.as_deref())
            .await
            .unwrap_or_default()
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
        api_mode: capabilities.api_mode,
        supports_v1: capabilities.supports_v1,
        supports_native_chat: capabilities.supports_native_chat,
        supports_streaming_events: capabilities.supports_streaming_events,
        supports_stateful_chat: capabilities.supports_stateful_chat,
        supports_native_mcp: capabilities.supports_native_mcp,
        supports_model_management: capabilities.supports_model_management,
        supports_downloads: capabilities.supports_downloads,
        supports_auth_token: capabilities.supports_auth_token,
        last_capability_error: capabilities.last_capability_error,
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

#[derive(Debug, Clone)]
struct CapabilityStatus {
    api_mode: String,
    supports_v1: bool,
    supports_native_chat: bool,
    supports_streaming_events: bool,
    supports_stateful_chat: bool,
    supports_native_mcp: bool,
    supports_model_management: bool,
    supports_downloads: bool,
    supports_auth_token: bool,
    last_capability_error: Option<String>,
}

async fn capability_status(base_url: &str, auth_token: Option<&str>) -> CapabilityStatus {
    let client = match Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(2))
        .build()
    {
        Ok(client) => client,
        Err(error) => {
            return CapabilityStatus {
                api_mode: "unavailable".to_string(),
                supports_v1: false,
                supports_native_chat: false,
                supports_streaming_events: false,
                supports_stateful_chat: false,
                supports_native_mcp: false,
                supports_model_management: false,
                supports_downloads: false,
                supports_auth_token: auth_token.is_some_and(|s| !s.is_empty()),
                last_capability_error: Some(error.to_string()),
            }
        }
    };

    let v1 = with_auth(client.get(native_models_url(base_url)), auth_token)
        .send()
        .await;
    match v1 {
        Ok(response) if response.status().is_success() => CapabilityStatus {
            api_mode: "v1".to_string(),
            supports_v1: true,
            supports_native_chat: true,
            supports_streaming_events: true,
            supports_stateful_chat: true,
            supports_native_mcp: true,
            supports_model_management: true,
            supports_downloads: true,
            supports_auth_token: auth_token.is_some_and(|s| !s.is_empty()),
            last_capability_error: None,
        },
        Ok(response) => CapabilityStatus {
            api_mode: "openai".to_string(),
            supports_v1: false,
            supports_native_chat: false,
            supports_streaming_events: false,
            supports_stateful_chat: false,
            supports_native_mcp: false,
            supports_model_management: false,
            supports_downloads: false,
            supports_auth_token: auth_token.is_some_and(|s| !s.is_empty()),
            last_capability_error: Some(format!("HTTP {}", response.status())),
        },
        Err(error) => {
            let v0 = with_auth(client.get(native_v0_models_url(base_url)), auth_token)
                .send()
                .await;
            if v0
                .as_ref()
                .is_ok_and(|response| response.status().is_success())
            {
                CapabilityStatus {
                    api_mode: "v0".to_string(),
                    supports_v1: false,
                    supports_native_chat: false,
                    supports_streaming_events: false,
                    supports_stateful_chat: false,
                    supports_native_mcp: false,
                    supports_model_management: false,
                    supports_downloads: false,
                    supports_auth_token: auth_token.is_some_and(|s| !s.is_empty()),
                    last_capability_error: Some(error.to_string()),
                }
            } else {
                CapabilityStatus {
                    api_mode: "openai".to_string(),
                    supports_v1: false,
                    supports_native_chat: false,
                    supports_streaming_events: false,
                    supports_stateful_chat: false,
                    supports_native_mcp: false,
                    supports_model_management: false,
                    supports_downloads: false,
                    supports_auth_token: auth_token.is_some_and(|s| !s.is_empty()),
                    last_capability_error: Some(error.to_string()),
                }
            }
        }
    }
}

async fn fetch_native_v1_models(
    client: &Client,
    base_url: &str,
    auth_token: Option<&str>,
) -> Result<Vec<LmStudioModel>, String> {
    let response = with_auth(client.get(native_models_url(base_url)), auth_token)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let decoded = response
        .json::<NativeV1ModelsResponse>()
        .await
        .map_err(|e| e.to_string())?;
    Ok(decoded
        .models
        .into_iter()
        .map(LmStudioModel::from)
        .collect())
}

async fn fetch_native_v0_models(
    client: &Client,
    base_url: &str,
    auth_token: Option<&str>,
) -> Result<Vec<LmStudioModel>, String> {
    let response = with_auth(client.get(native_v0_models_url(base_url)), auth_token)
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
    auth_token: Option<&str>,
) -> Result<Vec<LmStudioModel>, String> {
    let response = with_auth(client.get(openai_models_url(base_url)), auth_token)
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

async fn load_model_v1(
    base_url: &str,
    model: &str,
    context_target: i64,
    auth_token: Option<&str>,
) -> Result<String, String> {
    let client = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(180))
        .build()
        .map_err(|e| e.to_string())?;
    let body = serde_json::json!({
        "model": model,
        "context_length": context_target.max(4_096),
        "flash_attention": true,
        "offload_kv_cache_to_gpu": true,
        "echo_load_config": true,
    });
    let response = with_auth(
        client.post(format!("{}/models/load", native_api_root(base_url, "v1"))),
        auth_token,
    )
    .header("content-type", "application/json")
    .json(&body)
    .send()
    .await
    .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let decoded = response
        .json::<NativeLoadResponse>()
        .await
        .map_err(|e| e.to_string())?;
    Ok(decoded.instance_id)
}

async fn unload_model_v1(
    base_url: &str,
    instance_id: &str,
    auth_token: Option<&str>,
) -> Result<String, String> {
    let client = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(45))
        .build()
        .map_err(|e| e.to_string())?;
    let body = serde_json::json!({ "instance_id": instance_id });
    let response = with_auth(
        client.post(format!("{}/models/unload", native_api_root(base_url, "v1"))),
        auth_token,
    )
    .header("content-type", "application/json")
    .json(&body)
    .send()
    .await
    .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    let decoded = response
        .json::<NativeUnloadResponse>()
        .await
        .map_err(|e| e.to_string())?;
    Ok(decoded.instance_id)
}

async fn download_model_v1(
    base_url: &str,
    model: &str,
    quantization: Option<&str>,
    auth_token: Option<&str>,
) -> Result<LmStudioDownloadStatus, String> {
    if model.is_empty() {
        return Err("No model was entered.".to_string());
    }
    let client = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(45))
        .build()
        .map_err(|e| e.to_string())?;
    let mut body = serde_json::json!({ "model": model });
    if let Some(quantization) = quantization {
        body["quantization"] = serde_json::json!(quantization);
    }
    let response = with_auth(
        client.post(format!(
            "{}/models/download",
            native_api_root(base_url, "v1")
        )),
        auth_token,
    )
    .header("content-type", "application/json")
    .json(&body)
    .send()
    .await
    .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    response
        .json::<LmStudioDownloadStatus>()
        .await
        .map_err(|e| e.to_string())
}

async fn download_status_v1(
    base_url: &str,
    job_id: &str,
    auth_token: Option<&str>,
) -> Result<LmStudioDownloadStatus, String> {
    if job_id.is_empty() {
        return Err("No download job id was provided.".to_string());
    }
    let client = Client::builder()
        .user_agent(format!("Loom/{}", env!("CARGO_PKG_VERSION")))
        .timeout(Duration::from_secs(20))
        .build()
        .map_err(|e| e.to_string())?;
    let encoded = url::form_urlencoded::byte_serialize(job_id.as_bytes()).collect::<String>();
    let response = with_auth(
        client.get(format!(
            "{}/models/download/status/{}",
            native_api_root(base_url, "v1"),
            encoded
        )),
        auth_token,
    )
    .send()
    .await
    .map_err(|e| e.to_string())?;
    if !response.status().is_success() {
        return Err(format!("HTTP {}", response.status()));
    }
    response
        .json::<LmStudioDownloadStatus>()
        .await
        .map_err(|e| e.to_string())
}

fn with_auth(
    request: reqwest::RequestBuilder,
    auth_token: Option<&str>,
) -> reqwest::RequestBuilder {
    if let Some(token) = auth_token.filter(|token| !token.is_empty()) {
        request.bearer_auth(token)
    } else {
        request.bearer_auth("lm-studio")
    }
}

fn auth_token_for_endpoint(endpoint: &LocalEndpoint) -> Option<String> {
    if !endpoint.requires_auth {
        return None;
    }
    Entry::new("loom.endpoint", &endpoint.id)
        .ok()
        .and_then(|entry| entry.get_password().ok())
        .filter(|token| !token.is_empty())
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

async fn wait_for_server(base_url: &str, auth_token: Option<&str>, duration: Duration) -> bool {
    let started = std::time::Instant::now();
    while started.elapsed() < duration {
        if server_is_up_with_auth(base_url, auth_token).await {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(350)).await;
    }
    server_is_up_with_auth(base_url, auth_token).await
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
struct NativeV1ModelsResponse {
    models: Vec<NativeV1ModelEntry>,
}

#[derive(Debug, Deserialize)]
struct NativeV1ModelEntry {
    publisher: Option<String>,
    key: String,
    display_name: Option<String>,
    architecture: Option<String>,
    quantization: Option<NativeV1Quantization>,
    size_bytes: Option<i64>,
    loaded_instances: Vec<NativeV1LoadedInstance>,
    max_context_length: Option<i64>,
    format: Option<String>,
    capabilities: Option<NativeV1Capabilities>,
}

#[derive(Debug, Deserialize)]
struct NativeV1Quantization {
    name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct NativeV1LoadedInstance {
    id: String,
    config: NativeV1LoadedConfig,
}

#[derive(Debug, Deserialize)]
struct NativeV1LoadedConfig {
    context_length: Option<i64>,
}

#[derive(Debug, Deserialize)]
struct NativeV1Capabilities {
    trained_for_tool_use: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct NativeLoadResponse {
    instance_id: String,
}

#[derive(Debug, Deserialize)]
struct NativeUnloadResponse {
    instance_id: String,
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
            display_name: None,
            loaded,
            context_length,
            max_context_length: entry.max_context_length,
            quantization: entry.quantization,
            architecture,
            trained_for_tool_use,
            size_bytes: None,
            format: None,
            publisher: None,
            loaded_instance_ids: Vec::new(),
            api_mode: "v0".to_string(),
            schema_supported: None,
            detail: String::new(),
        };
        if model.loaded {
            model.loaded_instance_ids.push(model.id.clone());
        }
        model.detail = model_detail(&model);
        model
    }
}

impl From<NativeV1ModelEntry> for LmStudioModel {
    fn from(entry: NativeV1ModelEntry) -> Self {
        let loaded_instances = entry.loaded_instances;
        let context_length = loaded_instances
            .first()
            .and_then(|instance| instance.config.context_length)
            .or(entry.max_context_length);
        let mut model = Self {
            id: entry.key,
            display_name: entry.display_name,
            loaded: !loaded_instances.is_empty(),
            context_length,
            max_context_length: entry.max_context_length,
            quantization: entry.quantization.and_then(|q| q.name),
            architecture: entry.architecture,
            trained_for_tool_use: entry.capabilities.and_then(|c| c.trained_for_tool_use),
            size_bytes: entry.size_bytes,
            format: entry.format,
            publisher: entry.publisher,
            loaded_instance_ids: loaded_instances
                .into_iter()
                .map(|instance| instance.id)
                .collect(),
            api_mode: "v1".to_string(),
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
            display_name: None,
            loaded: false,
            context_length: None,
            max_context_length: None,
            quantization: None,
            architecture: None,
            trained_for_tool_use: None,
            size_bytes: None,
            format: None,
            publisher: None,
            loaded_instance_ids: Vec::new(),
            api_mode: "openai".to_string(),
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
    if let Some(format) = model.format.as_deref().filter(|s| !s.is_empty()) {
        bits.push(format.to_string());
    }
    if let Some(size_bytes) = model.size_bytes.filter(|bytes| *bytes > 0) {
        bits.push(format_bytes(size_bytes));
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

fn format_bytes(bytes: i64) -> String {
    let gb = bytes as f64 / 1_073_741_824.0;
    if gb >= 1.0 {
        format!("{gb:.1} GB")
    } else {
        format!("{:.0} MB", bytes as f64 / 1_048_576.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lmstudio_urls_strip_v1_for_native_api() {
        assert_eq!(
            native_models_url("http://localhost:1234/v1"),
            "http://localhost:1234/api/v1/models"
        );
        assert_eq!(
            native_models_url("http://localhost:1234/v1/"),
            "http://localhost:1234/api/v1/models"
        );
        assert_eq!(
            native_models_url("http://localhost:1234"),
            "http://localhost:1234/api/v1/models"
        );
        assert_eq!(
            native_v0_models_url("http://localhost:1234/v1"),
            "http://localhost:1234/api/v0/models"
        );
        assert_eq!(
            native_chat_url("http://localhost:1234/v1"),
            "http://localhost:1234/api/v1/chat"
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
                display_name: Some("Qwen Coder".to_string()),
                loaded: true,
                context_length: Some(65_536),
                max_context_length: Some(131_072),
                quantization: Some("Q4_K_M".to_string()),
                architecture: Some("qwen".to_string()),
                trained_for_tool_use: Some(true),
                size_bytes: None,
                format: Some("gguf".to_string()),
                publisher: Some("qwen".to_string()),
                loaded_instance_ids: vec!["qwen3-coder".to_string()],
                api_mode: "v1".to_string(),
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
