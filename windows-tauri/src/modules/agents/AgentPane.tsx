import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { Icons } from "../../lib/icons";
import { useApp } from "../../lib/store";
import {
  ipc,
  on,
  type LmStudioDownloadStatus,
  type LmStudioModel,
  type LmStudioRuntimeStatus,
  type LocalEndpoint,
  type Workspace,
} from "../../lib/ipc";

type Vendor =
  | "claude"
  | "codex"
  | "gemini"
  | "ollama"
  | "lmstudio"
  | "anthropic"
  | "openai-compat";

type Turn = {
  id: string;
  role: "user" | "assistant" | "system";
  text: string;
  streaming?: boolean;
  vendor?: Vendor;
};

type LmStudioRunStatus = {
  phase: string;
  label: string;
  detail?: string | null;
  progress?: number | null;
};

type LmStudioRunUsage = {
  stats?: {
    input_tokens?: number;
    total_output_tokens?: number;
    reasoning_output_tokens?: number;
    tokens_per_second?: number;
    time_to_first_token_seconds?: number;
    model_load_time_seconds?: number;
  } | null;
  responseId?: string | null;
  modelInstanceId?: string | null;
};

const VENDORS: { value: Vendor; label: string }[] = [
  { value: "claude", label: "Claude CLI" },
  { value: "codex", label: "Codex" },
  { value: "gemini", label: "Gemini" },
  { value: "ollama", label: "Ollama" },
  { value: "lmstudio", label: "LM Studio" },
  { value: "openai-compat", label: "OpenAI-compatible" },
  { value: "anthropic", label: "Anthropic API" },
];

const LOCAL_HTTP_VENDORS = new Set<Vendor>(["ollama", "lmstudio", "openai-compat"]);

type Props = { workspace: Workspace; blockId?: string; presentation?: "agent" | "chat" };

