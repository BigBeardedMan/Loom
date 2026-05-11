import { Component, type ErrorInfo, type ReactNode } from "react";
import { ipc } from "../../lib/ipc";

type Props = { children: ReactNode };
type State = { error: Error | null; info: ErrorInfo | null };

// Catches React render errors. The render fallback renders an inline
// "Loom crashed" card; the error itself is also forwarded to Rust so the
// next launch surfaces the regular CrashModal (the user might just reload).
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null, info: null };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    this.setState({ info });
    const body =
      `${error.name}: ${error.message}\n` +
      (error.stack ?? "") +
      (info.componentStack ? `\nComponent stack:${info.componentStack}` : "");
    ipc.crash.recordFrontend(body).catch(() => {});
  }

  reset = () => {
    this.setState({ error: null, info: null });
  };

  render() {
    if (!this.state.error) return this.props.children;

    return (
      <div
        className="flex h-full w-full items-center justify-center"
        style={{
          background: "var(--color-loom-cockpit)",
          color: "var(--color-loom-text)",
          padding: 24,
        }}
      >
        <div
          style={{
            maxWidth: 540,
            width: "100%",
            background: "var(--color-loom-panel)",
            border: "1px solid var(--color-loom-hairline)",
            borderRadius: 14,
            padding: 22,
            boxShadow: "0 20px 50px rgba(0,0,0,0.45)",
          }}
        >
          <h2 style={{ fontSize: 15, fontWeight: 600, marginBottom: 6 }}>
            Something broke in the UI
          </h2>
          <p style={{ fontSize: 12, color: "rgba(255,255,255,0.65)", marginBottom: 12 }}>
            The error is logged and will surface on the next launch with a Report button. You can
            also try reloading.
          </p>
          <pre
            className="scrollbar-thin"
            style={{
              maxHeight: 200,
              overflow: "auto",
              fontSize: 11,
              fontFamily: "var(--font-mono)",
              color: "rgba(255,255,255,0.85)",
              background: "rgba(255,255,255,0.04)",
              border: "1px solid rgba(255,255,255,0.06)",
              borderRadius: 8,
              padding: "8px 10px",
              whiteSpace: "pre-wrap",
              marginBottom: 14,
            }}
          >
            {this.state.error.name}: {this.state.error.message}
            {this.state.error.stack ? `\n${this.state.error.stack}` : ""}
          </pre>
          <div className="flex justify-end gap-2">
            <button
              onClick={() => window.location.reload()}
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
              Reload
            </button>
            <button
              onClick={this.reset}
              style={{
                padding: "6px 12px",
                fontSize: 12,
                borderRadius: 8,
                background: "rgba(255,255,255,0.06)",
                border: "1px solid rgba(255,255,255,0.10)",
                color: "rgba(255,255,255,0.85)",
              }}
            >
              Try again
            </button>
          </div>
        </div>
      </div>
    );
  }
}
