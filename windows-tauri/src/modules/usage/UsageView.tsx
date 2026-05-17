import { useMemo } from "react";
import { Icons } from "../../lib/icons";
import {
  useUsage,
  toolLabel,
  toolBrandColor,
  timeframeLabel,
  timeframeHeadline,
  type Tool,
  type Timeframe,
} from "../../lib/usage";
import { useApp } from "../../lib/store";

const TIMEFRAMES: Timeframe[] = ["day", "week", "month", "year"];

type Props = { tool: Tool };
type UsageData = NonNullable<ReturnType<typeof useUsage>["data"]>;

export function UsageView({ tool }: Props) {
  const timeframe = useApp((s) => s.usageTimeframe);
  const setTimeframe = useApp((s) => s.setUsageTimeframe);
  const { data, loading, error, refresh } = useUsage(tool, timeframe);

  const brand = toolBrandColor(tool);

  return (
    <div
      className="flex h-full w-full flex-col overflow-hidden"
      style={{ background: "var(--color-loom-cockpit)", color: "var(--color-loom-text)" }}
    >
      <header
        className="flex items-center gap-3 flex-none"
        style={{
          padding: "12px 18px",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
          background: "rgba(0,0,0,0.18)",
        }}
      >
        <div
          className="flex items-center justify-center rounded-md"
          style={{ width: 26, height: 26, background: brand, color: "white" }}
        >
          <Icons.sparkles size={14} strokeWidth={2.2} />
        </div>
        <div className="flex flex-col leading-tight">
          <span style={{ fontSize: 13, fontWeight: 600 }}>{toolLabel(tool)}</span>
          <span style={{ fontSize: 11, color: "rgba(255,255,255,0.5)" }}>
            {timeframeHeadline(timeframe)}
            {data?.lastActivity && ` · last activity ${shortAgo(data.lastActivity)}`}
          </span>
        </div>
        <div className="ml-auto flex items-center gap-1">
          {TIMEFRAMES.map((tf) => (
            <button
              key={tf}
              onClick={() => setTimeframe(tf)}
              style={{
                padding: "4px 10px",
                fontSize: 11,
                fontWeight: 500,
                borderRadius: 6,
                border: "1px solid rgba(255,255,255,0.10)",
                background: tf === timeframe ? brand : "rgba(255,255,255,0.05)",
                color: tf === timeframe ? "white" : "rgba(255,255,255,0.7)",
              }}
            >
              {timeframeLabel(tf)}
            </button>
          ))}
          <button
            onClick={refresh}
            aria-label="Refresh"
            style={{
              marginLeft: 4,
              padding: 6,
              borderRadius: 6,
              border: "1px solid rgba(255,255,255,0.10)",
              background: "rgba(255,255,255,0.05)",
              color: "rgba(255,255,255,0.7)",
            }}
          >
            {loading ? (
              <Icons.spinner size={14} className="animate-spin" />
            ) : (
              <Icons.refresh size={14} strokeWidth={2} />
            )}
          </button>
        </div>
      </header>

      <div className="scrollbar-thin flex-1 overflow-y-auto" style={{ padding: 18 }}>
        {error && (
          <div
            style={{
              padding: "10px 12px",
              marginBottom: 12,
              background: "rgba(242,70,32,0.15)",
              border: "1px solid rgba(242,70,32,0.4)",
              borderRadius: 8,
              fontSize: 12,
              color: "rgba(255,160,140,0.9)",
            }}
          >
            {error}
          </div>
        )}

        {data && !data.isInstalled && (
          <EmptyState
            title={`${toolLabel(tool)} not detected`}
            body="No on-disk session logs yet. Start a CLI session and check back."
          />
        )}

        {data && data.isInstalled && (
          <>
            <StatGrid data={data} />
            {tool === "codex" && hasCodexLimitData(data) && (
              <CodexLimits data={data} brand={brand} />
            )}
            {data.chartBuckets.length > 0 && (
              <Section title="Activity">
                <BucketBars buckets={data.chartBuckets} brand={brand} />
              </Section>
            )}
            <DonutsRow data={data} brand={brand} />
            <HourlyHeatmap hours={data.hourlyDistribution} brand={brand} />
            <PromptsAndTopics data={data} />
            <ProjectsList data={data} />
          </>
        )}
      </div>
    </div>
  );
}

