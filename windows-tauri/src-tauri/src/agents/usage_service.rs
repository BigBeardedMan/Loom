// Mirrors Loom/Agents/UsageService.swift.
// Reads on-disk usage data from local agents (Claude Code, Codex, LM Studio)
// and aggregates token totals, sessions, models, projects, prompts.

use chrono::{DateTime, Datelike, Duration, Local, TimeZone, Timelike, Utc};
use once_cell::sync::Lazy;
use regex::Regex;
use serde::Serialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CliTool {
    Claude,
    Codex,
    LmStudio,
}

impl CliTool {
    fn from_str(s: &str) -> Option<Self> {
        match s {
            "claude" => Some(Self::Claude),
            "codex" => Some(Self::Codex),
            "lmstudio" => Some(Self::LmStudio),
            _ => None,
        }
    }
    fn as_str(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::LmStudio => "lmstudio",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Timeframe {
    Day,
    Week,
    Month,
    Year,
}

impl Timeframe {
    fn from_str(s: &str) -> Self {
        match s {
            "week" => Self::Week,
            "month" => Self::Month,
            "year" => Self::Year,
            _ => Self::Day,
        }
    }
    fn span(self) -> Duration {
        match self {
            Self::Day => Duration::days(1),
            Self::Week => Duration::days(7),
            Self::Month => Duration::days(30),
            Self::Year => Duration::days(365),
        }
    }
    fn bucket_count(self) -> usize {
        match self {
            Self::Day => 24,
            Self::Week => 7,
            Self::Month => 30,
            Self::Year => 12,
        }
    }
    fn boundaries(self, now: DateTime<Local>) -> Vec<BucketBoundary> {
        let n = self.bucket_count();
        let mut out: Vec<BucketBoundary> = Vec::with_capacity(n);
        match self {
            Self::Day => {
                let anchor = now
                    .with_minute(0)
                    .unwrap()
                    .with_second(0)
                    .unwrap()
                    .with_nanosecond(0)
                    .unwrap();
                for i in (0..n as i64).rev() {
                    let start = anchor - Duration::hours(i);
                    let end = start + Duration::hours(1);
                    out.push(BucketBoundary {
                        start,
                        end,
                        label: format!("{:02}", start.hour()),
                    });
                }
            }
            Self::Week | Self::Month => {
                let today = now.date_naive().and_hms_opt(0, 0, 0).unwrap();
                let anchor = Local.from_local_datetime(&today).single().unwrap_or(now);
                for i in (0..n as i64).rev() {
                    let start = anchor - Duration::days(i);
                    let end = start + Duration::days(1);
                    out.push(BucketBoundary {
                        start,
                        end,
                        label: start.format("%m/%d").to_string(),
                    });
                }
            }
            Self::Year => {
                let cur_y = now.year();
                let cur_m = now.month() as i32;
                for i in (0..12_i32).rev() {
                    let mut m = cur_m - i;
                    let mut y = cur_y;
                    while m <= 0 {
                        m += 12;
                        y -= 1;
                    }
                    let start_naive = chrono::NaiveDate::from_ymd_opt(y, m as u32, 1)
                        .unwrap()
                        .and_hms_opt(0, 0, 0)
                        .unwrap();
                    let start = Local
                        .from_local_datetime(&start_naive)
                        .single()
                        .unwrap_or(now);
                    let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
                    let end_naive = chrono::NaiveDate::from_ymd_opt(ny, nm as u32, 1)
                        .unwrap()
                        .and_hms_opt(0, 0, 0)
                        .unwrap();
                    let end = Local
                        .from_local_datetime(&end_naive)
                        .single()
                        .unwrap_or(now);
                    out.push(BucketBoundary {
                        start,
                        end,
                        label: format!("{:02}", m),
                    });
                }
            }
        }
        out
    }
}

struct BucketBoundary {
    start: DateTime<Local>,
    end: DateTime<Local>,
    label: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageBucket {
    pub start: String,
    pub end: String,
    pub tokens: i64,
    pub label: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectUsage {
    pub display_name: String,
    pub path: String,
    pub sessions: i64,
    pub last_activity: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelUsage {
    pub model: String,
    pub tokens: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectTokenSlice {
    pub display_name: String,
    pub path: String,
    pub tokens: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptTopic {
    pub keyword: String,
    pub count: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptPreview {
    pub text: String,
    pub timestamp: String,
    pub project: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CliToolUsage {
    pub tool: String,
    pub is_installed: bool,
    pub active_sessions: i64,
    pub sessions_today: i64,
    pub sessions_total: i64,
    pub input_tokens: i64,
    pub output_tokens: i64,
    pub cached_tokens: i64,
    pub last_activity: Option<String>,
    pub models: Vec<String>,
    pub chart_buckets: Vec<UsageBucket>,
    pub top_projects: Vec<ProjectUsage>,
    pub tokens_by_model: Vec<ModelUsage>,
    pub tokens_by_project: Vec<ProjectTokenSlice>,
    pub top_topics: Vec<PromptTopic>,
    pub recent_prompts: Vec<PromptPreview>,
    pub hourly_distribution: Vec<i64>,
    pub prompt_count: i64,
    pub rate_limit_primary_used_percent: Option<f64>,
    pub rate_limit_primary_window_minutes: Option<i64>,
    pub rate_limit_primary_resets_at: Option<String>,
    pub rate_limit_secondary_used_percent: Option<f64>,
    pub rate_limit_secondary_window_minutes: Option<i64>,
    pub rate_limit_secondary_resets_at: Option<String>,
    pub plan_type: Option<String>,
    pub credits: Option<f64>,
    pub rate_limit_reached_type: Option<String>,
    pub rate_limit_observed_at: Option<String>,
}

impl CliToolUsage {
    fn unavailable(tool: CliTool) -> Self {
        Self {
            tool: tool.as_str().to_string(),
            is_installed: false,
            active_sessions: 0,
            sessions_today: 0,
            sessions_total: 0,
            input_tokens: 0,
            output_tokens: 0,
            cached_tokens: 0,
            last_activity: None,
            models: vec![],
            chart_buckets: vec![],
            top_projects: vec![],
            tokens_by_model: vec![],
            tokens_by_project: vec![],
            top_topics: vec![],
            recent_prompts: vec![],
            hourly_distribution: vec![0; 24],
            prompt_count: 0,
            rate_limit_primary_used_percent: None,
            rate_limit_primary_window_minutes: None,
            rate_limit_primary_resets_at: None,
            rate_limit_secondary_used_percent: None,
            rate_limit_secondary_window_minutes: None,
            rate_limit_secondary_resets_at: None,
            plan_type: None,
            credits: None,
            rate_limit_reached_type: None,
            rate_limit_observed_at: None,
        }
    }
}

// Stopwords copied verbatim from Loom/Agents/UsageService.swift lines 878-895.
static STOPWORDS: Lazy<HashSet<&'static str>> = Lazy::new(|| {
    [
        "this",
        "that",
        "with",
        "have",
        "from",
        "your",
        "into",
        "about",
        "where",
        "when",
        "what",
        "would",
        "could",
        "should",
        "there",
        "their",
        "they",
        "them",
        "then",
        "than",
        "also",
        "just",
        "like",
        "want",
        "need",
        "make",
        "made",
        "more",
        "some",
        "very",
        "well",
        "going",
        "still",
        "thing",
        "things",
        "really",
        "think",
        "back",
        "down",
        "much",
        "many",
        "most",
        "good",
        "right",
        "wrong",
        "okay",
        "sure",
        "yeah",
        "actually",
        "claude",
        "code",
        "please",
        "thanks",
        "thank",
        "hello",
        "look",
        "looks",
        "show",
        "shows",
        "let",
        "let's",
        "doesn",
        "didn",
        "won",
        "haven",
        "isn",
        "aren",
        "wasn",
        "weren",
        "the",
        "and",
        "but",
        "for",
        "are",
        "was",
        "were",
        "been",
        "being",
        "does",
        "did",
        "use",
        "used",
        "uses",
        "using",
        "get",
        "got",
        "see",
        "saw",
        "seen",
        "way",
        "out",
        "off",
        "now",
        "yes",
        "say",
        "said",
        "tell",
        "told",
        "give",
        "given",
        "currently",
        "current",
        "needs",
        "needed",
        "must",
        "might",
        "since",
        "before",
        "after",
        "while",
    ]
    .into_iter()
    .collect()
});

static CLAUDE_USAGE_RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#""usage":\{"input_tokens":(\d+),"cache_creation_input_tokens":(\d+),"cache_read_input_tokens":(\d+),"output_tokens":(\d+)"#).unwrap()
});

static CLAUDE_MODEL_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r#""model":"(claude-[^"]+)""#).unwrap());

static CLAUDE_PROMPT_RE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r#""role":"user","content":"((?:[^"\\]|\\.)*)""#).unwrap());

static CLAUDE_TS_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r#""timestamp":"([^"]+)""#).unwrap());

fn parse_iso8601(s: &str) -> Option<DateTime<Local>> {
    DateTime::parse_from_rfc3339(s)
        .ok()
        .map(|d| d.with_timezone(&Local))
        .or_else(|| {
            // Some lines drop fractional seconds; try a tolerant alt format.
            chrono::NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%SZ")
                .ok()
                .map(|nd| Utc.from_utc_datetime(&nd).with_timezone(&Local))
        })
}

fn unescape_json(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c != '\\' {
            out.push(c);
            continue;
        }
        let Some(next) = it.next() else { break };
        match next {
            'n' => out.push('\n'),
            't' => out.push('\t'),
            'r' => out.push('\r'),
            '"' => out.push('"'),
            '\\' => out.push('\\'),
            '/' => out.push('/'),
            'u' => {
                let hex: String = it.by_ref().take(4).collect();
                if let Ok(v) = u32::from_str_radix(&hex, 16) {
                    if let Some(ch) = char::from_u32(v) {
                        out.push(ch);
                    }
                }
            }
            other => out.push(other),
        }
    }
    out
}

fn friendly_project_name(raw: &str) -> String {
    let s = raw.strip_prefix('-').unwrap_or(raw);
    let segments: Vec<&str> = s.split('-').collect();
    if segments.is_empty() {
        return raw.to_string();
    }
    let tail = segments
        .iter()
        .rev()
        .take(2)
        .rev()
        .copied()
        .collect::<Vec<_>>();
    tail.join("/")
}

fn extract_keywords(text: &str) -> Vec<String> {
    let lowered = text.to_lowercase();
    let mut seen: HashSet<String> = HashSet::new();
    let mut out: Vec<String> = Vec::new();
    let mut current = String::new();
    let push = |cur: &mut String, seen: &mut HashSet<String>, out: &mut Vec<String>| {
        if cur.is_empty() {
            return;
        }
        let len = cur.chars().count();
        let all_digits = cur.chars().all(|c| c.is_ascii_digit());
        let keep = len >= 4 && len <= 24 && !all_digits && !STOPWORDS.contains(cur.as_str());
        if keep && !seen.contains(cur) {
            seen.insert(cur.clone());
            out.push(cur.clone());
        }
        cur.clear();
    };
    for c in lowered.chars() {
        if c.is_alphanumeric() {
            current.push(c);
        } else {
            push(&mut current, &mut seen, &mut out);
        }
    }
    push(&mut current, &mut seen, &mut out);
    out
}

fn bucket_index(ts: DateTime<Local>, boundaries: &[BucketBoundary]) -> Option<usize> {
    boundaries.iter().position(|b| ts >= b.start && ts < b.end)
}

fn file_mtime(path: &Path) -> Option<DateTime<Local>> {
    let md = fs::metadata(path).ok()?;
    let modified = md.modified().ok()?;
    let secs = modified
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs() as i64;
    Some(Utc.timestamp_opt(secs, 0).single()?.with_timezone(&Local))
}

fn read_text(path: &Path) -> Option<String> {
    let mut f = fs::File::open(path).ok()?;
    let mut s = String::new();
    f.read_to_string(&mut s).ok()?;
    Some(s)
}

fn read_claude_usage(
    root: &Path,
    live_cutoff: DateTime<Local>,
    start_of_today: DateTime<Local>,
    boundaries: &[BucketBoundary],
    window_start: DateTime<Local>,
) -> CliToolUsage {
    if !root.exists() {
        return CliToolUsage::unavailable(CliTool::Claude);
    }

    let mut sessions_total: i64 = 0;
    let mut sessions_today: i64 = 0;
    let mut active_sessions: i64 = 0;
    let mut input_tokens: i64 = 0;
    let mut output_tokens: i64 = 0;
    let mut cached_tokens: i64 = 0;
    let mut last_activity: Option<DateTime<Local>> = None;
    let mut models: HashSet<String> = HashSet::new();

    let mut bucket_tokens: Vec<i64> = vec![0; boundaries.len()];
    let mut hourly: Vec<i64> = vec![0; 24];
    let mut model_tokens: HashMap<String, i64> = HashMap::new();
    let mut project_tokens: HashMap<PathBuf, i64> = HashMap::new();
    let mut project_sessions: HashMap<PathBuf, i64> = HashMap::new();
    let mut project_last: HashMap<PathBuf, DateTime<Local>> = HashMap::new();
    let mut topic_counts: HashMap<String, i64> = HashMap::new();
    let mut prompt_count: i64 = 0;
    let mut recent: Vec<PromptPreview> = Vec::new();

    let project_dirs = match fs::read_dir(root) {
        Ok(it) => it,
        Err(_) => return CliToolUsage::unavailable(CliTool::Claude),
    };

    for entry in project_dirs.flatten() {
        let project_dir = entry.path();
        if !project_dir.is_dir() {
            continue;
        }
        let project_name = friendly_project_name(
            project_dir
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or(""),
        );
        let Ok(files) = fs::read_dir(&project_dir) else {
            continue;
        };
        for f in files.flatten() {
            let path = f.path();
            if path.extension().and_then(|s| s.to_str()) != Some("jsonl") {
                continue;
            }
            let Some(mtime) = file_mtime(&path) else {
                continue;
            };
            sessions_total += 1;
            if mtime >= start_of_today {
                sessions_today += 1;
            }
            if mtime >= live_cutoff {
                active_sessions += 1;
            }
            if last_activity.map_or(true, |la| mtime > la) {
                last_activity = Some(mtime);
            }
            if mtime >= window_start {
                *project_sessions.entry(project_dir.clone()).or_insert(0) += 1;
                project_last
                    .entry(project_dir.clone())
                    .and_modify(|d| {
                        if mtime > *d {
                            *d = mtime;
                        }
                    })
                    .or_insert(mtime);
            }

            let Some(text) = read_text(&path) else {
                continue;
            };
            parse_claude_file(
                &text,
                mtime,
                window_start,
                boundaries,
                &project_dir,
                &project_name,
                &mut input_tokens,
                &mut output_tokens,
                &mut cached_tokens,
                &mut models,
                &mut bucket_tokens,
                &mut hourly,
                &mut model_tokens,
                &mut project_tokens,
                &mut topic_counts,
                &mut prompt_count,
                &mut recent,
            );
        }
    }

    let chart_buckets: Vec<UsageBucket> = boundaries
        .iter()
        .zip(bucket_tokens.iter())
        .map(|(b, t)| UsageBucket {
            start: b.start.to_rfc3339(),
            end: b.end.to_rfc3339(),
            tokens: *t,
            label: b.label.clone(),
        })
        .collect();

    let mut top_projects: Vec<ProjectUsage> = project_sessions
        .iter()
        .filter_map(|(p, sessions)| {
            let last = project_last.get(p)?;
            Some(ProjectUsage {
                display_name: friendly_project_name(
                    p.file_name().and_then(|s| s.to_str()).unwrap_or(""),
                ),
                path: p.to_string_lossy().to_string(),
                sessions: *sessions,
                last_activity: last.to_rfc3339(),
            })
        })
        .collect();
    top_projects.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
    top_projects.truncate(5);

    let mut tokens_by_model: Vec<ModelUsage> = model_tokens
        .into_iter()
        .map(|(model, tokens)| ModelUsage { model, tokens })
        .collect();
    tokens_by_model.sort_by(|a, b| b.tokens.cmp(&a.tokens));

    let mut tokens_by_project: Vec<ProjectTokenSlice> = project_tokens
        .into_iter()
        .map(|(p, tokens)| ProjectTokenSlice {
            display_name: friendly_project_name(
                p.file_name().and_then(|s| s.to_str()).unwrap_or(""),
            ),
            path: p.to_string_lossy().to_string(),
            tokens,
        })
        .collect();
    tokens_by_project.sort_by(|a, b| b.tokens.cmp(&a.tokens));

    let mut top_topics: Vec<PromptTopic> = topic_counts
        .into_iter()
        .filter(|(_, c)| *c >= 2)
        .map(|(keyword, count)| PromptTopic { keyword, count })
        .collect();
    top_topics.sort_by(|a, b| b.count.cmp(&a.count));
    top_topics.truncate(12);

    recent.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    recent.truncate(8);

    let mut models_sorted: Vec<String> = models.into_iter().collect();
    models_sorted.sort();

    CliToolUsage {
        tool: CliTool::Claude.as_str().to_string(),
        is_installed: true,
        active_sessions,
        sessions_today,
        sessions_total,
        input_tokens,
        output_tokens,
        cached_tokens,
        last_activity: last_activity.map(|d| d.to_rfc3339()),
        models: models_sorted,
        chart_buckets,
        top_projects,
        tokens_by_model,
        tokens_by_project,
        top_topics,
        recent_prompts: recent,
        hourly_distribution: hourly,
        prompt_count,
        rate_limit_primary_used_percent: None,
        rate_limit_primary_window_minutes: None,
        rate_limit_primary_resets_at: None,
        rate_limit_secondary_used_percent: None,
        rate_limit_secondary_window_minutes: None,
        rate_limit_secondary_resets_at: None,
        plan_type: None,
        credits: None,
        rate_limit_reached_type: None,
        rate_limit_observed_at: None,
    }
}

fn parse_claude_file(
    text: &str,
    file_mtime: DateTime<Local>,
    window_start: DateTime<Local>,
    boundaries: &[BucketBoundary],
    project_dir: &Path,
    project_name: &str,
    input_tokens: &mut i64,
    output_tokens: &mut i64,
    cached_tokens: &mut i64,
    models: &mut HashSet<String>,
    bucket_tokens: &mut [i64],
    hourly: &mut [i64],
    model_tokens: &mut HashMap<String, i64>,
    project_tokens: &mut HashMap<PathBuf, i64>,
    topic_counts: &mut HashMap<String, i64>,
    prompt_count: &mut i64,
    recent: &mut Vec<PromptPreview>,
) {
    for line in text.lines() {
        if line.contains("\"usage\":{") {
            if let Some(caps) = CLAUDE_USAGE_RE.captures(line) {
                let li: i64 = caps[1].parse().unwrap_or(0);
                let lcc: i64 = caps[2].parse().unwrap_or(0);
                let lcr: i64 = caps[3].parse().unwrap_or(0);
                let lo: i64 = caps[4].parse().unwrap_or(0);
                let lc = lcc + lcr;
                let lt = li + lc + lo;
                *input_tokens += li;
                *cached_tokens += lc;
                *output_tokens += lo;

                let mut model: Option<String> = None;
                if let Some(mc) = CLAUDE_MODEL_RE.captures(line) {
                    let m = mc[1].to_string();
                    models.insert(m.clone());
                    model = Some(m);
                }

                let ts = CLAUDE_TS_RE
                    .captures(line)
                    .and_then(|c| parse_iso8601(&c[1]))
                    .unwrap_or(file_mtime);

                if let Some(m) = model {
                    *model_tokens.entry(m).or_insert(0) += lt;
                }
                if ts >= window_start && lt > 0 {
                    *project_tokens.entry(project_dir.to_path_buf()).or_insert(0) += lt;
                    if let Some(idx) = bucket_index(ts, boundaries) {
                        bucket_tokens[idx] += lt;
                    }
                    let h = ts.hour() as usize;
                    if h < 24 {
                        hourly[h] += lt;
                    }
                }
            }
        } else if line.contains("\"role\":\"user\"") && !line.contains("\"tool_use_id\"") {
            if let Some(caps) = CLAUDE_PROMPT_RE.captures(line) {
                let raw = &caps[1];
                let unesc = unescape_json(raw);
                let cleaned = unesc.trim();
                if cleaned.is_empty() {
                    continue;
                }
                let ts = CLAUDE_TS_RE
                    .captures(line)
                    .and_then(|c| parse_iso8601(&c[1]))
                    .unwrap_or_else(Local::now);
                if ts < window_start {
                    continue;
                }
                *prompt_count += 1;
                for kw in extract_keywords(cleaned) {
                    *topic_counts.entry(kw).or_insert(0) += 1;
                }
                let preview: String = cleaned.replace('\n', " ").chars().take(140).collect();
                recent.push(PromptPreview {
                    text: preview,
                    timestamp: ts.to_rfc3339(),
                    project: project_name.to_string(),
                });
            }
        }
    }
}

#[derive(Debug, Clone, Default)]
struct CodexTokenTotals {
    input_tokens: i64,
    cached_tokens: i64,
    output_tokens: i64,
}

impl CodexTokenTotals {
    fn total(&self) -> i64 {
        self.input_tokens + self.cached_tokens + self.output_tokens
    }
}

#[derive(Debug, Clone)]
struct CodexRateLimitSnapshot {
    observed_at: DateTime<Local>,
    primary_used_percent: Option<f64>,
    primary_window_minutes: Option<i64>,
    primary_resets_at: Option<String>,
    secondary_used_percent: Option<f64>,
    secondary_window_minutes: Option<i64>,
    secondary_resets_at: Option<String>,
    plan_type: Option<String>,
    credits: Option<f64>,
    rate_limit_reached_type: Option<String>,
}

#[derive(Debug, Clone)]
struct CodexPrompt {
    text: String,
    timestamp: DateTime<Local>,
}

fn value_as_i64(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_u64().and_then(|n| i64::try_from(n).ok()))
        .or_else(|| v.as_f64().map(|n| n as i64))
        .or_else(|| v.as_str().and_then(|s| s.parse::<i64>().ok()))
}

fn value_as_f64(v: &Value) -> Option<f64> {
    v.as_f64()
        .or_else(|| v.as_i64().map(|n| n as f64))
        .or_else(|| v.as_u64().map(|n| n as f64))
        .or_else(|| v.as_str().and_then(|s| s.parse::<f64>().ok()))
}

fn json_i64(v: &Value, pointer: &str) -> Option<i64> {
    v.pointer(pointer).and_then(value_as_i64)
}

fn json_f64(v: &Value, pointer: &str) -> Option<f64> {
    v.pointer(pointer).and_then(value_as_f64)
}

fn json_string(v: &Value, pointer: &str) -> Option<String> {
    v.pointer(pointer)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

fn json_timestamp(v: &Value) -> Option<DateTime<Local>> {
    json_string(v, "/timestamp").and_then(|s| parse_iso8601(&s))
}

fn json_timestamp_from(v: &Value, pointer: &str) -> Option<DateTime<Local>> {
    json_string(v, pointer).and_then(|s| parse_iso8601(&s))
}

fn value_as_reset_time(v: &Value) -> Option<String> {
    if let Some(secs) = value_as_i64(v) {
        return Utc
            .timestamp_opt(secs, 0)
            .single()
            .map(|d| d.with_timezone(&Local).to_rfc3339());
    }
    let s = v.as_str()?;
    parse_iso8601(s).map(|d| d.to_rfc3339())
}

fn json_reset_time(v: &Value, pointer: &str) -> Option<String> {
    v.pointer(pointer).and_then(value_as_reset_time)
}

fn codex_project_display_name(path: &Path) -> String {
    path.file_name()
        .and_then(|s| s.to_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .unwrap_or_else(|| path.to_string_lossy().to_string())
}

fn is_codex_token_count(value: &Value) -> bool {
    value.get("type").and_then(|v| v.as_str()) == Some("token_count")
        || value.pointer("/payload/type").and_then(|v| v.as_str()) == Some("token_count")
}

fn codex_total_usage_value(value: &Value) -> Option<&Value> {
    value
        .pointer("/payload/info/total_token_usage")
        .or_else(|| value.pointer("/payload/total_token_usage"))
        .or_else(|| value.pointer("/info/total_token_usage"))
        .or_else(|| value.pointer("/total_token_usage"))
}

fn has_codex_rate_limit_fields(value: &Value) -> bool {
    value.pointer("/primary").is_some()
        || value.pointer("/secondary").is_some()
        || json_f64(value, "/credits").is_some()
        || json_string(value, "/plan_type").is_some()
        || json_string(value, "/rate_limit_reached_type").is_some()
}

fn codex_rate_limits_value(value: &Value) -> Option<&Value> {
    [
        value.pointer("/payload/rate_limits"),
        value.pointer("/rate_limits"),
        value.get("payload"),
        Some(value),
    ]
    .into_iter()
    .flatten()
    .find(|candidate| has_codex_rate_limit_fields(candidate))
}

fn parse_codex_totals(value: &Value) -> Option<CodexTokenTotals> {
    let input = json_i64(value, "/input_tokens").unwrap_or(0);
    let cached = json_i64(value, "/cached_input_tokens")
        .or_else(|| json_i64(value, "/cache_read_input_tokens"))
        .or_else(|| json_i64(value, "/cached_tokens"))
        .unwrap_or(0);
    let output = json_i64(value, "/output_tokens").unwrap_or(0);
    let reported_total = json_i64(value, "/total_tokens");

    if input == 0 && cached == 0 && output == 0 && reported_total.unwrap_or(0) == 0 {
        return None;
    }

    // Codex/OpenAI reports cached tokens as a subset of input_tokens. Loom's
    // shared usage UI displays input + cached + output, so store non-cached
    // input here when total_tokens confirms that relationship.
    let normalized_input = if reported_total == Some(input + output) && cached <= input {
        input - cached
    } else {
        input
    };

    Some(CodexTokenTotals {
        input_tokens: normalized_input,
        cached_tokens: cached,
        output_tokens: output,
    })
}

fn parse_codex_rate_limit(
    value: &Value,
    observed_at: DateTime<Local>,
) -> Option<CodexRateLimitSnapshot> {
    if !has_codex_rate_limit_fields(value) {
        return None;
    }

    Some(CodexRateLimitSnapshot {
        observed_at,
        primary_used_percent: json_f64(value, "/primary/used_percent"),
        primary_window_minutes: json_i64(value, "/primary/window_minutes"),
        primary_resets_at: json_reset_time(value, "/primary/resets_at"),
        secondary_used_percent: json_f64(value, "/secondary/used_percent"),
        secondary_window_minutes: json_i64(value, "/secondary/window_minutes"),
        secondary_resets_at: json_reset_time(value, "/secondary/resets_at"),
        plan_type: json_string(value, "/plan_type"),
        credits: json_f64(value, "/credits"),
        rate_limit_reached_type: json_string(value, "/rate_limit_reached_type"),
    })
}

fn fill_codex_rate_limit_metadata(snapshot: &mut CodexRateLimitSnapshot, value: &Value) {
    if snapshot.plan_type.is_none() {
        snapshot.plan_type =
            json_string(value, "/payload/plan_type").or_else(|| json_string(value, "/plan_type"));
    }
    if snapshot.credits.is_none() {
        snapshot.credits =
            json_f64(value, "/payload/credits").or_else(|| json_f64(value, "/credits"));
    }
    if snapshot.rate_limit_reached_type.is_none() {
        snapshot.rate_limit_reached_type = json_string(value, "/payload/rate_limit_reached_type")
            .or_else(|| json_string(value, "/rate_limit_reached_type"));
    }
}

fn collect_codex_text(value: &Value, parts: &mut Vec<String>) {
    match value {
        Value::String(s) => {
            if !s.trim().is_empty() {
                parts.push(s.trim().to_string());
            }
        }
        Value::Array(items) => {
            for item in items {
                collect_codex_text(item, parts);
            }
        }
        Value::Object(map) => {
            if let Some(text) = map.get("text").and_then(|v| v.as_str()) {
                if !text.trim().is_empty() {
                    parts.push(text.trim().to_string());
                    return;
                }
            }
            if let Some(content) = map.get("content") {
                collect_codex_text(content, parts);
            }
        }
        _ => {}
    }
}

fn extract_codex_prompt(value: &Value) -> Option<String> {
    let payload = value.get("payload")?;
    let top_type = value.get("type").and_then(|v| v.as_str());
    let payload_type = payload.get("type").and_then(|v| v.as_str());

    if top_type == Some("event_msg") && payload_type == Some("user_message") {
        if let Some(message) = payload.get("message").and_then(|v| v.as_str()) {
            let cleaned = message.trim();
            if !cleaned.is_empty() {
                return Some(cleaned.to_string());
            }
        }
        if let Some(text_elements) = payload.get("text_elements") {
            let mut parts = Vec::new();
            collect_codex_text(text_elements, &mut parts);
            if !parts.is_empty() {
                return Some(parts.join("\n"));
            }
        }
    }

    if top_type == Some("response_item")
        && payload_type == Some("message")
        && payload.get("role").and_then(|v| v.as_str()) == Some("user")
    {
        let mut parts = Vec::new();
        if let Some(content) = payload.get("content") {
            collect_codex_text(content, &mut parts);
        }
        if !parts.is_empty() {
            return Some(parts.join("\n"));
        }
    }

    None
}

fn read_codex_usage(
    root: &Path,
    live_cutoff: DateTime<Local>,
    start_of_today: DateTime<Local>,
    boundaries: &[BucketBoundary],
    window_start: DateTime<Local>,
) -> CliToolUsage {
    if !root.exists() {
        return CliToolUsage::unavailable(CliTool::Codex);
    }
    let mut sessions_total: i64 = 0;
    let mut sessions_today: i64 = 0;
    let mut active_sessions: i64 = 0;
    let mut input_tokens: i64 = 0;
    let mut output_tokens: i64 = 0;
    let mut cached_tokens: i64 = 0;
    let mut last_activity: Option<DateTime<Local>> = None;
    let mut models: HashSet<String> = HashSet::new();

    let mut bucket_tokens: Vec<i64> = vec![0; boundaries.len()];
    let mut hourly: Vec<i64> = vec![0; 24];
    let mut model_tokens: HashMap<String, i64> = HashMap::new();
    let mut project_tokens: HashMap<PathBuf, i64> = HashMap::new();
    let mut project_sessions: HashMap<PathBuf, i64> = HashMap::new();
    let mut project_last: HashMap<PathBuf, DateTime<Local>> = HashMap::new();
    let mut topic_counts: HashMap<String, i64> = HashMap::new();
    let mut prompt_count: i64 = 0;
    let mut recent: Vec<PromptPreview> = Vec::new();
    let mut latest_rate_limit: Option<CodexRateLimitSnapshot> = None;

    walk_jsonl(root, &mut |path| {
        let Some(mtime) = file_mtime(path) else {
            return;
        };
        let Some(text) = read_text(path) else { return };

        let mut session_started_at: Option<DateTime<Local>> = None;
        let mut session_activity = mtime;
        let mut session_project: Option<PathBuf> = None;
        let mut session_model: Option<String> = None;
        let mut session_totals: Option<CodexTokenTotals> = None;
        let mut session_totals_at: Option<DateTime<Local>> = None;
        let mut session_prompts: Vec<CodexPrompt> = Vec::new();
        let mut seen_prompts: HashSet<String> = HashSet::new();

        for line in text.lines() {
            let Ok(value) = serde_json::from_str::<Value>(line) else {
                continue;
            };
            let ts = json_timestamp(&value).unwrap_or(mtime);
            if ts > session_activity {
                session_activity = ts;
            }

            if value.get("type").and_then(|v| v.as_str()) == Some("session_meta") {
                if let Some(meta_ts) = json_timestamp_from(&value, "/payload/timestamp")
                    .or_else(|| json_timestamp(&value))
                {
                    session_started_at = Some(meta_ts);
                }
                if let Some(cwd) = json_string(&value, "/payload/cwd") {
                    session_project = Some(PathBuf::from(cwd));
                }
            }

            if value.get("type").and_then(|v| v.as_str()) == Some("turn_context") {
                if session_project.is_none() {
                    if let Some(cwd) = json_string(&value, "/payload/cwd") {
                        session_project = Some(PathBuf::from(cwd));
                    }
                }
                if let Some(model) = json_string(&value, "/payload/model") {
                    models.insert(model.clone());
                    session_model = Some(model);
                }
            }

            if is_codex_token_count(&value) {
                if let Some(total_value) = codex_total_usage_value(&value) {
                    if let Some(totals) = parse_codex_totals(total_value) {
                        session_totals = Some(totals);
                        session_totals_at = Some(ts);
                    }
                }
                if let Some(rate_value) = codex_rate_limits_value(&value) {
                    if let Some(mut snapshot) = parse_codex_rate_limit(rate_value, ts) {
                        fill_codex_rate_limit_metadata(&mut snapshot, &value);
                        if latest_rate_limit
                            .as_ref()
                            .map_or(true, |current| snapshot.observed_at > current.observed_at)
                        {
                            latest_rate_limit = Some(snapshot);
                        }
                    }
                }
            }

            if let Some(prompt) = extract_codex_prompt(&value) {
                let cleaned = prompt.replace('\n', " ").trim().to_string();
                if cleaned.is_empty() {
                    continue;
                }
                let key = format!("{}|{}", ts.to_rfc3339(), cleaned);
                if seen_prompts.insert(key) {
                    session_prompts.push(CodexPrompt {
                        text: cleaned,
                        timestamp: ts,
                    });
                }
            }
        }

        sessions_total += 1;
        let session_started = session_started_at.unwrap_or(mtime);
        if session_started >= start_of_today {
            sessions_today += 1;
        }
        if mtime >= live_cutoff {
            active_sessions += 1;
        }
        if last_activity.map_or(true, |la| session_activity > la) {
            last_activity = Some(session_activity);
        }

        let project_path = session_project.unwrap_or_else(|| path.to_path_buf());
        if session_activity >= window_start {
            *project_sessions.entry(project_path.clone()).or_insert(0) += 1;
            project_last
                .entry(project_path.clone())
                .and_modify(|d| {
                    if session_activity > *d {
                        *d = session_activity;
                    }
                })
                .or_insert(session_activity);
        }

        let project_name = codex_project_display_name(&project_path);
        for prompt in session_prompts {
            if prompt.timestamp < window_start {
                continue;
            }
            prompt_count += 1;
            for kw in extract_keywords(&prompt.text) {
                *topic_counts.entry(kw).or_insert(0) += 1;
            }
            let preview: String = prompt.text.chars().take(140).collect();
            recent.push(PromptPreview {
                text: preview,
                timestamp: prompt.timestamp.to_rfc3339(),
                project: project_name.clone(),
            });
        }

        let Some(totals) = session_totals else { return };
        let total_tokens = totals.total();
        input_tokens += totals.input_tokens;
        cached_tokens += totals.cached_tokens;
        output_tokens += totals.output_tokens;

        if let Some(model) = session_model {
            *model_tokens.entry(model).or_insert(0) += total_tokens;
        }

        let token_ts = session_totals_at.unwrap_or(session_activity);
        if token_ts >= window_start && total_tokens > 0 {
            *project_tokens.entry(project_path).or_insert(0) += total_tokens;
            if let Some(idx) = bucket_index(token_ts, boundaries) {
                bucket_tokens[idx] += total_tokens;
            }
            let h = token_ts.hour() as usize;
            if h < 24 {
                hourly[h] += total_tokens;
            }
        }
    });

    let chart_buckets: Vec<UsageBucket> = boundaries
        .iter()
        .zip(bucket_tokens.iter())
        .map(|(b, t)| UsageBucket {
            start: b.start.to_rfc3339(),
            end: b.end.to_rfc3339(),
            tokens: *t,
            label: b.label.clone(),
        })
        .collect();

    let mut top_projects: Vec<ProjectUsage> = project_sessions
        .iter()
        .filter_map(|(p, sessions)| {
            let last = project_last.get(p)?;
            Some(ProjectUsage {
                display_name: codex_project_display_name(p),
                path: p.to_string_lossy().to_string(),
                sessions: *sessions,
                last_activity: last.to_rfc3339(),
            })
        })
        .collect();
    top_projects.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
    top_projects.truncate(5);

    let mut tokens_by_model: Vec<ModelUsage> = model_tokens
        .into_iter()
        .map(|(model, tokens)| ModelUsage { model, tokens })
        .collect();
    tokens_by_model.sort_by(|a, b| b.tokens.cmp(&a.tokens));

    let mut tokens_by_project: Vec<ProjectTokenSlice> = project_tokens
        .into_iter()
        .map(|(p, tokens)| ProjectTokenSlice {
            display_name: codex_project_display_name(&p),
            path: p.to_string_lossy().to_string(),
            tokens,
        })
        .collect();
    tokens_by_project.sort_by(|a, b| b.tokens.cmp(&a.tokens));

    let mut top_topics: Vec<PromptTopic> = topic_counts
        .into_iter()
        .filter(|(_, c)| *c >= 2)
        .map(|(keyword, count)| PromptTopic { keyword, count })
        .collect();
    top_topics.sort_by(|a, b| b.count.cmp(&a.count));
    top_topics.truncate(12);

    recent.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    recent.truncate(8);

    let mut models_sorted: Vec<String> = models.into_iter().collect();
    models_sorted.sort();

    let (
        rate_limit_primary_used_percent,
        rate_limit_primary_window_minutes,
        rate_limit_primary_resets_at,
        rate_limit_secondary_used_percent,
        rate_limit_secondary_window_minutes,
        rate_limit_secondary_resets_at,
        plan_type,
        credits,
        rate_limit_reached_type,
        rate_limit_observed_at,
    ) = if let Some(snapshot) = latest_rate_limit {
        (
            snapshot.primary_used_percent,
            snapshot.primary_window_minutes,
            snapshot.primary_resets_at,
            snapshot.secondary_used_percent,
            snapshot.secondary_window_minutes,
            snapshot.secondary_resets_at,
            snapshot.plan_type,
            snapshot.credits,
            snapshot.rate_limit_reached_type,
            Some(snapshot.observed_at.to_rfc3339()),
        )
    } else {
        (None, None, None, None, None, None, None, None, None, None)
    };

    CliToolUsage {
        tool: CliTool::Codex.as_str().to_string(),
        is_installed: true,
        active_sessions,
        sessions_today,
        sessions_total,
        input_tokens,
        output_tokens,
        cached_tokens,
        last_activity: last_activity.map(|d| d.to_rfc3339()),
        models: models_sorted,
        chart_buckets,
        top_projects,
        tokens_by_model,
        tokens_by_project,
        top_topics,
        recent_prompts: recent,
        hourly_distribution: hourly,
        prompt_count,
        rate_limit_primary_used_percent,
        rate_limit_primary_window_minutes,
        rate_limit_primary_resets_at,
        rate_limit_secondary_used_percent,
        rate_limit_secondary_window_minutes,
        rate_limit_secondary_resets_at,
        plan_type,
        credits,
        rate_limit_reached_type,
        rate_limit_observed_at,
    }
}

fn walk_jsonl(root: &Path, visit: &mut dyn FnMut(&Path)) {
    let Ok(entries) = fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            walk_jsonl(&path, visit);
        } else if path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
            visit(&path);
        }
    }
}

fn read_lmstudio_usage(
    root: &Path,
    live_cutoff: DateTime<Local>,
    start_of_today: DateTime<Local>,
    boundaries: &[BucketBoundary],
    window_start: DateTime<Local>,
) -> CliToolUsage {
    let mut sessions_total: i64 = 0;
    let mut sessions_today: i64 = 0;
    let mut active_sessions: i64 = 0;
    let mut input_tokens: i64 = 0;
    let mut output_tokens: i64 = 0;
    let mut last_activity: Option<DateTime<Local>> = None;
    let mut models: HashSet<String> = HashSet::new();
    let mut buckets = vec![0_i64; boundaries.len()];
    let mut hourly = vec![0_i64; 24];
    let mut model_tokens: HashMap<String, i64> = HashMap::new();
    let mut project_tokens: HashMap<String, i64> = HashMap::new();
    let mut project_names: HashMap<String, String> = HashMap::new();
    let mut project_sessions: HashMap<String, i64> = HashMap::new();
    let mut project_last: HashMap<String, DateTime<Local>> = HashMap::new();
    let mut topics: HashMap<String, i64> = HashMap::new();
    let mut recent_prompts: Vec<PromptPreview> = Vec::new();
    let mut prompt_count: i64 = 0;

    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) != Some("json") {
                continue;
            }
            let Some(text) = read_text(&path) else { continue };
            let Ok(value) = serde_json::from_str::<Value>(&text) else {
                continue;
            };
            let summary = value.get("summary").unwrap_or(&Value::Null);
            let messages = value
                .get("messages")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            let updated_at = summary
                .get("updatedAt")
                .and_then(apple_date_from_value)
                .or_else(|| file_mtime(&path))
                .unwrap_or_else(Local::now);
            let workspace_key = summary
                .get("workspaceKey")
                .and_then(Value::as_str)
                .unwrap_or("global")
                .to_string();
            let workspace_name = summary
                .get("workspaceName")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| friendly_project_name(&workspace_key));
            let model = summary
                .get("modelLabel")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
                .unwrap_or("LM Studio")
                .to_string();