// Mirrors Loom/Agents/AgentPaneView.swift.
// Vendor picker, model field, transcript, input bar. Block title bar lives in BlockTitleBar.
export function AgentPane({ workspace, blockId, presentation = "agent" }: Props) {
  const isChatPane = presentation === "chat";
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [vendor, setVendor] = useState<Vendor>(
    () => (localStorage.getItem(`loom.agent.vendor.${workspace.id}`) as Vendor) || "claude"
  );
  const [model, setModel] = useState(
    () =>
      localStorage.getItem(`loom.agent.model.${workspace.id}`) ||
      "claude-sonnet-4-6"
  );
  const [endpoints, setEndpoints] = useState<LocalEndpoint[]>([]);
  const [endpointId, setEndpointId] = useState<string>(
    () => localStorage.getItem(`loom.agent.endpoint.${workspace.id}`) || ""
  );
  const [turns, setTurns] = useState<Turn[]>([]);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [lmModels, setLmModels] = useState<LmStudioModel[]>([]);
  const [lmRuntime, setLmRuntime] = useState<LmStudioRuntimeStatus | null>(null);
  const [lmModelsLoading, setLmModelsLoading] = useState(false);
  const [lmBusy, setLmBusy] = useState(false);
  const [lmAutoScale, setLmAutoScale] = useState(
    () => localStorage.getItem(`loom.lmstudio.autoScale.${workspace.id}`) !== "false"
  );
  const [lmContextTarget, setLmContextTarget] = useState(() => {
    const saved = Number(localStorage.getItem(`loom.lmstudio.context.${workspace.id}`));
    return Number.isFinite(saved) && saved >= 4096 ? saved : 65536;
  });
  const [lmRoutingEnabled, setLmRoutingEnabled] = useState(
    () => localStorage.getItem(`loom.lmstudio.routing.${workspace.id}`) === "true"
  );
  const [lmPlannerModel, setLmPlannerModel] = useState(
    () => localStorage.getItem(`loom.lmstudio.planner.${workspace.id}`) || ""
  );
  const [lmCoderModel, setLmCoderModel] = useState(
    () => localStorage.getItem(`loom.lmstudio.coder.${workspace.id}`) || ""
  );
  const [lmReviewerModel, setLmReviewerModel] = useState(
    () => localStorage.getItem(`loom.lmstudio.reviewer.${workspace.id}`) || ""
  );
  const [lmDownloadModel, setLmDownloadModel] = useState("");
  const [lmDownloadQuantization, setLmDownloadQuantization] = useState("");
  const [lmDownloadStatus, setLmDownloadStatus] = useState<LmStudioDownloadStatus | null>(null);
  const [lmRunStatus, setLmRunStatus] = useState<LmStudioRunStatus | null>(null);
  const [lmRunUsage, setLmRunUsage] = useState<LmStudioRunUsage | null>(null);
  const [lmNativeResponseId, setLmNativeResponseId] = useState<string | null>(null);
  const cleanupRef = useRef<(() => void) | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    localStorage.setItem(`loom.agent.vendor.${workspace.id}`, vendor);
  }, [vendor, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.agent.model.${workspace.id}`, model);
  }, [model, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.agent.endpoint.${workspace.id}`, endpointId);
  }, [endpointId, workspace.id]);

  useEffect(() => {
    localStorage.setItem(
      `loom.lmstudio.autoScale.${workspace.id}`,
      lmAutoScale ? "true" : "false"
    );
  }, [lmAutoScale, workspace.id]);

  useEffect(() => {
    localStorage.setItem(
      `loom.lmstudio.context.${workspace.id}`,
      String(lmContextTarget)
    );
  }, [lmContextTarget, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.lmstudio.routing.${workspace.id}`, lmRoutingEnabled ? "true" : "false");
  }, [lmRoutingEnabled, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.lmstudio.planner.${workspace.id}`, lmPlannerModel);
  }, [lmPlannerModel, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.lmstudio.coder.${workspace.id}`, lmCoderModel);
  }, [lmCoderModel, workspace.id]);

  useEffect(() => {
    localStorage.setItem(`loom.lmstudio.reviewer.${workspace.id}`, lmReviewerModel);
  }, [lmReviewerModel, workspace.id]);

  useEffect(() => {
    ipc.endpoints.list().then(setEndpoints).catch(() => {});
  }, []);

  const matchingEndpoints = endpoints.filter((e) => {
    if (vendor === "ollama") return e.kind === "ollama";
    if (vendor === "lmstudio") return e.kind === "lmstudio";
    if (vendor === "openai-compat") return e.kind === "openai-compat";
    return false;
  });
  const activeEndpoint =
    matchingEndpoints.find((e) => e.id === endpointId) ?? matchingEndpoints[0];
  const usesEndpoint = LOCAL_HTTP_VENDORS.has(vendor);
  const lmEffectiveModel =
    vendor === "lmstudio" && lmRoutingEnabled && lmCoderModel.trim()
      ? lmCoderModel.trim()
      : model;

  useEffect(() => {
    setLmNativeResponseId(null);
  }, [activeEndpoint?.id, lmEffectiveModel, vendor]);

  useEffect(() => {
    if (!usesEndpoint || matchingEndpoints.length === 0) return;
    if (!matchingEndpoints.some((endpoint) => endpoint.id === endpointId)) {
      setEndpointId(matchingEndpoints[0].id);
    }
  }, [endpointId, matchingEndpoints, usesEndpoint]);

  useEffect(() => {
    if (!blockId) return;
    setBlockStatus(blockId, busy ? "active" : "idle");
  }, [busy, blockId, setBlockStatus]);

  useEffect(() => () => cleanupRef.current?.(), []);

  useEffect(() => {
    const onDictation = (event: Event) => {
      const text = (event as CustomEvent<{ text?: string }>).detail?.text?.trim();
      if (!text) return;
      setDraft((prev) => (prev.trim() ? `${prev} ${text}` : text));
    };
    window.addEventListener("loom-dictation-insert", onDictation);
    return () => window.removeEventListener("loom-dictation-insert", onDictation);
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: 99999, behavior: "smooth" });
  }, [turns]);

  useEffect(() => {
    if (vendor !== "lmstudio" || !activeEndpoint) {
      setLmModels([]);
      setLmRuntime(null);
      setLmModelsLoading(false);
      return;
    }

    let cancelled = false;
    setLmModelsLoading(true);
    Promise.all([
      ipc.lmStudio.models(activeEndpoint.id).catch(() => [] as LmStudioModel[]),
      ipc.lmStudio.runtimeStatus(activeEndpoint.id),
    ])
      .then(([models, runtime]) => {
        if (cancelled) return;
        setLmModels(models);
        setLmRuntime(runtime);
        const recommended =
          runtime.recommendedModelId ||
          models.find((entry) => entry.loaded)?.id ||
          models[0]?.id ||
          activeEndpoint.defaultModel;
        if (recommended && (!model.trim() || !models.some((entry) => entry.id === model))) {
          setModel(recommended);
        }
      })
      .catch((e) => {
        if (cancelled) return;
        setLmRuntime(emptyLmRuntime(String(e)));
      })
      .finally(() => {
        if (!cancelled) setLmModelsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [activeEndpoint?.id, vendor]);

  const refreshLmStudio = async () => {
    if (!activeEndpoint) return;
    setLmModelsLoading(true);
    try {
      const runtime = await ipc.lmStudio.runtimeStatus(activeEndpoint.id);
      setLmRuntime(runtime);
      setLmModels(runtime.models);
      const recommended =
        runtime.recommendedModelId ||
        runtime.models.find((entry) => entry.loaded)?.id ||
        runtime.models[0]?.id ||
        activeEndpoint.defaultModel;
      if (recommended && (!model.trim() || !runtime.models.some((entry) => entry.id === model))) {
        setModel(recommended);
      }
    } catch (e) {
      setLmRuntime((current) => ({ ...emptyLmRuntime(String(e)), ...(current ?? {}), lastError: String(e) }));
    } finally {
      setLmModelsLoading(false);
    }
  };

  const prepareLmStudio = async () => {
    if (!activeEndpoint) return;
    setLmBusy(true);
    try {
      const runtime = await ipc.lmStudio.prepare({
        endpointId: activeEndpoint.id,
        preferredModel: lmEffectiveModel || activeEndpoint.defaultModel || undefined,
        contextTarget: lmContextTarget,
        autoScale: lmAutoScale,
      });
      setLmRuntime(runtime);
      setLmModels(runtime.models);
      if (runtime.recommendedModelId) setModel(runtime.recommendedModelId);
    } catch (e) {
      setLmRuntime((current) => ({ ...emptyLmRuntime(String(e)), ...(current ?? {}), lastError: String(e) }));
    } finally {
      setLmBusy(false);
    }
  };

  const loadLmStudioModel = async (modelId: string) => {
    if (!activeEndpoint) return;
    setLmBusy(true);
    try {
      const runtime = await ipc.lmStudio.load({
        endpointId: activeEndpoint.id,
        model: modelId,
        contextTarget: lmContextTarget,
      });
      setLmRuntime(runtime);
      setLmModels(runtime.models);
      setModel(modelId);
    } catch (e) {
      setLmRuntime((current) => ({ ...emptyLmRuntime(String(e)), ...(current ?? {}), lastError: String(e) }));
    } finally {
      setLmBusy(false);
    }
  };

  const unloadLmStudioModel = async (entry: LmStudioModel) => {
    if (!activeEndpoint) return;
    setLmBusy(true);
    try {
      const runtime = await ipc.lmStudio.unload({
        endpointId: activeEndpoint.id,
        model: entry.id,
        instanceId: entry.loadedInstanceIds[0] || entry.id,
      });
      setLmRuntime(runtime);
      setLmModels(runtime.models);
    } catch (e) {
      setLmRuntime((current) => ({ ...emptyLmRuntime(String(e)), ...(current ?? {}), lastError: String(e) }));
    } finally {
      setLmBusy(false);
    }
  };

  const downloadLmStudioModel = async () => {
    if (!activeEndpoint) return;
    const target = lmDownloadModel.trim();
    if (!target) return;
    setLmBusy(true);
    try {
      const status = await ipc.lmStudio.download({
        endpointId: activeEndpoint.id,
        model: target,
        quantization: lmDownloadQuantization.trim() || undefined,
      });
      setLmDownloadStatus(status);
      await refreshLmStudio();
    } catch (e) {
      setLmRuntime((current) => ({ ...emptyLmRuntime(String(e)), ...(current ?? {}), lastError: String(e) }));
    } finally {
      setLmBusy(false);
    }
  };

  const submit = async () => {
    const prompt = draft.trim();
    if (!prompt || busy) return;
    setDraft("");
    const lmPreviousResponseId =
      vendor === "lmstudio" && turns.length > 0 ? lmNativeResponseId : null;
    if (vendor === "lmstudio") {
      setLmRunStatus(null);
      setLmRunUsage(null);
      if (!lmPreviousResponseId) setLmNativeResponseId(null);
    }
    const userTurn: Turn = { id: crypto.randomUUID(), role: "user", text: prompt };
    const asstId = crypto.randomUUID();
    const asstTurn: Turn = {
      id: asstId,
      role: "assistant",
      text: "",
      streaming: true,
      vendor,
    };
    setTurns((prev) => [...prev, userTurn, asstTurn]);
    setBusy(true);

    try {
      if (vendor === "anthropic") await runAnthropic(prompt, asstId);
      else if (
        vendor === "openai-compat" ||
        vendor === "lmstudio" ||
        (vendor === "ollama" && activeEndpoint)
      )
        await runOpenAi(prompt, asstId, lmPreviousResponseId);
      else await runCli(prompt, asstId);
    } catch (e) {
      setTurns((prev) =>
        prev.map((t) =>
          t.id === asstId
            ? { ...t, text: `${t.text}\n[error] ${String(e)}`, streaming: false }
            : t
        )
      );
      setBusy(false);
    }
  };

  const runCli = async (prompt: string, asstId: string) => {
    const streamId = await ipc.agents.cliSend({
      vendor: vendor as "claude" | "codex" | "gemini" | "ollama",
      prompt,
      cwd: workspace.folderPath || ".",
    });
    const off1 = await on<string>(`agent://${streamId}/chunk`, (line) => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, text: t.text + line + "\n" } : t))
      );
    });
    const off2 = await on<number>(`agent://${streamId}/done`, () => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, streaming: false } : t))
      );
      setBusy(false);
      if (!document.hasFocus()) {
        ipc.notify(`${vendor} agent done`, "Loom agent finished a response.");
      }
      off1();
      off2();
      cleanupRef.current = null;
    });
    cleanupRef.current = () => {
      off1();
      off2();
    };
  };

  const runOpenAi = async (prompt: string, asstId: string, previousResponseId?: string | null) => {
    if (!activeEndpoint) {
      throw new Error("No endpoint configured. Open Settings → AI Providers to add one.");
    }
    const messages = [{ role: "user", content: prompt }];
    const selectedModel =
      vendor === "lmstudio"
        ? lmEffectiveModel || lmRuntime?.recommendedModelId || activeEndpoint.defaultModel || ""
        : model || activeEndpoint.defaultModel || "";
    const streamId = await ipc.agents.openaiSend({
      endpointId: activeEndpoint.id,
      model: selectedModel,
      messages,
      maxTokens: 4096,
      previousResponseId: vendor === "lmstudio" ? previousResponseId ?? undefined : undefined,
    });
    const off1 = await on<{ kind: string; data: unknown }>(
      `agent://${streamId}/event`,
      (ev) => {
        if (ev.kind === "content_block_delta") {
          const t = (ev.data as { delta?: { text?: string } }).delta?.text || "";
          if (t)
            setTurns((prev) =>
              prev.map((x) => (x.id === asstId ? { ...x, text: x.text + t } : x))
            );
        } else if (ev.kind === "lmstudio_status") {
          setLmRunStatus(ev.data as LmStudioRunStatus);
        } else if (ev.kind === "lmstudio_usage") {
          const usage = ev.data as LmStudioRunUsage;
          setLmRunUsage(usage);
          if (usage.responseId) setLmNativeResponseId(usage.responseId);
        }
      }
    );
    const off2 = await on<number>(`agent://${streamId}/done`, () => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, streaming: false } : t))
      );
      setBusy(false);
      if (!document.hasFocus()) {
        ipc.notify(`${activeEndpoint?.name ?? "Agent"} done`, "Loom agent finished a response.");
      }
      off1();
      off2();
      cleanupRef.current = null;
    });
    const off3 = await on<string>(`agent://${streamId}/error`, (msg) => {
      setTurns((prev) =>
        prev.map((t) =>
          t.id === asstId
            ? { ...t, text: `${t.text}\n[error] ${msg}`, streaming: false }
            : t
        )
      );
    });
    cleanupRef.current = () => {
      off1();
      off2();
      off3();
    };
  };

  const runAnthropic = async (prompt: string, asstId: string) => {
    const apiKey = await ipc.keychain.get("loom.anthropic", "default");
    if (!apiKey) throw new Error("Anthropic API key not set. Open Settings to add one.");
    const messages = [{ role: "user", content: prompt }];
    const streamId = await ipc.agents.httpSend({
      apiKey,
      model,
      messages,
      maxTokens: 4096,
    });
    const off1 = await on<{ kind: string; data: unknown }>(
      `agent://${streamId}/event`,
      (ev) => {
        if (ev.kind === "content_block_delta") {
          const t = (ev.data as { delta?: { text?: string } }).delta?.text || "";
          if (t)
            setTurns((prev) =>
              prev.map((x) => (x.id === asstId ? { ...x, text: x.text + t } : x))
            );
        }
      }
    );
    const off2 = await on<number>(`agent://${streamId}/done`, () => {
      setTurns((prev) =>
        prev.map((t) => (t.id === asstId ? { ...t, streaming: false } : t))
      );
      setBusy(false);
      if (!document.hasFocus()) {
        ipc.notify("Anthropic agent done", "Loom agent finished a response.");
      }
      off1();
      off2();
      cleanupRef.current = null;
    });
    cleanupRef.current = () => {
      off1();
      off2();
    };
  };

  const cancel = () => {
    cleanupRef.current?.();
    cleanupRef.current = null;
    setTurns((prev) => prev.map((t) => (t.streaming ? { ...t, streaming: false } : t)));
    setBusy(false);
  };

  const lmReadiness = [
    {
      label: "Workspace",
      ok: Boolean(workspace.folderPath),
      detail: workspace.folderPath || "Set a workspace folder.",
    },
    {
      label: "Server",
      ok: lmRuntime?.serverReachable === true,
      detail: lmRuntimeLabel(lmRuntime, activeEndpoint),
    },
    {
      label: "Model",
      ok: lmModels.some((entry) => entry.id === lmEffectiveModel && entry.loaded),
      detail: lmEffectiveModel || lmRuntime?.recommendedModelId || "No selected model.",
    },
    {
      label: "API",
      ok: lmRuntime?.supportsNativeChat === true || lmRuntime?.supportsV1 === true,
      detail: lmRuntime?.supportsNativeChat
        ? "Native v1 chat + streaming"
        : lmRuntime?.apiMode
          ? lmRuntime.apiMode.toUpperCase()
          : "checking",
    },
  ];

  return (
    <div className="flex h-full flex-col" style={{ background: "#04050A" }}>
      <div
        className="flex items-center gap-2 flex-none"
        style={{
          padding: "6px 12px",
          background: "rgba(0, 0, 0, 0.25)",
          borderBottom: "1px solid rgba(255, 255, 255, 0.10)",
        }}
      >
        <select
          value={vendor}
          onChange={(e) => setVendor(e.target.value as Vendor)}
          className="focus:outline-none"
          style={{
            background: "rgba(255, 255, 255, 0.06)",
            border: "1px solid rgba(255, 255, 255, 0.10)",
            borderRadius: 4,
            padding: "3px 8px",
            fontSize: 11,
            color: "rgba(255, 255, 255, 0.9)",
          }}
        >
          {VENDORS.map((v) => (
            <option key={v.value} value={v.value}>
              {v.label}
            </option>
          ))}
        </select>
        {vendor === "anthropic" && (
          <input
            value={model}
            onChange={(e) => setModel(e.target.value)}
            placeholder="model"
            className="focus:outline-none"
            style={{
              background: "rgba(255, 255, 255, 0.06)",
              border: "1px solid rgba(255, 255, 255, 0.10)",
              borderRadius: 4,
              padding: "3px 8px",
              fontSize: 11,
              width: 160,
              color: "rgba(255, 255, 255, 0.9)",
              fontFamily: "var(--font-mono)",
            }}
          />
        )}
        {usesEndpoint && (
          <>
            {matchingEndpoints.length > 0 ? (
              <select
                value={activeEndpoint?.id ?? ""}
                onChange={(e) => setEndpointId(e.target.value)}
                className="focus:outline-none"
                style={{
                  background: "rgba(255, 255, 255, 0.06)",
                  border: "1px solid rgba(255, 255, 255, 0.10)",
                  borderRadius: 4,
                  padding: "3px 8px",
                  fontSize: 11,
                  color: "rgba(255, 255, 255, 0.9)",
                  maxWidth: 200,
                }}
              >
                {matchingEndpoints.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.name}
                  </option>
                ))}
              </select>
            ) : (
              <span style={{ fontSize: 10, color: "rgba(255,255,255,0.45)" }}>
                Add one in Settings → AI Providers
              </span>
            )}
            {activeEndpoint && (
              vendor === "lmstudio" && lmModels.length > 0 ? (
                <select
                  value={model}
                  onChange={(e) => setModel(e.target.value)}
                  className="focus:outline-none"
                  style={{
                    background: "rgba(255, 255, 255, 0.06)",
                    border: "1px solid rgba(255, 255, 255, 0.10)",
                    borderRadius: 4,
                    padding: "3px 8px",
                    fontSize: 11,
                    width: 220,
                    color: "rgba(255, 255, 255, 0.9)",
                    fontFamily: "var(--font-mono)",
                  }}
                >
                  {lmModels.map((entry) => (
                    <option key={entry.id} value={entry.id}>
                      {entry.loaded ? "Loaded · " : ""}
                      {entry.id}
                      {entry.detail ? ` · ${entry.detail}` : ""}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  value={model}
                  onChange={(e) => setModel(e.target.value)}
                  placeholder={
                    vendor === "lmstudio"
                      ? activeEndpoint.defaultModel || "auto-discover model"
                      : activeEndpoint.defaultModel || "model"
                  }
                  className="focus:outline-none"
                  style={{
                    background: "rgba(255, 255, 255, 0.06)",
                    border: "1px solid rgba(255, 255, 255, 0.10)",
                    borderRadius: 4,
                    padding: "3px 8px",
                    fontSize: 11,
                    width: 140,
                    color: "rgba(255, 255, 255, 0.9)",
                    fontFamily: "var(--font-mono)",
                  }}
                />
              )
            )}
          </>
        )}
      </div>

      {vendor === "lmstudio" && (
        <div
          className="flex items-center gap-2 flex-none"
          style={{
            padding: "7px 12px",
            background: "rgba(255, 255, 255, 0.035)",
            borderBottom: "1px solid rgba(255, 255, 255, 0.08)",
            color: "rgba(255, 255, 255, 0.74)",
            fontSize: 11,
          }}
        >
          <Icons.cpu
            size={13}
            strokeWidth={2}
            color={lmRuntime?.serverReachable ? "var(--color-ws-green)" : "rgba(255,255,255,0.5)"}
          />
          <span style={{ fontWeight: 650, color: "rgba(255,255,255,0.88)" }}>
            {lmRuntimeLabel(lmRuntime, activeEndpoint)}
          </span>
          {lmRuntime?.recommendedModelId && (
            <span
              style={{
                maxWidth: 280,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                fontFamily: "var(--font-mono)",
              }}
              title={lmRuntime.recommendedModelId}
            >
              {lmRuntime.recommendedModelId}
            </span>
          )}
          {lmRunStatus && (
            <span
              title={lmRunStatus.detail || lmRunStatus.phase}
              style={{
                maxWidth: 220,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                color: "rgba(255,255,255,0.62)",
              }}
            >
              {lmRunStatus.label}
              {typeof lmRunStatus.progress === "number"
                ? ` · ${Math.round(lmRunStatus.progress * 100)}%`
                : ""}
            </span>
          )}
          {lmRunUsage && (
            <span
              title={lmRunUsage.modelInstanceId || undefined}
              style={{
                maxWidth: 190,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                color: "rgba(255,255,255,0.55)",
                fontFamily: "var(--font-mono)",
              }}
            >
              {lmUsageText(lmRunUsage)}
            </span>
          )}
          <button
            onClick={refreshLmStudio}
            disabled={!activeEndpoint || lmModelsLoading || lmBusy}
            title="Refresh LM Studio"
            aria-label="Refresh LM Studio"
            style={{
              marginLeft: "auto",
              padding: 3,
              borderRadius: 4,
              color: "rgba(255,255,255,0.58)",
              opacity: !activeEndpoint || lmModelsLoading || lmBusy ? 0.5 : 1,
            }}
          >
            <Icons.refresh
              size={11}
              strokeWidth={2}
              className={lmModelsLoading ? "animate-spin" : undefined}
            />
          </button>
          <label className="flex items-center gap-1.5" style={{ whiteSpace: "nowrap" }}>
            <input
              type="checkbox"
              checked={lmAutoScale}
              onChange={(e) => setLmAutoScale(e.target.checked)}
              style={{ accentColor: "var(--color-loom-accent)" }}
            />
            Auto-scale
          </label>
          <input
            type="number"
            min={4096}
            max={131072}
            step={4096}
            value={lmContextTarget}
            onChange={(e) => setLmContextTarget(Number(e.target.value) || 65536)}
            title="Context target"
            aria-label="LM Studio context target"
            style={{
              width: 78,
              background: "rgba(255, 255, 255, 0.06)",
              border: "1px solid rgba(255, 255, 255, 0.10)",
              borderRadius: 4,
              padding: "3px 6px",
              color: "rgba(255,255,255,0.88)",
              fontSize: 11,
              fontFamily: "var(--font-mono)",
            }}
          />
          <button
            onClick={prepareLmStudio}
            disabled={!activeEndpoint || lmBusy}
            className="flex items-center gap-1"
            style={{
              padding: "4px 9px",
              borderRadius: 5,
              background: "var(--color-loom-accent)",
              color: "white",
              opacity: !activeEndpoint || lmBusy ? 0.55 : 1,
            }}
          >
            {lmBusy ? (
              <Icons.spinner size={11} strokeWidth={2} className="animate-spin" />
            ) : (
              <Icons.server size={11} strokeWidth={2} />
            )}
            Prepare
          </button>
          {lmRuntime?.lastError && (
            <span
              style={{
                color: "rgb(242,99,46)",
                maxWidth: 260,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
              }}
              title={lmRuntime.lastError}
            >
              {lmRuntime.lastError}
            </span>
          )}
        </div>
      )}

      {vendor === "lmstudio" && (
        <div
          className="grid flex-none gap-2"
          style={{
            gridTemplateColumns: "minmax(220px, 0.9fr) minmax(260px, 1.2fr) minmax(220px, 0.9fr)",
            padding: "8px 12px",
            background: "rgba(255, 255, 255, 0.025)",
            borderBottom: "1px solid rgba(255, 255, 255, 0.08)",
          }}
        >
          <div style={lmPanelStyle}>
            <PanelTitle icon={<Icons.check size={12} strokeWidth={2} />} label="Readiness" />
            <div className="flex flex-col gap-1">
              {lmReadiness.map((row) => (
                <div key={row.label} className="flex items-start gap-1.5">
                  <span
                    style={{
                      width: 7,
                      height: 7,
                      borderRadius: 999,
                      marginTop: 5,
                      background: row.ok ? "var(--color-ws-green)" : "rgb(242, 163, 60)",
                      flex: "0 0 auto",
                    }}
                  />
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontSize: 10, fontWeight: 650, color: "rgba(255,255,255,0.86)" }}>
                      {row.label}
                    </div>
                    <div
                      title={row.detail}
                      style={{
                        fontSize: 10,
                        color: "rgba(255,255,255,0.48)",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                      }}
                    >
                      {row.detail}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div style={lmPanelStyle}>
            <PanelTitle icon={<Icons.cpu size={12} strokeWidth={2} />} label="Model Library" />
            <div className="flex flex-col gap-1" style={{ maxHeight: 128, overflow: "auto" }}>
              {lmModels.length === 0 ? (
                <span style={{ fontSize: 10, color: "rgba(255,255,255,0.45)" }}>
                  No LM Studio models reported yet.
                </span>
              ) : (
                lmModels.slice(0, 6).map((entry) => (
                  <div
                    key={entry.id}
                    className="flex items-center gap-1.5"
                    style={{ minWidth: 0, fontSize: 10 }}
                  >
                    <span
                      style={{
                        width: 7,
                        height: 7,
                        borderRadius: 999,
                        background: entry.loaded ? "var(--color-ws-green)" : "rgba(255,255,255,0.28)",
                        flex: "0 0 auto",
                      }}
                    />
                    <button
                      onClick={() => setModel(entry.id)}
                      title={`${entry.displayName ? `${entry.displayName} · ` : ""}${entry.id}${entry.detail ? ` · ${entry.detail}` : ""}`}
                      style={{
                        minWidth: 0,
                        flex: 1,
                        textAlign: "left",
                        overflow: "hidden",
                        textOverflow: "ellipsis",
                        whiteSpace: "nowrap",
                        color: entry.id === model ? "var(--color-loom-accent)" : "rgba(255,255,255,0.82)",
                        fontFamily: "var(--font-mono)",
                      }}
                    >
                      {entry.displayName ? `${entry.displayName} · ` : ""}
                      {entry.id}
                    </button>
                    <button
                      onClick={() => loadLmStudioModel(entry.id)}
                      disabled={lmBusy}
                      style={miniButtonStyle}
                    >
                      {entry.loaded ? "Reload" : "Load"}
                    </button>
                    {entry.loaded && (
                      <button
                        onClick={() => unloadLmStudioModel(entry)}
                        disabled={lmBusy}
                        style={miniButtonStyle}
                      >
                        Unload
                      </button>
                    )}
                  </div>
                ))
              )}
            </div>
            <div className="mt-2 flex gap-1.5">
              <input
                value={lmDownloadModel}
                onChange={(e) => setLmDownloadModel(e.target.value)}
                placeholder="model id or Hugging Face URL"
                style={compactInputStyle}
              />
              <input
                value={lmDownloadQuantization}
                onChange={(e) => setLmDownloadQuantization(e.target.value)}
                placeholder="Q4_K_M"
                style={{ ...compactInputStyle, width: 72, flex: "0 0 auto" }}
              />
              <button
                onClick={downloadLmStudioModel}
                disabled={!lmRuntime?.supportsDownloads || lmBusy || !lmDownloadModel.trim()}
                style={miniButtonStyle}
              >
                Download
              </button>
            </div>
            {lmDownloadStatus && (
              <div style={{ marginTop: 4, fontSize: 10, color: "rgba(255,255,255,0.48)" }}>
                {downloadStatusText(lmDownloadStatus)}
              </div>
            )}
          </div>

          <div style={lmPanelStyle}>
            <PanelTitle icon={<Icons.package size={12} strokeWidth={2} />} label="Run Profiles" />
            <label className="flex items-center gap-1.5" style={{ fontSize: 10, color: "rgba(255,255,255,0.72)" }}>
              <input
                type="checkbox"
                checked={lmRoutingEnabled}
                onChange={(e) => setLmRoutingEnabled(e.target.checked)}
                style={{ accentColor: "var(--color-loom-accent)" }}
              />
              Route planner / coder / reviewer
            </label>
            <ProfileInput label="Planner" value={lmPlannerModel} onChange={setLmPlannerModel} />
            <ProfileInput label="Coder" value={lmCoderModel} onChange={setLmCoderModel} />
            <ProfileInput label="Reviewer" value={lmReviewerModel} onChange={setLmReviewerModel} />
          </div>
        </div>
      )}

      <div
        ref={scrollRef}
        className="scrollbar-thin flex-1 overflow-y-auto"
        style={{ padding: "12px 16px" }}
      >
        {turns.length === 0 && (
          <div
            className="flex h-full items-center justify-center"
            style={{ color: "rgba(255, 255, 255, 0.35)", fontSize: 12 }}
          >
            {isChatPane ? "Start a chat about this workspace." : "Ask the agent anything about this workspace."}
          </div>
        )}
        {turns.map((t, i) => (
          <div
            key={t.id}
            className="flex flex-col gap-1"
            style={{
              marginBottom: 14,
              background:
                t.role === "user" ? "rgba(255, 255, 255, 0.04)" : "transparent",
              borderRadius: 8,
              padding: t.role === "user" ? "8px 10px" : 0,
            }}
          >
            <span
              className="uppercase"
              style={{
                fontSize: 10,
                fontWeight: 600,
                letterSpacing: 0.6,
                color: "rgba(255, 255, 255, 0.45)",
              }}
            >
              {t.role === "user" ? "You" : t.vendor ?? "Agent"}
              {t.streaming && (
                <Icons.spinner
                  size={10}
                  strokeWidth={2}
                  className="ml-1 inline-block animate-spin"
                  style={{ verticalAlign: -1 }}
                />
              )}
            </span>
            <pre
              className="whitespace-pre-wrap break-words"
              style={{
                fontSize: 13,
                fontFamily: t.role === "user" ? "var(--font-sans)" : "var(--font-mono)",
                color: "rgba(255, 255, 255, 0.92)",
                lineHeight: 1.5,
                margin: 0,
              }}
            >
              {t.text}
            </pre>
            {i < turns.length - 1 && i % 2 === 1 && (
              <hr
                style={{
                  border: "none",
                  borderTop: "1px solid rgba(255, 255, 255, 0.06)",
                  margin: "8px 0 0",
                }}
              />
            )}
          </div>
        ))}
      </div>

      <div
        className="flex items-end gap-2 flex-none"
        style={{
          padding: 10,
          background: "rgba(0, 0, 0, 0.24)",
          borderTop: "1px solid rgba(255, 255, 255, 0.10)",
        }}
      >
        <textarea
          rows={2}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              submit();
            }
          }}
          placeholder={isChatPane ? "Message this chat…" : "Message the agent…"}
          className="scrollbar-thin flex-1 resize-none focus:outline-none"
          style={{
            background: "rgba(255, 255, 255, 0.06)",
            border: "1px solid rgba(255, 255, 255, 0.10)",
            borderRadius: 8,
            padding: "8px 10px",
            fontSize: 13,
            fontFamily: "var(--font-mono)",
            color: "rgba(255, 255, 255, 0.92)",
            minHeight: 38,
          }}
        />
        {busy ? (
          <button
            onClick={cancel}
            aria-label="Cancel"
            style={{
              background: "rgba(242, 70, 32, 0.85)",
              color: "white",
              borderRadius: 999,
              padding: 8,
              border: "none",
            }}
          >
            <Icons.cancel size={14} strokeWidth={2.4} fill="currentColor" />
          </button>
        ) : (
          <button
            onClick={submit}
            disabled={!draft.trim()}
            aria-label="Send"
            style={{
              background: draft.trim()
                ? "var(--color-loom-accent)"
                : "rgba(255, 255, 255, 0.10)",
              color: "white",
              borderRadius: 999,
              padding: 8,
              border: "none",
              opacity: draft.trim() ? 1 : 0.5,
            }}
          >
            <Icons.send size={14} strokeWidth={2.2} />
          </button>
        )}
      </div>
    </div>
  );
}