function StatGrid({ data }: { data: UsageData }) {
  const stats: Array<[string, string]> = [
    ["Sessions today", String(data.sessionsToday)],
    ["Sessions total", String(data.sessionsTotal)],
    ["Total tokens", fmt(data.inputTokens + data.outputTokens + data.cachedTokens)],
    ["Input", fmt(data.inputTokens)],
    ["Output", fmt(data.outputTokens)],
    ["Cached", fmt(data.cachedTokens)],
  ];
  return (
    <div className="grid grid-cols-3 gap-3" style={{ marginBottom: 18 }}>
      {stats.map(([label, value]) => (
        <div
          key={label}
          style={{
            padding: 12,
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(255,255,255,0.06)",
            borderRadius: 10,
          }}
        >
          <div style={{ fontSize: 10, color: "rgba(255,255,255,0.45)", letterSpacing: 0.6, textTransform: "uppercase" }}>
            {label}
          </div>
          <div style={{ fontSize: 20, fontWeight: 600, marginTop: 4, fontFamily: "var(--font-mono)" }}>
            {value}
          </div>
        </div>
      ))}
    </div>
  );
}

function hasCodexLimitData(data: UsageData): boolean {
  return (
    data.rateLimitObservedAt != null ||
    data.rateLimitPrimaryUsedPercent != null ||
    data.rateLimitPrimaryWindowMinutes != null ||
    data.rateLimitPrimaryResetsAt != null ||
    data.rateLimitSecondaryUsedPercent != null ||
    data.rateLimitSecondaryWindowMinutes != null ||
    data.rateLimitSecondaryResetsAt != null ||
    data.planType != null ||
    data.credits != null ||
    data.rateLimitReachedType != null
  );
}

function CodexLimits({ data, brand }: { data: UsageData; brand: string }) {
  const rows = [
    {
      label: "Primary",
      used: data.rateLimitPrimaryUsedPercent,
      window: data.rateLimitPrimaryWindowMinutes,
      resetsAt: data.rateLimitPrimaryResetsAt,
    },
    {
      label: "Secondary",
      used: data.rateLimitSecondaryUsedPercent,
      window: data.rateLimitSecondaryWindowMinutes,
      resetsAt: data.rateLimitSecondaryResetsAt,
    },
  ].filter((row) => row.used != null || row.window != null || row.resetsAt != null);

  return (
    <Section title="Codex limits">
      <div
        style={{
          padding: 12,
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 10,
        }}
      >
        <div className="flex items-center gap-2" style={{ marginBottom: 10 }}>
          <span style={{ fontSize: 11, color: "rgba(255,255,255,0.55)" }}>
            reported by latest local Codex session
          </span>
          {data.planType && (
            <span
              style={{
                marginLeft: "auto",
                fontSize: 10,
                padding: "2px 7px",
                borderRadius: 999,
                background: "rgba(255,255,255,0.07)",
                color: "rgba(255,255,255,0.72)",
                textTransform: "uppercase",
              }}
            >
              {data.planType}
            </span>
          )}
        </div>
        {rows.length > 0 && (
          <div className="grid grid-cols-2 gap-3">
            {rows.map((row) => (
              <LimitMeter key={row.label} {...row} brand={brand} />
            ))}
          </div>
        )}
        <div
          className="flex flex-wrap items-center gap-x-4 gap-y-1"
          style={{ marginTop: 10, fontSize: 11, color: "rgba(255,255,255,0.5)" }}
        >
          <span>
            {data.credits == null
              ? "credit balance unavailable"
              : `Credit balance ${fmtCredits(data.credits)}`}
          </span>
          {data.rateLimitObservedAt && <span>Observed {shortDateTime(data.rateLimitObservedAt)}</span>}
          {data.rateLimitReachedType && <span>Reached {data.rateLimitReachedType}</span>}
        </div>
      </div>
    </Section>
  );
}

