use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use uuid::Uuid;

const ANTHROPIC_URL: &str = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION: &str = "2023-06-01";

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnthropicSendArgs {
    pub api_key: String,
    pub model: String,
    pub messages: Vec<Value>,
    pub system: Option<String>,
    #[serde(default)]
    pub tools: Vec<Value>,
    pub max_tokens: Option<u32>,
    pub temperature: Option<f32>,
    #[serde(default)]
    pub anthropic_beta: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
struct AnthropicEvent {
    #[serde(rename = "type")]
    kind: String,
    data: Value,
}

#[tauri::command]
pub async fn agent_http_send(app: AppHandle, args: AnthropicSendArgs) -> Result<String, String> {
    let stream_id = Uuid::new_v4().to_string();
    let app_clone = app.clone();
    let stream_id_clone = stream_id.clone();

    tokio::spawn(async move {
        let mut body = serde_json::json!({
            "model": args.model,
            "messages": args.messages,
            "stream": true,
        });
        if let Some(system) = args.system {
            body["system"] = Value::String(system);
        }
        if !args.tools.is_empty() {
            body["tools"] = Value::Array(args.tools);
        }
        body["max_tokens"] = Value::from(args.max_tokens.unwrap_or(8192));
        if let Some(t) = args.temperature {
            body["temperature"] = serde_json::json!(t);
        }

        let client = match reqwest::Client::builder()
            .timeout(Duration::from_secs(600))
            .build()
        {
            Ok(c) => c,
            Err(e) => {
                let _ = app_clone.emit(
                    &format!("agent://{stream_id_clone}/error"),
                    e.to_string(),
                );
                let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 1i32);
                return;
            }
        };

        let mut req = client
            .post(ANTHROPIC_URL)
            .header("x-api-key", &args.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("content-type", "application/json")
            .header("accept", "text/event-stream");
        if !args.anthropic_beta.is_empty() {
            req = req.header("anthropic-beta", args.anthropic_beta.join(","));
        }

        let resp = match req.json(&body).send().await {
            Ok(r) => r,
            Err(e) => {
                let _ = app_clone.emit(
                    &format!("agent://{stream_id_clone}/error"),
                    e.to_string(),
                );
                let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 1i32);
                return;
            }
        };

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            let _ = app_clone.emit(
                &format!("agent://{stream_id_clone}/error"),
                format!("HTTP {status}: {body}"),
            );
            let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 1i32);
            return;
        }

        let mut stream = resp.bytes_stream();
        let mut buffer = String::new();
        while let Some(chunk) = stream.next().await {
            let Ok(bytes) = chunk else {
                break;
            };
            buffer.push_str(&String::from_utf8_lossy(&bytes));
            while let Some(idx) = buffer.find("\n\n") {
                let event = buffer[..idx].to_string();
                buffer.drain(..=idx + 1);
                if let Some(data) = parse_sse_data(&event) {
                    if data == "[DONE]" {
                        continue;
                    }
                    if let Ok(parsed) = serde_json::from_str::<Value>(&data) {
                        let kind = parsed
                            .get("type")
                            .and_then(|v| v.as_str())
                            .unwrap_or("unknown")
                            .to_string();
                        let _ = app_clone.emit(
                            &format!("agent://{stream_id_clone}/event"),
                            AnthropicEvent { kind, data: parsed },
                        );
                    }
                }
            }
        }
        let _ = app_clone.emit(&format!("agent://{stream_id_clone}/done"), 0i32);
    });

    Ok(stream_id)
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
