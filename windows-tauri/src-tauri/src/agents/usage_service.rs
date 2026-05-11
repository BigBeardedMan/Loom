// Mirrors Loom/Agents/UsageService.swift.
// Reads on-disk usage data from local CLI agents (Claude Code, Codex, Gemini)
// and aggregates token totals, sessions, models, projects, prompts.

use chrono::{DateTime, Datelike, Duration, Local, TimeZone, Timelike, Utc};
use once_cell::sync::Lazy;
use regex::Regex;
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CliTool {
    Claude,
    Codex,
    Gemini,
}

impl CliTool {
    fn from_str(s: &str) -> Option<Self> {
        match s {
            "claude" => Some(Self::Claude),
            "codex" => Some(Self::Codex),
            "gemini" => Some(Self::Gemini),
            _ => None,
        }
    }
    fn as_str(self) -> &'static str {
        match self {
            Self::Claude => "claude",
            Self::Codex => "codex",
            Self::Gemini => "gemini",
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
                    let start = Local.from_local_datetime(&start_naive).single().unwrap_or(now);
                    let (ny, nm) = if m == 12 { (y + 1, 1) } else { (y, m + 1) };
                    let end_naive = chrono::NaiveDate::from_ymd_opt(ny, nm as u32, 1)
                        .unwrap()
                        .and_hms_opt(0, 0, 0)
                        .unwrap();
                    let end = Local.from_local_datetime(&end_naive).single().unwrap_or(now);
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
        }
    }
}

// Stopwords copied verbatim from Loom/Agents/UsageService.swift lines 878-895.
static STOPWORDS: Lazy<HashSet<&'static str>> = Lazy::new(|| {
    [
        "this", "that", "with", "have", "from", "your", "into", "about", "where", "when", "what",
        "would", "could", "should", "there", "their", "they", "them", "then", "than", "also",
        "just", "like", "want", "need", "make", "made", "more", "some", "very", "well", "going",
        "still", "thing", "things", "really", "think", "back", "down", "much", "many", "most",
        "good", "right", "wrong", "okay", "sure", "yeah", "actually", "claude", "code", "please",
        "thanks", "thank", "hello", "look", "looks", "show", "shows", "let", "let's", "doesn",
        "didn", "won", "haven", "isn", "aren", "wasn", "weren", "the", "and", "but", "for", "are",
        "was", "were", "been", "being", "does", "did", "use", "used", "uses", "using", "get",
        "got", "see", "saw", "seen", "way", "out", "off", "now", "yes", "say", "said", "tell",
        "told", "give", "given", "currently", "current", "needs", "needed", "must", "might",
        "since", "before", "after", "while",
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

static CODEX_TOTALS_RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r#""total_token_usage":\{"input_tokens":(\d+),"cached_input_tokens":(\d+),"output_tokens":(\d+)"#).unwrap()
});

static CODEX_MODEL_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r#""model":"([^"]+)""#).unwrap());

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
    let tail = segments.iter().rev().take(2).rev().copied().collect::<Vec<_>>();
    tail.join("/")
}

fn extract_keywords(text: &str) -> Vec<String> {
    let lowered = text.to_lowercase();
    let mut seen: HashSet<String> = HashSet::new();
    let mut out: Vec<String> = Vec::new();
    let mut current = String::new();
    let mut push = |cur: &mut String, seen: &mut HashSet<String>, out: &mut Vec<String>| {
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
    Some(
        Utc.timestamp_opt(secs, 0)
            .single()?
            .with_timezone(&Local),
    )
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
            let Some(mtime) = file_mtime(&path) else { continue };
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

            let Some(text) = read_text(&path) else { continue };
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

fn read_codex_usage(
    root: &Path,
    live_cutoff: DateTime<Local>,
    start_of_today: DateTime<Local>,
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

    walk_jsonl(root, &mut |path| {
        let Some(mtime) = file_mtime(path) else { return };
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
        if let Some(text) = read_text(path) {
            let mut last_i: i64 = 0;
            let mut last_c: i64 = 0;
            let mut last_o: i64 = 0;
            for caps in CODEX_TOTALS_RE.captures_iter(&text) {
                last_i = caps[1].parse().unwrap_or(0);
                last_c = caps[2].parse().unwrap_or(0);
                last_o = caps[3].parse().unwrap_or(0);
            }
            input_tokens += last_i;
            cached_tokens += last_c;
            output_tokens += last_o;
            if let Some(mc) = CODEX_MODEL_RE.captures(&text) {
                models.insert(mc[1].to_string());
            }
        }
    });

    let mut models_sorted: Vec<String> = models.into_iter().collect();
    models_sorted.sort();

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
        chart_buckets: vec![],
        top_projects: vec![],
        tokens_by_model: vec![],
        tokens_by_project: vec![],
        top_topics: vec![],
        recent_prompts: vec![],
        hourly_distribution: vec![0; 24],
        prompt_count: 0,
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

fn read_gemini_usage(root: &Path) -> CliToolUsage {
    let mut u = CliToolUsage::unavailable(CliTool::Gemini);
    u.is_installed = root.exists();
    u
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
            read_claude_usage(&root, live_cutoff, start_of_today, &boundaries, window_start)
        }
        CliTool::Codex => {
            let root = h.join(".codex").join("sessions");
            read_codex_usage(&root, live_cutoff, start_of_today)
        }
        CliTool::Gemini => {
            let root = h.join(".gemini");
            read_gemini_usage(&root)
        }
    })
}
