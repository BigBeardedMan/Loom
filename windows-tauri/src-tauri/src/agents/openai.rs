// OpenAI-compatible streaming client. Handles both Ollama (which exposes a
// /v1/chat/completions endpoint matching the OpenAI shape) and any
// third-party OpenAI-compatible API (Groq, OpenRouter, vLLM, etc).
//
// Normalizes streamed deltas into the same `{ kind: "content_block_delta",
// data: { delta: { text: <chunk> } } }` envelope the Anthropic path emits,
// so AgentPane's existing event handler works untouched.

use crate::agents::lmstudio;
use crate::db::endpoints;
use crate::state::AppState;
use futures_util::StreamExt;
use keyring::Entry;
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
    pub previous_response_id: Option<String>,
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

    let mut args = args;
    if endpoint.kind == "lmstudio" && args.model.trim().is_empty() {
        let models = lmstudio::fetch_models(&endpoint.base_url)
            .await
            .map_err(|e| format!("Could not discover LM Studio models: {e}"))?;
        let model = lmstudio::choose_model(&models, Some(endpoint.default_model.as_str()))
            .ok_or_else(|| "No local LM Studio models were found.".to_string())?;
        args.model = model.id.clone();
    }

    let stream_id = Uuid::new_v4().to_string();
    let app_clone = app.clone();
    let stream_id_clone = stream_id.clone();

    tokio::spawn(async move {
        if endpoint.kind == "lmstudio" {
            match stream_lmstudio_native(
                &app_clone,
                &stream_id_clone,
                &endpoint,
                auth_token.as_deref(),
                &args,
            )
            .await
            {
                Ok(()) => {
                    let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 0i32);
                    return;
                }
                Err(reason) => {
                    let _ = app_clone.emit(
                        &format!("agent://{stream_id_clone}/event"),
                        StreamedEvent {
                            kind: "lmstudio_status".to_string(),
                            data: serde_json::json!({
                                "phase": "fallback",
                                "label": "OpenAI-compatible fallback",
                                "detail": reason,
                            }),
                        },
                    );
                }
            }
        }

        let url = lmstudio::chat_completions_url(&endpoint.base_url);

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
        if endpoint.kind == "lmstudio" {
            req = req.bearer_auth("lm-studio");
        }
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
            emit_error(
                &app_clone,
                &stream_id_clone,
                format!("HTTP {status}: {text}"),
            );
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

async fn stream_lmstudio_native(
    app: &AppHandle,
    stream_id: &str,
    endpoint: &endpoints::LocalEndpoint,
    auth_token: Option<&str>,
    args: &OpenAiSendArgs,
) -> Result<(), String> {
    let input = latest_user_content(&args.messages)
        .ok_or_else(|| "No user input to send through native v1 chat.".to_string())?;
    let mut body = serde_json::json!({
        "model": args.model,
        "input": input,
        "stream": true,
        "store": true,
        "context_length": 65536,
    });
    if let Some(system) = args.system.as_deref().filter(|s| !s.is_empty()) {
        body["system_prompt"] = Value::from(system);
    }
    if let Some(m) = args.max_tokens {
        body["max_output_tokens"] = Value::from(m);
    }
    if let Some(t) = args.temperature {
        body["temperature"] = serde_json::json!(t);
    } else {
        body["temperature"] = serde_json::json!(0);
    }
    if let Some(previous_response_id) = args
        .previous_response_id
        .as_deref()
        .filter(|id| id.starts_with("resp_"))
    {
        body["previous_response_id"] = Value::from(previous_response_id);
    }

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(600))
        .build()
        .map_err(|e| e.to_string())?;
    let mut req = client
        .post(lmstudio::native_chat_url(&endpoint.base_url))
        .header("content-type", "application/json")
        .header("accept", "text/event-stream")
        .bearer_auth("lm-studio");
    if let Some(token) = auth_token.filter(|t| !t.is_empty()) {
        req = req.bearer_auth(token);
    }

    let resp = req.json(&body).send().await.map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        let status = resp.status();
        let text = resp.text().await.unwrap_or_default();
        return Err(format!(
            "native v1 chat HTTP {status}: {}",
            text.chars().take(180).collect::<String>()
        ));
    }

    let mut stream = resp.bytes_stream();
    let mut buffer = String::new();
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| e.to_string())?;
        buffer.push_str(&String::from_utf8_lossy(&bytes));
        while let Some(idx) = buffer.find("\n\n") {
            let event = buffer[..idx].to_string();
            buffer.drain(..idx + 2);
            handle_lmstudio_native_event(app, stream_id, &event);
        }
    }
    if !buffer.trim().is_empty() {
        handle_lmstudio_native_event(app, stream_id, &buffer);
    }
    Ok(())
}

fn latest_user_content(messages: &[Value]) -> Option<String> {
    messages.iter().rev().find_map(|message| {
        let role = message.get("role").and_then(Value::as_str)?;
        if role != "user" {
            return None;
        }
        match message.get("content") {
            Some(Value::String(text)) => Some(text.clone()),
            Some(Value::Array(items)) => {
                let text = items
                    .iter()
                    .filter_map(|item| item.get("text").and_then(Value::as_str))
                    .collect::<Vec<_>>()
                    .join("\n");
                (!text.is_empty()).then_some(text)
            }
            _ => None,
        }
    })
}

