import { useState } from "react";
import { open as openExternal } from "@tauri-apps/plugin-shell";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import { Icons } from "../../lib/icons";
import type { CrashReport } from "../../lib/ipc";

type Props = {
  report: CrashReport;
  onClose: () => void;
};

const REPO = "BigBeardedMan/Loom";

export function CrashModal({ report, onClose }: Props) {
  const [copied, setCopied] = useState(false);

  const reportUrl = (() => {
    const title = encodeURIComponent(`Loom crashed: ${firstLineMessage(report.body)}`);
    const labels = encodeURIComponent("crash,windows");
    const body = encodeURIComponent(
      `**Version:** ${report.version}\n` +
        `**Arch:** ${report.arch}\n` +
        `**Captured:** ${report.timestamp}\n\n` +
        `Steps to reproduce:\n` +
        `1.\n2.\n3.\n\n` +
        `\`\`\`\n${truncate(report.body, 6000)}\n\`\`\`\n`
    );
    return `https://github.com/${REPO}/issues/new?title=${title}&body=${body}&labels=${labels}`;
  })();

  const copy = async () => {
    try {
      await writeText(report.body);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {}
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 flex items-center justify-center"
      style={{ background: "rgba(0,0,0,0.55)", zIndex: 100 }}
    >
      <div
        style={{
          width: 560,
          maxHeight: "82vh",
          display: "flex",
          flexDirection: "column",
          background: "var(--color-loom-panel)",
          color: "var(--color-loom-text)",
          border: "1px solid var(--color-loom-hairline)",
          borderRadius: 14,
          padding: 22,
          boxShadow: "0 20px 50px rgba(0,0,0,0.45)",
        }}
      >
        <header className="flex items-center gap-2" style={{ marginBottom: 6 }}>
          <Icons.failedCircle
            size={18}
            strokeWidth={2.2}
            style={{ color: "rgb(242, 70, 32)" }}
          />
          <h2 style={{ fontSize: 15, fontWeight: 600 }}>Loom crashed last time</h2>
        </header>
        <p style={{ fontSize: 12, color: "rgba(255,255,255,0.65)", marginBottom: 12 }}>
          A previous run ended in a panic. Details below — please file an issue so I can fix it.
        </p>

        <div
          className="scrollbar-thin"
          style={{
            flex: 1,
            minHeight: 120,
            overflow: "auto",
            background: "rgba(255,255,255,0.04)",
            border: "1px solid rgba(255,255,255,0.06)",
            borderRadius: 8,
            padding: "8px 10px",
            fontFamily: "var(--font-mono)",
            fontSize: 11,
            color: "rgba(255,255,255,0.85)",
            whiteSpace: "pre-wrap",
            marginBottom: 14,
          }}
        >
          {report.body}
        </div>

        <footer className="flex items-center justify-end gap-2">
          <button
            onClick={copy}
            style={{
              padding: "6px 12px",
              fontSize: 12,
              borderRadius: 8,
              background: "rgba(255,255,255,0.06)",
              border: "1px solid rgba(255,255,255,0.10)",
              color: "rgba(255,255,255,0.85)",
            }}
          >
            {copied ? "Copied" : "Copy details"}
          </button>
          <button
            onClick={() => openExternal(reportUrl).catch(() => {})}
            style={{
              padding: "6px 14px",
              fontSize: 12,
              fontWeight: 600,
              borderRadius: 8,
              background: "var(--color-ws-green)",
              color: "white",
              border: 0,
            }}
          >
            Report on GitHub
          </button>
          <button
            onClick={onClose}
            style={{
              padding: "6px 12px",
              fontSize: 12,
              borderRadius: 8,
              background: "rgba(255,255,255,0.04)",
              border: "1px solid rgba(255,255,255,0.10)",
              color: "rgba(255,255,255,0.7)",
            }}
          >
            Dismiss
          </button>
        </footer>
      </div>
    </div>
  );
}

function firstLineMessage(body: string): string {
  for (const line of body.split("\n")) {
    if (line.startsWith("Message:")) return line.replace("Message:", "").trim().slice(0, 80);
  }
  for (const line of body.split("\n")) {
    if (line.trim()) return line.trim().slice(0, 80);
  }
  return "unknown";
}

function truncate(s: string, n: number): string {
  return s.length <= n ? s : s.slice(0, n) + "\n…[truncated]";
}