            sessions_total += 1;
            if updated_at >= start_of_today {
                sessions_today += 1;
            }
            if updated_at >= live_cutoff {
                active_sessions += 1;
            }
            if last_activity.map(|d| updated_at > d).unwrap_or(true) {
                last_activity = Some(updated_at);
            }

            models.insert(model.clone());
            project_names.insert(workspace_key.clone(), workspace_name.clone());
            if updated_at >= window_start {
                *project_sessions.entry(workspace_key.clone()).or_default() += 1;
                project_last
                    .entry(workspace_key.clone())
                    .and_modify(|prev| {
                        if updated_at > *prev {
                            *prev = updated_at;
                        }
                    })
                    .or_insert(updated_at);
            }

            let mut session_tokens: i64 = 0;
            for message in messages {
                let role = message
                    .get("role")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_ascii_lowercase();
                let body = message.get("text").and_then(Value::as_str).unwrap_or("");
                let tokens = estimate_tokens(body);
                if tokens <= 0 {
                    continue;
                }
                session_tokens += tokens;
                if role == "user" {
                    input_tokens += tokens;
                } else if role == "assistant" {
                    output_tokens += tokens;
                }
                let ts = message
                    .get("createdAt")
                    .and_then(apple_date_from_value)
                    .unwrap_or(updated_at);
                if ts >= window_start {
                    if let Some(idx) = bucket_index(ts, boundaries) {
                        buckets[idx] += tokens;
                    }
                    let hour = ts.hour() as usize;
                    if hour < hourly.len() {
                        hourly[hour] += tokens;
                    }
                    if role == "user" {
                        prompt_count += 1;
                        for word in extract_keywords(body) {
                            *topics.entry(word).or_default() += 1;
                        }
                        recent_prompts.push(PromptPreview {
                            text: body.replace('\n', " ").chars().take(140).collect(),
                            timestamp: ts.to_rfc3339(),
                            project: workspace_name.clone(),
                        });
                    }
                }
            }

