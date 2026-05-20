import { useEffect, useRef, useState } from "react";
import { ipc, type CliToolUsage } from "./ipc";

export type Tool = "claude" | "codex" | "lmstudio";
export type Timeframe = "day" | "week" | "month" | "year";

export function toolLabel(t: Tool): string {
  return t === "claude" ? "Claude Code" : t === "codex" ? "Codex" : "LM Studio";
}

export function toolBrandColor(t: Tool): string {
  return t === "claude"
    ? "rgb(242, 99, 46)"
    : t === "codex"
      ? "rgb(59, 219, 117)"
      : "rgb(158, 87, 240)";
}

export function timeframeLabel(tf: Timeframe): string {
  return tf === "day" ? "Day" : tf === "week" ? "Week" : tf === "month" ? "Month" : "Year";
}

export function timeframeHeadline(tf: Timeframe): string {
  return tf === "day"
    ? "Last 24 hours"
    : tf === "week"
      ? "Last 7 days"
      : tf === "month"
        ? "Last 30 days"
        : "Last 365 days";
}

export function useUsage(tool: Tool, timeframe: Timeframe) {
  const [data, setData] = useState<CliToolUsage | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const reqRef = useRef(0);

  useEffect(() => {
    const myReq = ++reqRef.current;
    setLoading(true);
    setError(null);
    ipc.usage
      .read(tool, timeframe)
      .then((d) => {
        if (myReq !== reqRef.current) return;
        setData(d);
        setLoading(false);
      })
      .catch((e) => {
        if (myReq !== reqRef.current) return;
        setError(String(e));
        setLoading(false);
      });
  }, [tool, timeframe]);

  const refresh = () => {
    const myReq = ++reqRef.current;
    setLoading(true);
    setError(null);
    ipc.usage
      .read(tool, timeframe)
      .then((d) => {
        if (myReq !== reqRef.current) return;
        setData(d);
        setLoading(false);
      })
      .catch((e) => {
        if (myReq !== reqRef.current) return;
        setError(String(e));
        setLoading(false);
      });
  };

  return { data, loading, error, refresh };
}