function lmRuntimeLabel(
  runtime: LmStudioRuntimeStatus | null,
  endpoint?: LocalEndpoint
): string {
  if (!endpoint) return "No LM Studio endpoint";
  if (!runtime) return "Checking LM Studio";
  if (runtime.state === "missing-cli") return "LM Studio CLI missing";
  if (runtime.state === "running") return "LM Studio running";
  if (runtime.state === "stopped") return "LM Studio stopped";
  if (runtime.state === "no-endpoint") return "No LM Studio endpoint";
  return runtime.state;
}

function emptyLmRuntime(error: string): LmStudioRuntimeStatus {
  return {
    cliInstalled: false,
    serverReachable: false,
    state: "stopped",
    apiMode: "unknown",
    supportsV1: false,
    supportsNativeChat: false,
    supportsStreamingEvents: false,
    supportsStatefulChat: false,
    supportsNativeMcp: false,
    supportsModelManagement: false,
    supportsDownloads: false,
    supportsAuthToken: false,
    lastCapabilityError: null,
    models: [],
    recommendedModelId: null,
    lastError: error,
  };
}

const lmPanelStyle: CSSProperties = {
  minWidth: 0,
  padding: 8,
  borderRadius: 6,
  background: "rgba(255, 255, 255, 0.04)",
  border: "1px solid rgba(255, 255, 255, 0.08)",
};