            if updated_at >= window_start {
                *model_tokens.entry(model).or_default() += session_tokens;
                *project_tokens.entry(workspace_key).or_default() += session_tokens;
            }
        }
    }

    let chart_buckets: Vec<UsageBucket> = boundaries
        .iter()
        .zip(buckets)
        .map(|(b, t)| UsageBucket {
            start: b.start.to_rfc3339(),
            end: b.end.to_rfc3339(),
            tokens: t,
            label: b.label.clone(),
        })
        .collect();
    let mut top_projects: Vec<ProjectUsage> = project_sessions
        .into_iter()
        .filter_map(|(path, sessions)| {
            let last = project_last.get(&path)?;
            Some(ProjectUsage {
                display_name: project_names
                    .get(&path)
                    .cloned()
                    .unwrap_or_else(|| friendly_project_name(&path)),
                path,
                sessions,
                last_activity: last.to_rfc3339(),
            })
        })
        .collect();
    top_projects.sort_by(|a, b| b.last_activity.cmp(&a.last_activity));
    top_projects.truncate(5);

    let mut tokens_by_model: Vec<ModelUsage> = model_tokens
        .into_iter()
        .map(|(model, tokens)| ModelUsage { model, tokens })
        .collect();
    tokens_by_model.sort_by(|a, b| b.tokens.cmp(&a.tokens));

    let mut tokens_by_project: Vec<ProjectTokenSlice> = project_tokens
        .into_iter()
        .map(|(path, tokens)| ProjectTokenSlice {
            display_name: project_names
                .get(&path)
                .cloned()
                .unwrap_or_else(|| friendly_project_name(&path)),
            path,
            tokens,
        })
        .collect();
    tokens_by_project.sort_by(|a, b| b.tokens.cmp(&a.tokens));

    let mut top_topics: Vec<PromptTopic> = topics
        .into_iter()
        .filter(|(_, count)| *count >= 2)
        .map(|(keyword, count)| PromptTopic { keyword, count })
        .collect();
    top_topics.sort_by(|a, b| b.count.cmp(&a.count));
    top_topics.truncate(12);
    recent_prompts.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    recent_prompts.truncate(8);
    let mut models_sorted: Vec<String> = models.into_iter().collect();
    models_sorted.sort();

    CliToolUsage {
        tool: CliTool::LmStudio.as_str().to_string(),
        is_installed: true,
        active_sessions,
        sessions_today,
        sessions_total,
        input_tokens,
        output_tokens,
        cached_tokens: 0,
        last_activity: last_activity.map(|d| d.to_rfc3339()),
        models: models_sorted,
        chart_buckets,
        top_projects,
        tokens_by_model,
        tokens_by_project,
        top_topics,
        recent_prompts,
        hourly_distribution: hourly,
        prompt_count,
        rate_limit_primary_used_percent: None,
        rate_limit_primary_window_minutes: None,
        rate_limit_primary_resets_at: None,
        rate_limit_secondary_used_percent: None,
        rate_limit_secondary_window_minutes: None,
        rate_limit_secondary_resets_at: None,
        plan_type: None,
        credits: None,
        rate_limit_reached_type: None,
        rate_limit_observed_at: None,
    }
}