fn handle_lmstudio_native_event(app: &AppHandle, stream_id: &str, event: &str) {
    let Some((name, data)) = parse_named_sse_event(event) else {
        return;
    };
    let event_type = data
        .get("type")
        .and_then(Value::as_str)
        .unwrap_or(name.as_str());
    match event_type {
        "message.delta" => {
            if let Some(content) = data.get("content").and_then(Value::as_str) {
                emit_content_delta(app, stream_id, content);
            }
        }
        "reasoning.start" | "reasoning.delta" | "reasoning.end" => {
            emit_lmstudio_status(app, stream_id, "reasoning", "Reasoning", None, None);
        }
        "model_load.start" => emit_lmstudio_status(
            app,
            stream_id,
            "model-load",
            "Loading model",
            data.get("model_instance_id").and_then(Value::as_str),
            Some(0.0),
        ),
        "model_load.progress" => emit_lmstudio_status(
            app,
            stream_id,
            "model-load",
            "Loading model",
            data.get("model_instance_id").and_then(Value::as_str),
            data.get("progress").and_then(Value::as_f64),
        ),
        "model_load.end" => emit_lmstudio_status(
            app,
            stream_id,
            "model-load",
            "Model loaded",
            None,
            Some(1.0),
        ),
        "prompt_processing.start" => emit_lmstudio_status(
            app,
            stream_id,
            "prompt-processing",
            "Processing prompt",
            None,
            Some(0.0),
        ),
        "prompt_processing.progress" => emit_lmstudio_status(
            app,
            stream_id,
            "prompt-processing",
            "Processing prompt",
            None,
            data.get("progress").and_then(Value::as_f64),
        ),
        "prompt_processing.end" => emit_lmstudio_status(
            app,
            stream_id,
            "prompt-processing",
            "Prompt processed",
            None,
            Some(1.0),
        ),
        "tool_call.start" | "tool_call.arguments" | "tool_call.success" => emit_lmstudio_status(
            app,
            stream_id,
            "native-tool",
            data.get("tool")
                .and_then(Value::as_str)
                .unwrap_or("Native tool"),
            Some(event_type),
            None,
        ),
        "tool_call.failure" => emit_lmstudio_status(
            app,
            stream_id,
            "native-tool",
            "Native tool failed",
            data.get("reason").and_then(Value::as_str),
            None,
        ),
        "error" => {
            let detail = data
                .get("error")
                .and_then(|e| e.get("message"))
                .and_then(Value::as_str);
            emit_lmstudio_status(
                app,
                stream_id,
                "error",
                "LM Studio native error",
                detail,
                None,
            );
        }
        "chat.end" => {
            if let Some(result) = data.get("result") {
                let payload = serde_json::json!({
                    "stats": result.get("stats").cloned().unwrap_or(Value::Null),
                    "responseId": result.get("response_id").and_then(Value::as_str),
                    "modelInstanceId": result.get("model_instance_id").and_then(Value::as_str),
                });
                let _ = app.emit(
                    &format!("agent://{stream_id}/event"),
                    StreamedEvent {
                        kind: "lmstudio_usage".to_string(),
                        data: payload,
                    },
                );
            }
        }
        _ => {}
    }
}

fn emit_content_delta(app: &AppHandle, stream_id: &str, content: &str) {
    if content.is_empty() {
        return;
    }
    let envelope = serde_json::json!({
        "delta": { "text": content }
    });
    let _ = app.emit(
        &format!("agent://{stream_id}/event"),
        StreamedEvent {
            kind: "content_block_delta".to_string(),
            data: envelope,
        },
    );
}

fn emit_lmstudio_status(
    app: &AppHandle,
    stream_id: &str,
    phase: &str,
    label: &str,
    detail: Option<&str>,
    progress: Option<f64>,
) {
    let _ = app.emit(
        &format!("agent://{stream_id}/event"),
        StreamedEvent {
            kind: "lmstudio_status".to_string(),
            data: serde_json::json!({
                "phase": phase,
                "label": label,
                "detail": detail,
                "progress": progress,
            }),
        },
    );
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

fn parse_named_sse_event(event: &str) -> Option<(String, Value)> {
    let mut name = String::new();
    let mut data_lines = Vec::new();
    for line in event.lines() {
        if let Some(rest) = line.strip_prefix("event:") {
            name = rest.trim().to_string();
        } else if let Some(rest) = line.strip_prefix("data:") {
            data_lines.push(rest.trim_start().to_string());
        }
    }
    if data_lines.is_empty() {
        return None;
    }
    let data = data_lines.join("\n");
    let parsed = serde_json::from_str::<Value>(&data).ok()?;
    if name.is_empty() {
        name = parsed
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
    }
    Some((name, parsed))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_named_lmstudio_sse_event() {
        let raw =
            "event: message.delta\ndata: {\"type\":\"message.delta\",\"content\":\"hello\"}\n\n";
        let (name, data) = parse_named_sse_event(raw).expect("event");
        assert_eq!(name, "message.delta");
        assert_eq!(data.get("content").and_then(Value::as_str), Some("hello"));
    }

    #[test]
    fn extracts_latest_user_content() {
        let messages = vec![
            serde_json::json!({"role": "user", "content": "first"}),
            serde_json::json!({"role": "assistant", "content": "answer"}),
            serde_json::json!({"role": "user", "content": "second"}),
        ];
        assert_eq!(latest_user_content(&messages).as_deref(), Some("second"));
    }
}