const miniButtonStyle: CSSProperties = {
  padding: "3px 6px",
  borderRadius: 4,
  background: "rgba(255,255,255,0.07)",
  border: "1px solid rgba(255,255,255,0.10)",
  color: "rgba(255,255,255,0.82)",
  fontSize: 10,
  whiteSpace: "nowrap",
};

const compactInputStyle: CSSProperties = {
  minWidth: 0,
  flex: 1,
  background: "rgba(255, 255, 255, 0.06)",
  border: "1px solid rgba(255, 255, 255, 0.10)",
  borderRadius: 4,
  padding: "3px 6px",
  color: "rgba(255,255,255,0.88)",
  fontSize: 10,
  fontFamily: "var(--font-mono)",
};

function PanelTitle({ icon, label }: { icon: ReactNode; label: string }) {
  return (
    <div className="mb-1.5 flex items-center gap-1.5" style={{ color: "rgba(255,255,255,0.88)" }}>
      {icon}
      <span style={{ fontSize: 10, fontWeight: 750 }}>{label}</span>
    </div>
  );
}

function ProfileInput({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <label className="mt-1 flex items-center gap-1.5" style={{ fontSize: 10, color: "rgba(255,255,255,0.58)" }}>
      <span style={{ width: 46 }}>{label}</span>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={`${label.toLowerCase()} model`}
        style={compactInputStyle}
      />
    </label>
  );
}