fn apple_date_from_value(value: &Value) -> Option<DateTime<Local>> {
    if let Some(seconds) = value.as_f64() {
        let unix_seconds = 978_307_200_f64 + seconds;
        let whole = unix_seconds.trunc() as i64;
        let nanos = ((unix_seconds.fract().abs()) * 1_000_000_000.0) as u32;
        return Utc.timestamp_opt(whole, nanos).single().map(|d| d.with_timezone(&Local));
    }
    value.as_str().and_then(parse_iso8601)
}

fn estimate_tokens(text: &str) -> i64 {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return 0;
    }
    ((trimmed.chars().count() as f64) / 4.0).ceil().max(1.0) as i64
}

fn home() -> PathBuf {
    dirs::home_dir().unwrap_or_else(|| PathBuf::from("."))
}

#[tauri::command]
pub fn usage_read(tool: String, timeframe: String) -> Result<CliToolUsage, String> {
    let tool = CliTool::from_str(&tool).ok_or_else(|| format!("unknown tool: {tool}"))?;
    let tf = Timeframe::from_str(&timeframe);
    let now = Local::now();
    let live_cutoff = now - Duration::minutes(5);
    let start_of_today_naive = now.date_naive().and_hms_opt(0, 0, 0).unwrap();
    let start_of_today = Local
        .from_local_datetime(&start_of_today_naive)
        .single()
        .unwrap_or(now);
    let window_start = now - tf.span();
    let boundaries = tf.boundaries(now);

    let h = home();
    Ok(match tool {
        CliTool::Claude => {
            let root = h.join(".claude").join("projects");
            read_claude_usage(
                &root,
                live_cutoff,
                start_of_today,
                &boundaries,
                window_start,
            )
        }
        CliTool::Codex => {
            let root = h.join(".codex").join("sessions");
            read_codex_usage(
                &root,
                live_cutoff,
                start_of_today,
                &boundaries,
                window_start,
            )
        }
        CliTool::LmStudio => {
            let root = dirs::data_dir()
                .unwrap_or_else(|| h.join("AppData").join("Roaming"))
                .join("Loom Testing Edition")
                .join("lmstudio-agent-sessions");
            read_lmstudio_usage(
                &root,
                live_cutoff,
                start_of_today,
                &boundaries,
                window_start,
            )
        }
    })
}
