//! Port of Loom/Agents/AgentRegistry.parseClaudeAgentsList (Swift).
//! Pure, deterministic, no side effects. Mirrors the Swift parser's contract:
//! consumes `claude agents list` stdout and produces a flat list of agents.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentDescriptor {
    pub name: String,
    pub scope: AgentScope,
    pub description: String,
    pub tools: Vec<String>,
    pub model: Option<String>,
    pub color: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentScope {
    Project,
    User,
    Builtin,
}

pub fn parse_claude_agents_list(stdout: &str) -> Vec<AgentDescriptor> {
    let mut agents = Vec::new();
    let mut current_scope: Option<AgentScope> = None;
    let mut current: Option<AgentDescriptor> = None;

    for raw_line in stdout.lines() {
        let line = strip_ansi(raw_line);
        let trimmed = line.trim_end();

        if let Some(scope) = scope_header(&line) {
            if let Some(agent) = current.take() {
                agents.push(agent);
            }
            current_scope = Some(scope);
            continue;
        }

        if let Some(name) = agent_header(trimmed) {
            if let Some(agent) = current.take() {
                agents.push(agent);
            }
            current = Some(AgentDescriptor {
                name,
                scope: current_scope.unwrap_or(AgentScope::User),
                description: String::new(),
                tools: Vec::new(),
                model: None,
                color: None,
            });
            continue;
        }

        if let Some(agent) = current.as_mut() {
            let lower = line.trim_start().to_ascii_lowercase();
            if let Some(rest) = lower.strip_prefix("description:") {
                agent.description = rest.trim().to_string();
            } else if let Some(rest) = lower.strip_prefix("tools:") {
                agent.tools = rest
                    .split(|c: char| c == ',' || c.is_whitespace())
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .collect();
            } else if let Some(rest) = lower.strip_prefix("model:") {
                agent.model = Some(rest.trim().to_string());
            } else if let Some(rest) = lower.strip_prefix("color:") {
                agent.color = Some(rest.trim().to_string());
            }
        }
    }
    if let Some(agent) = current.take() {
        agents.push(agent);
    }
    agents
}

fn scope_header(line: &str) -> Option<AgentScope> {
    let lower = line.trim().to_ascii_lowercase();
    if lower.contains("project agents") || lower == "project" {
        Some(AgentScope::Project)
    } else if lower.contains("user agents") || lower == "user" {
        Some(AgentScope::User)
    } else if lower.contains("built-in agents") || lower.contains("builtin agents") {
        Some(AgentScope::Builtin)
    } else {
        None
    }
}

fn agent_header(line: &str) -> Option<String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }
    let candidate = trimmed
        .trim_start_matches(|c: char| !c.is_alphanumeric() && c != '_' && c != '-')
        .trim();
    if !candidate.is_empty()
        && candidate
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Some(candidate.to_string());
    }
    None
}

fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\u{1b}' {
            if matches!(chars.peek(), Some(&'[')) {
                chars.next();
                while let Some(&next) = chars.peek() {
                    chars.next();
                    if next.is_alphabetic() {
                        break;
                    }
                }
                continue;
            }
        }
        out.push(c);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_simple_agent() {
        let input = "Project agents\n  loom-agent\n    description: Test\n    tools: Read, Write\n    model: sonnet\n";
        let parsed = parse_claude_agents_list(input);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].name, "loom-agent");
        assert_eq!(parsed[0].scope, AgentScope::Project);
        assert_eq!(parsed[0].description, "Test");
        assert_eq!(parsed[0].tools, vec!["read", "write"]);
        assert_eq!(parsed[0].model.as_deref(), Some("sonnet"));
    }

    #[test]
    fn parses_multiple_scopes() {
        let input = "Project agents\n  a-one\n    description: P\nUser agents\n  b-two\n    description: U\n";
        let parsed = parse_claude_agents_list(input);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].scope, AgentScope::Project);
        assert_eq!(parsed[1].scope, AgentScope::User);
    }
}