function downloadStatusText(status: LmStudioDownloadStatus): string {
  if (status.totalSizeBytes && status.downloadedBytes) {
    const pct = Math.round((status.downloadedBytes / status.totalSizeBytes) * 100);
    return `${status.jobId ?? "download"} · ${status.status} · ${pct}%`;
  }
  return `${status.jobId ?? "download"} · ${status.status}`;
}

function lmUsageText(usage: LmStudioRunUsage): string {
  const stats = usage.stats;
  if (!stats) return usage.responseId ? "stateful" : "native";
  const bits: string[] = [];
  if (typeof stats.input_tokens === "number") bits.push(`in ${stats.input_tokens}`);
  if (typeof stats.total_output_tokens === "number") bits.push(`out ${stats.total_output_tokens}`);
  if (typeof stats.reasoning_output_tokens === "number" && stats.reasoning_output_tokens > 0) {
    bits.push(`r ${stats.reasoning_output_tokens}`);
  }
  if (typeof stats.tokens_per_second === "number") bits.push(`${stats.tokens_per_second.toFixed(1)} tok/s`);
  if (typeof stats.time_to_first_token_seconds === "number") {
    bits.push(`ttft ${stats.time_to_first_token_seconds.toFixed(2)}s`);
  }
  return bits.length ? bits.join(" · ") : "native stats";
}
