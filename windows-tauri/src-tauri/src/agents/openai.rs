// OpenAI-compatible streaming client. Handles both Ollama (which exposes a
// /v1/chat/completions endpoint matching the OpenAI shape) and any
// third-party OpenAI-compatible API (Groq, OpenRouter, vLLM, etc).
//
// Normalizes streamed deltas into the same `{ kind: "content_block_delta",
// data: { delta: { text: <chunk> } } }` envelope the Anthropic path emits,
// so AgentPane's existing event handler works untouched.

use crate::db::endpoints;
use crate::state::AppState;
use keyring::Entry;
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::Duration;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenAiSendArgs {
    pub endpoint_id: String,
    pub model: String,
    pub messages: Vec<Value>,
    pub system: Option<String>,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
}

#[derive(Debug, Clone, Serialize)]
struct StreamedEvent {
    #[serde(rename = "type")]
    kind: String,
    data: Value,
}

#[tauri::command]
pub async fn agent_openai_send(
    app: AppHandle,
    state: State<'_, AppState>,
    args: OpenAiSendArgs,
) -> Result<String, String> {
    let endpoint = endpoints::get(&state.db, &args.endpoint_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("endpoint {} not found", args.endpoint_id))?;

    let auth_token = if endpoint.requires_auth {
        match Entry::new("loom.endpoint", &endpoint.id) {
            Ok(entry) => match entry.get_password() {
                Ok(token) if !token.is_empty() => Some(token),
                _ => None,
            },
            _ => None,
        }
    } else {
        None
    };

    let stream_id = Uuid::new_v4().to_string();
    let app_clone = app.clone();
    let stream_id_clone = stream_id.clone();

    tokio::spawn(async move {
        let url = format!(
            "{}/v1/chat/completions",
            endpoint.base_url.trim_end_matches('/')
        );

        let mut messages = args.messages.clone();
        if let Some(system) = args.system.as_deref().filter(|s| !s.is_empty()) {
            messages.insert(
                0,
                serde_json::json!({ "role": "system", "content": system }),
            );
        }

        let mut body = serde_json::json!({
            "model": args.model,
            "messages": messages,
            "stream": true,
        });
        if let Some(m) = args.max_tokens {
            body["max_tokens"] = Value::from(m);
        }
        if let Some(t) = args.temperature {
            body["temperature"] = serde_json::json!(t);
        }

        let client = match reqwest::Client::builder()
            .timeout(Duration::from_secs(600))
            .build()
        {
            Ok(c) => c,
            Err(e) => {
                emit_error(&app_clone, &stream_id_clone, e.to_string());
                return;
            }
        };

        let mut req = client
            .post(&url)
            .header("content-type", "application/json")
            .header("accept", "text/event-stream");
        if let Some(token) = auth_token.as_deref() {
            req = req.bearer_auth(token);
        }

        let resp = match req.json(&body).send().await {
            Ok(r) => r,
            Err(e) => {
                emit_error(&app_clone, &stream_id_clone, e.to_string());
                return;
            }
        };

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            emit_error(&app_clone, &stream_id_clone, format!("HTTP {status}: {text}"));
            return;
        }

        let mut stream = resp.bytes_stream();
        let mut buffer = String::new();
        while let Some(chunk) = stream.next().await {
            let Ok(bytes) = chunk else { break };
            buffer.push_str(&String::from_utf8_lossy(&bytes));
            while let Some(idx) = buffer.find("\n\n") {
                let event = buffer[..idx].to_string();
                buffer.drain(..=idx + 1);
                if let Some(data) = parse_sse_data(&event) {
                    if data == "[DONE]" {
                        continue;
                    }
                    let Ok(parsed) = serde_json::from_str::<Value>(&data) else {
                        continue;
                    };
                    if let Some(content) = parsed
                        .get("choices")
                        .and_then(|c| c.get(0))
                        .and_then(|c| c.get("delta"))
                        .and_then(|d| d.get("content"))
                        .and_then(|c| c.as_str())
                    {
                        let envelope = serde_json::json!({
                            "delta": { "text": content }
                        });
                        let _ = app_clone.emit(
                            &format!("agent://{stream_id_clone}/event"),
                            StreamedEvent {
                                kind: "content_block_delta".to_string(),
                                data: envelope,
                            },
                        );
                    }
                }
            }
        }

        let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 0i32);
    });

    Ok(stream_id)
}

fn emit_error(app: &AppHandle, stream_id: &str, message: String) {
    let _ = app.emit(&format!("agent://{stream_id}/error"), message);
    let _ = app.emit(&format!("agent://{stream_id}/done"), 1i32);
}

fn parse_sse_data(event: &str) -> Option<String> {
    let mut data_lines = Vec::new();
    for line in event.lines() {
        if let Some(rest) = line.strip_prefix("data:") {
            data_lines.push(rest.trim_start().to_string());
        }
    }
    if data_lines.is_empty() {
        None
    } else {
        Some(data_lines.join("\n"))
    }
}