function LimitMeter({
  label,
  used,
  window,
  resetsAt,
  brand,
}: {
  label: string;
  used?: number | null;
  window?: number | null;
  resetsAt?: string | null;
  brand: string;
}) {
  const width = used == null ? 0 : Math.max(0, Math.min(100, used));
  return (
    <div style={{ minWidth: 0 }}>
      <div className="flex items-center gap-2">
        <span style={{ fontSize: 11, color: "rgba(255,255,255,0.75)", fontWeight: 600 }}>
          {label}
        </span>
        <span style={{ marginLeft: "auto", fontSize: 11, color: "rgba(255,255,255,0.55)", fontFamily: "var(--font-mono)" }}>
          {used == null ? "Unknown" : fmtPercent(used)}
        </span>
      </div>
      <div
        style={{
          height: 5,
          marginTop: 6,
          borderRadius: 999,
          background: "rgba(255,255,255,0.08)",
          overflow: "hidden",
        }}
      >
        <div style={{ width: `${width}%`, height: "100%", background: brand }} />
      </div>
      <div
        className="flex items-center gap-2"
        style={{ marginTop: 5, fontSize: 10, color: "rgba(255,255,255,0.42)" }}
      >
        <span>{window == null ? "Window unknown" : formatWindow(window)}</span>
        {resetsAt && <span style={{ marginLeft: "auto" }}>resets {shortDateTime(resetsAt)}</span>}
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section style={{ marginBottom: 18 }}>
      <h2
        style={{
          fontSize: 11,
          fontWeight: 600,
          letterSpacing: 0.6,
          textTransform: "uppercase",
          color: "rgba(255,255,255,0.55)",
          marginBottom: 8,
        }}
      >
        {title}
      </h2>
      {children}
    </section>
  );
}

