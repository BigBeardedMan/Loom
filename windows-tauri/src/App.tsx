import { useEffect, useState } from "react";
import { useApp } from "./lib/store";
import { useGlobalKeymap } from "./lib/keymap";
import { CommandPalette } from "./modules/workspace/CommandPalette";
import { SettingsModal } from "./modules/settings/SettingsModal";
import { ipc, type CrashReport } from "./lib/ipc";
import { ErrorBoundary } from "./modules/crash/ErrorBoundary";
import { CrashModal } from "./modules/crash/CrashModal";
import { AppShell } from "./components/AppShell";

function App() {
  const loadWorkspaces = useApp((s) => s.loadWorkspaces);
  const setUpdatePill = useApp((s) => s.setUpdatePill);
  const [crash, setCrash] = useState<CrashReport | null>(null);

  useGlobalKeymap();

  useEffect(() => {
    loadWorkspaces();
    const saved = localStorage.getItem("loom.theme");
    if (saved === "light" || saved === "dark")
      document.documentElement.setAttribute("data-theme", saved);
  }, [loadWorkspaces]);

  useEffect(() => {
    ipc.crash
      .getLast()
      .then((r) => {
        if (r) setCrash(r);
      })
      .catch(() => {});

    const onError = (e: ErrorEvent) => {
      const body = `${e.message}\n${e.filename ?? ""}:${e.lineno ?? "?"}:${e.colno ?? "?"}\n${
        e.error?.stack ?? ""
      }`;
      ipc.crash.recordFrontend(body).catch(() => {});
    };
    const onRejection = (e: PromiseRejectionEvent) => {
      const reason = e.reason;
      const body =
        reason instanceof Error
          ? `Unhandled rejection: ${reason.name}: ${reason.message}\n${reason.stack ?? ""}`
          : `Unhandled rejection: ${String(reason)}`;
      ipc.crash.recordFrontend(body).catch(() => {});
    };
    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onRejection);
    return () => {
      window.removeEventListener("error", onError);
      window.removeEventListener("unhandledrejection", onRejection);
    };
  }, []);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;
    const tick = async () => {
      try {
        const info = await ipc.update.check();
        if (info) setUpdatePill({ version: info.version });
        else setUpdatePill(null);
      } catch {}
    };
    tick();
    timer = setInterval(tick, 60_000);
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [setUpdatePill]);

  return (
    <ErrorBoundary>
      <>
        <AppShell />
        <CommandPalette />
        <SettingsModal />
        {crash && <CrashModal report={crash} onClose={() => setCrash(null)} />}
      </>
    </ErrorBoundary>
  );
}

export default App;