function BucketBars({
  buckets,
  brand,
}: {
  buckets: { label: string; tokens: number }[];
  brand: string;
}) {
  const max = Math.max(1, ...buckets.map((b) => b.tokens));
  return (
    <div
      className="flex items-end gap-1"
      style={{
        height: 96,
        padding: 10,
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.06)",
        borderRadius: 10,
      }}
    >
      {buckets.map((b, i) => {
        const h = Math.max(2, (b.tokens / max) * 70);
        return (
          <div key={i} className="flex flex-1 flex-col items-center" style={{ minWidth: 0 }}>
            <div
              title={`${b.label} · ${fmt(b.tokens)}`}
              style={{
                width: "70%",
                height: h,
                background: brand,
                opacity: b.tokens === 0 ? 0.18 : 0.85,
                borderRadius: 3,
              }}
            />
            <span
              style={{
                fontSize: 9,
                marginTop: 4,
                color: "rgba(255,255,255,0.4)",
                whiteSpace: "nowrap",
              }}
            >
              {b.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function DonutsRow({
  data,
  brand,
}: {
  data: UsageData;
  brand: string;
}) {
  const tokenMix = [
    { label: "Input", value: data.inputTokens, color: brand },
    { label: "Output", value: data.outputTokens, color: "rgba(255,255,255,0.6)" },
    { label: "Cached", value: data.cachedTokens, color: "rgba(255,255,255,0.25)" },
  ];
  return (
    <div className="grid grid-cols-3 gap-3" style={{ marginBottom: 18 }}>
      <DonutCard title="Token mix" slices={tokenMix} />
      <DonutCard
        title="Models"
        slices={data.tokensByModel.slice(0, 6).map((m, i) => ({
          label: shortModel(m.model),
          value: m.tokens,
          color: palette(i),
        }))}
      />
      <DonutCard
        title="Projects"
        slices={data.tokensByProject.slice(0, 6).map((p, i) => ({
          label: p.displayName,
          value: p.tokens,
          color: palette(i),
        }))}
      />
    </div>
  );
}

function DonutCard({
  title,
  slices,
}: {
  title: string;
  slices: { label: string; value: number; color: string }[];
}) {
  const total = useMemo(() => slices.reduce((s, x) => s + x.value, 0), [slices]);
  const arcs = useMemo(() => {
    if (total <= 0) return [];
    let acc = 0;
    return slices.map((s) => {
      const start = acc / total;
      acc += s.value;
      const end = acc / total;
      return { ...s, start, end };
    });
  }, [slices, total]);
  return (
    <div
      style={{
        padding: 12,
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(255,255,255,0.06)",
        borderRadius: 10,
      }}
    >
      <div style={{ fontSize: 10, color: "rgba(255,255,255,0.45)", letterSpacing: 0.6, textTransform: "uppercase" }}>
        {title}
      </div>
      <div className="flex items-center gap-3" style={{ marginTop: 8 }}>
        <svg width={72} height={72} viewBox="0 0 72 72">
          <circle cx={36} cy={36} r={28} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth={10} />
          {arcs.map((a, i) => (
            <ArcPath key={i} start={a.start} end={a.end} color={a.color} />
          ))}
        </svg>
        <div className="flex flex-1 flex-col gap-1" style={{ minWidth: 0 }}>
          {slices.length === 0 && (
            <span style={{ fontSize: 11, color: "rgba(255,255,255,0.4)" }}>No data</span>
          )}
          {slices.slice(0, 4).map((s) => (
            <div key={s.label} className="flex items-center gap-2" style={{ minWidth: 0 }}>
              <span
                style={{ width: 8, height: 8, borderRadius: 2, background: s.color, flex: "none" }}
              />
              <span
                style={{
                  fontSize: 11,
                  color: "rgba(255,255,255,0.7)",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                  flex: 1,
                }}
              >
                {s.label}
              </span>
              <span style={{ fontSize: 10, color: "rgba(255,255,255,0.45)", fontFamily: "var(--font-mono)" }}>
                {fmt(s.value)}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function ArcPath({ start, end, color }: { start: number; end: number; color: string }) {
  const r = 28;
  const cx = 36;
  const cy = 36;
  const a0 = start * Math.PI * 2 - Math.PI / 2;
  const a1 = end * Math.PI * 2 - Math.PI / 2;
  const x0 = cx + r * Math.cos(a0);
  const y0 = cy + r * Math.sin(a0);
  const x1 = cx + r * Math.cos(a1);
  const y1 = cy + r * Math.sin(a1);
  const large = end - start > 0.5 ? 1 : 0;
  if (end - start < 0.001) return null;
  return (
    <path
      d={`M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1}`}
      stroke={color}
      strokeWidth={10}
      fill="none"
    />
  );
}

function HourlyHeatmap({ hours, brand }: { hours: number[]; brand: string }) {
  const max = Math.max(1, ...hours);
  return (
    <Section title="Hour-of-day">
      <div
        className="flex items-end gap-1"
        style={{
          height: 64,
          padding: 10,
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 10,
        }}
      >
        {hours.map((v, h) => {
          const intensity = v / max;
          return (
            <div key={h} className="flex flex-1 flex-col items-center" style={{ minWidth: 0 }}>
              <div
                title={`${pad2(h)}:00 · ${fmt(v)}`}
                style={{
                  width: "70%",
                  height: Math.max(2, intensity * 40),
                  background: brand,
                  opacity: 0.15 + intensity * 0.8,
                  borderRadius: 2,
                }}
              />
              <span
                style={{
                  fontSize: 8,
                  marginTop: 3,
                  color: "rgba(255,255,255,0.32)",
                }}
              >
                {h % 6 === 0 ? pad2(h) : ""}
              </span>
            </div>
          );
        })}
      </div>
    </Section>
  );
}

function PromptsAndTopics({ data }: { data: UsageData }) {
  if (data.recentPrompts.length === 0 && data.topTopics.length === 0) return null;
  return (
    <div className="grid grid-cols-2 gap-3" style={{ marginBottom: 18 }}>
      <div
        style={{
          padding: 12,
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 10,
        }}
      >
        <div style={{ fontSize: 10, color: "rgba(255,255,255,0.45)", letterSpacing: 0.6, textTransform: "uppercase" }}>
          Recent prompts ({data.promptCount})
        </div>
        <ul style={{ marginTop: 8, display: "flex", flexDirection: "column", gap: 6 }}>
          {data.recentPrompts.map((p, i) => (
            <li key={i} style={{ fontSize: 11, color: "rgba(255,255,255,0.78)" }}>
              <span style={{ color: "rgba(255,255,255,0.4)" }}>{shortAgo(p.timestamp)} </span>
              <span>{p.text}</span>
            </li>
          ))}
          {data.recentPrompts.length === 0 && (
            <li style={{ fontSize: 11, color: "rgba(255,255,255,0.4)" }}>None in this window.</li>
          )}
        </ul>
      </div>
      <div
        style={{
          padding: 12,
          background: "rgba(255,255,255,0.04)",
          border: "1px solid rgba(255,255,255,0.06)",
          borderRadius: 10,
        }}
      >
        <div style={{ fontSize: 10, color: "rgba(255,255,255,0.45)", letterSpacing: 0.6, textTransform: "uppercase" }}>
          Top topics
        </div>
        <div
          className="flex flex-wrap gap-2"
          style={{ marginTop: 8 }}
        >
          {data.topTopics.map((t) => (
            <span
              key={t.keyword}
              style={{
                fontSize: 11,
                padding: "2px 8px",
                borderRadius: 999,
                background: "rgba(255,255,255,0.06)",
                color: "rgba(255,255,255,0.78)",
              }}
            >
              {t.keyword}
              <span style={{ marginLeft: 6, color: "rgba(255,255,255,0.4)" }}>{t.count}</span>
            </span>
          ))}
          {data.topTopics.length === 0 && (
            <span style={{ fontSize: 11, color: "rgba(255,255,255,0.4)" }}>None.</span>
          )}
        </div>
      </div>
    </div>
  );
}

function ProjectsList({ data }: { data: UsageData }) {
  if (data.topProjects.length === 0) return null;
  return (
    <Section title="Top projects">
      <div className="flex flex-col gap-1">
        {data.topProjects.map((p) => (
          <div
            key={p.path}
            className="flex items-center gap-3"
            style={{
              fontSize: 12,
              padding: "6px 10px",
              background: "rgba(255,255,255,0.03)",
              borderRadius: 8,
            }}
          >
            <span style={{ flex: 1, fontFamily: "var(--font-mono)" }}>{p.displayName}</span>
            <span style={{ color: "rgba(255,255,255,0.5)", fontSize: 11 }}>
              {p.sessions} session{p.sessions === 1 ? "" : "s"}
            </span>
            <span style={{ color: "rgba(255,255,255,0.4)", fontSize: 10 }}>{shortAgo(p.lastActivity)}</span>
          </div>
        ))}
      </div>
    </Section>
  );
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div
      className="flex h-full w-full items-center justify-center"
      style={{
        flexDirection: "column",
        gap: 6,
        textAlign: "center",
        padding: 40,
        color: "rgba(255,255,255,0.55)",
      }}
    >
      <div style={{ fontSize: 14, fontWeight: 500 }}>{title}</div>
      <div style={{ fontSize: 12, color: "rgba(255,255,255,0.4)" }}>{body}</div>
    </div>
  );
}

function fmt(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1) + "k";
  return n.toString();
}

function fmtCredits(n: number): string {
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function fmtPercent(n: number): string {
  const rounded = Math.round(n);
  const value = Math.abs(n - rounded) < 0.05 ? String(rounded) : n.toFixed(1);
  return `${value}%`;
}

function formatWindow(minutes: number): string {
  if (minutes >= 1440 && minutes % 1440 === 0) return `${minutes / 1440}d window`;
  if (minutes >= 60 && minutes % 60 === 0) return `${minutes / 60}h window`;
  return `${minutes}m window`;
}

function shortDateTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "unknown";
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function shortAgo(iso: string): string {
  const t = new Date(iso).getTime();
  if (!t) return "";
  const diff = Date.now() - t;
  const m = Math.floor(diff / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function shortModel(m: string): string {
  return m.replace(/^claude-/, "").replace(/-\d{8}$/, "");
}

function palette(i: number): string {
  const colors = [
    "rgb(242, 99, 46)",
    "rgb(59, 219, 117)",
    "rgb(46, 128, 245)",
    "rgb(244, 179, 75)",
    "rgb(202, 102, 245)",
    "rgb(228, 80, 137)",
  ];
  return colors[i % colors.length];
}
