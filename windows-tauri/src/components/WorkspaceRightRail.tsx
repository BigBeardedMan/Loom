import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from "react";
import { Icons } from "../lib/icons";
import { ipc, type AgentDescriptor, type AgentGraphEvent, type AgentGraphRunSummary, type LiveAgentTaskGroup, type LocalEndpoint, type Workspace } from "../lib/ipc";
import { PANEL_META, ROOM_META } from "../lib/commands";
import { LOOM_ENDPOINTS_CHANGED } from "../lib/events";
import { useRightRailContext, type MemoryFile } from "../lib/railContext";
import { useApp, type Panel } from "../lib/store";
import { radius, surface, text, workspaceColorVar } from "../lib/theme";
import { defaultPreviewUrlFor } from "../modules/build/previewUrls";
import type { Block } from "../modules/workspace/LayoutPersistence";

export function WorkspaceRightRail() {
  const workspaces = useApp((s) => s.workspaces);
  const selectedId = useApp((s) => s.selectedWorkspaceId);
  const workspace = workspaces.find((w) => w.id === selectedId) ?? null;
  const layout = useApp((s) => s.layout);
  const activeBlockId = useApp((s) => s.activeBlockId);
  const selectedTab = useApp((s) => s.rightRailTab);
  const setSelectedTab = useApp((s) => s.setRightRailTab);
  const blocks = layout?.blocks ?? [];
  const activeBlock = layout?.blocks.find((b) => b.id === activeBlockId) ?? null;
  const { scopedRuns, memoryFiles, railTabs, refreshRuns: refreshRunSummaries } = useRightRailContext(workspace, blocks);
  const [liveGroups, setLiveGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [expandedRunId, setExpandedRunId] = useState<string | null>(null);
  const [loadingRunId, setLoadingRunId] = useState<string | null>(null);
  const [eventsByRun, setEventsByRun] = useState<Record<string, AgentGraphEvent[]>>({});
  const [agents, setAgents] = useState<AgentDescriptor[]>([]);
  const [endpoints, setEndpoints] = useState<LocalEndpoint[]>([]);

  const scopedLiveGroups = useMemo(() => filterLiveGroupsForWorkspace(liveGroups, workspace), [liveGroups, workspace?.folderPath]);
  const reviewableRuns = useMemo(() => scopedRuns.filter(isReviewableRun), [scopedRuns]);
  const reviewableRunKey = reviewableRuns.slice(0, 6).map((run) => run.id).join("|");
  const effectiveTab = railTabs.some((tab) => tab.tab === selectedTab) ? selectedTab : railTabs[0]?.tab ?? "details";

  const refreshRuns = () => {
    refreshRunSummaries();
    ipc.liveTasks.list().then(setLiveGroups).catch(() => setLiveGroups([]));
  };
  const refreshProviders = () => {
    ipc.agents.refresh().then(setAgents).catch(() => setAgents([]));
    ipc.endpoints.list().then(setEndpoints).catch(() => setEndpoints([]));
  };

  useEffect(() => {
    refreshRuns();
    refreshProviders();
    const id = setInterval(refreshRuns, 5000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    window.addEventListener(LOOM_ENDPOINTS_CHANGED, refreshProviders);
    return () => window.removeEventListener(LOOM_ENDPOINTS_CHANGED, refreshProviders);
  }, []);

  useEffect(() => {
    if (effectiveTab !== "diff" || reviewableRuns.length === 0) return;
    const missing = reviewableRuns.slice(0, 6).filter((run) => !eventsByRun[run.id]);
    if (missing.length === 0) return;

    let active = true;
    Promise.all(
      missing.map((run) =>
        ipc.agentGraph
          .read(run.id)
          .then((events) => [run.id, events] as const)
          .catch(() => [run.id, [] as AgentGraphEvent[]] as const)
      )
    ).then((entries) => {
      if (!active) return;
      setEventsByRun((current) => {
        const next = { ...current };
        for (const [runId, events] of entries) {
          if (!next[runId]) next[runId] = events;
        }
        return next;
      });
    });

    return () => {
      active = false;
    };
  }, [effectiveTab, reviewableRunKey]);

  return (
    <aside
      className="loom-right-rail flex h-full flex-col overflow-hidden"
      style={{
        width: "var(--loom-inspector-width, 308px)",
        flex: "0 0 var(--loom-inspector-width, 308px)",
        background: surface.shellInspector,
        border: `1px solid ${surface.hairline}`,
        borderRadius: 10,
      }}
    >
      <header
        className="flex items-center gap-2"
        style={{
          padding: "9px 12px",
          borderBottom: `1px solid ${surface.hairline}`,
        }}
      >
        <Icons.layers size={14} color={workspace ? workspaceColorVar[workspace.colorName] : workspaceColorVar.blue} />
        <div className="min-w-0 flex-1">
          <div className="truncate" style={{ fontSize: 12, fontWeight: 700, color: text.primary }}>
            {workspace?.name ?? "Inspector"}
          </div>
          <div className="truncate" style={{ fontSize: 10, color: text.muted }}>
            {activeBlock ? defaultBlockTitle(activeBlock) : "Adaptive context"}
          </div>
        </div>
        <button
          onClick={refreshRuns}
          title="Refresh rail data"
          style={{ padding: 4, borderRadius: 6, color: text.muted }}
        >
          <Icons.refresh size={12} strokeWidth={2.1} />
        </button>
      </header>

      <div className="flex gap-1 overflow-x-auto" style={{ padding: "8px 10px", borderBottom: `1px solid ${surface.hairline}` }}>
        {railTabs.map((tab) => {
          const Icon = Icons[tab.icon];
          const active = effectiveTab === tab.tab;
          return (
            <button
              key={tab.tab}
              onClick={() => setSelectedTab(tab.tab)}
              title={tab.label}
              aria-label={tab.label}
              style={{
                width: 26,
                height: 24,
                borderRadius: 7,
                display: "grid",
                placeItems: "center",
                background: active ? workspaceColorVar.blue : surface.softPanel,
                color: active ? "#fff" : text.muted,
              }}
            >
              <Icon size={12} strokeWidth={2.2} />
            </button>
          );
        })}
      </div>

      <main className="scrollbar-thin min-h-0 flex-1 overflow-y-auto" style={{ padding: 12 }}>
        <WorkflowMap workspace={workspace} runs={scopedRuns} liveGroups={scopedLiveGroups} />
        {effectiveTab === "timeline" && (
          <TimelineContent
            runs={scopedRuns}
            liveGroups={scopedLiveGroups}
            expandedRunId={expandedRunId}
            loadingRunId={loadingRunId}
            eventsByRun={eventsByRun}
            onToggle={(run) => {
              if (expandedRunId === run.id) {
                setExpandedRunId(null);
                return;
              }
              setExpandedRunId(run.id);
              if (eventsByRun[run.id]) return;
              setLoadingRunId(run.id);
              ipc.agentGraph
                .read(run.id)
                .then((events) => setEventsByRun((current) => ({ ...current, [run.id]: events })))
                .catch(() => setEventsByRun((current) => ({ ...current, [run.id]: [] })))
                .finally(() => setLoadingRunId((current) => (current === run.id ? null : current)));
            }}
          />
        )}
        {effectiveTab === "files" && <FilesContent workspace={workspace} memoryFiles={memoryFiles} />}
        {effectiveTab === "preview" && <PreviewContent workspace={workspace} blocks={blocks} />}
        {effectiveTab === "tools" && <ToolsContent blocks={blocks} agents={agents} endpoints={endpoints} />}
        {effectiveTab === "diff" && <DiffContent runs={scopedRuns} liveGroups={scopedLiveGroups} workspace={workspace} blocks={blocks} eventsByRun={eventsByRun} />}
        {effectiveTab === "memory" && <MemoryContent memoryFiles={memoryFiles} runs={scopedRuns} />}
        {effectiveTab === "details" && <DetailsContent workspace={workspace} block={activeBlock} blocks={blocks} />}
      </main>
    </aside>
  );
}

function WorkflowMap({
  workspace,
  runs,
  liveGroups,
}: {
  workspace: Workspace | null;
  runs: AgentGraphRunSummary[];
  liveGroups: LiveAgentTaskGroup[];
}) {
  const signals = workflowSignals(runs, liveGroups);
  const phases = [
    ["Scope", !!workspace, workspace ? workspaceColorVar[workspace.colorName] : workspaceColorVar.blue],
    ["Workspace", !!workspace?.folderPath, workspaceColorVar.blue],
    ["Agents", signals.hasActiveAgents, workspaceColorVar.purple],
    ["Checks", signals.hasCheckSignals, workspaceColorVar.green],
    ["Review", signals.hasReviewSignals, signals.hasAttention ? workspaceColorVar.orange : workspaceColorVar.green],
    ["Ship", signals.shipReady, workspaceColorVar.green],
  ] as const;

  return (
    <section style={sectionBox}>
      <SectionTitle>Workflow</SectionTitle>
      <div className="grid grid-cols-6 gap-1">
        {phases.map(([label, active, color]) => (
          <div key={label} className="min-w-0 text-center">
            <span
              style={{
                display: "inline-block",
                width: 7,
                height: 7,
                borderRadius: 999,
                background: active ? color : surface.hairline,
              }}
            />
            <div className="truncate" style={{ fontSize: 8, fontWeight: 700, color: active ? text.primary : text.tertiary }}>
              {label}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

function TimelineContent({
  runs,
  liveGroups,
  expandedRunId,
  loadingRunId,
  eventsByRun,
  onToggle,
}: {
  runs: AgentGraphRunSummary[];
  liveGroups: LiveAgentTaskGroup[];
  expandedRunId: string | null;
  loadingRunId: string | null;
  eventsByRun: Record<string, AgentGraphEvent[]>;
  onToggle: (run: AgentGraphRunSummary) => void;
}) {
  return (
    <>
      <RailSection title="Live Runs">
        {liveGroups.length === 0 ? (
          <Muted>No live agent task groups are active.</Muted>
        ) : (
          liveGroups.slice(0, 6).map((group) => (
            <RailRow
              key={group.id}
              icon="workflow"
              color={workspaceColorVar.green}
              title={liveGroupTitle(group)}
              detail={group.headline || `${group.tasks.length} tasks`}
            />
          ))
        )}
      </RailSection>
      <RailSection title="Recent History">
        {runs.length === 0 ? (
          <Muted>No graph ledgers found under ~/.loom/agent-runs.</Muted>
        ) : (
          runs.slice(0, 8).map((run) => {
            const expanded = expandedRunId === run.id;
            const events = eventsByRun[run.id] ?? [];
            const evidence = runEvidence(events);
            return (
              <section key={run.id} style={sectionBox}>
                <button
                  type="button"
                  className="w-full text-left"
                  onClick={() => onToggle(run)}
                  style={{ border: 0, background: "transparent", color: "inherit", padding: 0 }}
                >
                  <RailRow
                    icon={run.status === "completed" ? "checkCircle" : run.status === "failed" ? "failedCircle" : "workflow"}
                    color={run.status === "completed" ? workspaceColorVar.green : run.status === "failed" ? workspaceColorVar.orange : workspaceColorVar.blue}
                    title={run.title}
                    detail={summaryChips(run).join(" - ")}
                  />
                </button>
                {expanded && (
                  <div style={{ marginTop: 8, paddingTop: 8, borderTop: `1px solid ${surface.hairline}` }}>
                    {loadingRunId === run.id ? (
                      <Muted>Loading ledger events...</Muted>
                    ) : events.length === 0 ? (
                      <Muted>No ledger events found.</Muted>
                    ) : (
                      events.slice(-5).reverse().map((event) => (
                        <div key={event.eventId} style={{ marginTop: 6 }}>
                          <RailRow
                            icon={eventIcon(event.type)}
                            color={eventColor(event)}
                            title={event.type}
                            detail={eventDetail(event)}
                          />
                        </div>
                      ))
                    )}
                    {evidence.length > 0 && (
                      <div style={{ marginTop: 10 }}>
                        <SectionTitle>Evidence</SectionTitle>
                        <div className="flex flex-col gap-2">
                          {evidence.map((item) => (
                            <RailRow key={item.id} icon={item.icon} color={item.color} title={item.title} detail={item.detail} />
                          ))}
                        </div>
                      </div>
                    )}
                    <div style={{ marginTop: 10 }}>
                      <CodeLine>{displayPath(run.ledgerPath)}</CodeLine>
                      <LedgerActions run={run} />
                    </div>
                  </div>
                )}
              </section>
            );
          })
        )}
      </RailSection>
    </>
  );
}

function FilesContent({ workspace, memoryFiles }: { workspace: Workspace | null; memoryFiles: MemoryFile[] }) {
  return (
    <RailSection title="Project Files">
      {!workspace?.folderPath ? (
        <Muted>Bind this room to a folder to show project context.</Muted>
      ) : (
        <>
          <CodeLine>{workspace.folderPath}</CodeLine>
          <FolderActions path={workspace.folderPath} label={ROOM_META[workspace.kindRaw]?.label ?? workspace.name} />
          {memoryFiles.length === 0 ? (
            <Muted>No agent memory files found in this folder.</Muted>
          ) : (
            memoryFiles.map((file) => (
              <section key={file.id} style={sectionBox}>
                <RailRow icon="file" color={workspaceColorVar.blue} title={file.name} detail={`${file.characterCount} chars`} />
                <MemoryFileActions file={file} />
              </section>
            ))
          )}
        </>
      )}
    </RailSection>
  );
}

function PreviewContent({ workspace, blocks }: { workspace: Workspace | null; blocks: Block[] }) {
  const previews = blocks.filter((b) => b.kind === "preview");
  return (
    <RailSection title="Previews">
      {previews.length === 0 ? (
        <Muted>No Preview panes are open in this room.</Muted>
      ) : (
        previews.map((block) => {
          const url = previewUrlForBlock(workspace, block);
          const title = defaultBlockTitle(block);
          return (
            <section key={block.id} style={sectionBox}>
              <RailRow icon="eye" color={workspaceColorVar.pink} title={title} detail={url} />
              <PreviewActions url={url} label={title} />
            </section>
          );
        })
      )}
    </RailSection>
  );
}

function ToolsContent({
  blocks,
  agents,
  endpoints,
}: {
  blocks: Block[];
  agents: AgentDescriptor[];
  endpoints: LocalEndpoint[];
}) {
  const counts = useMemo(() => {
    const next = new Map<Panel, number>();
    for (const block of blocks) next.set(block.kind, (next.get(block.kind) ?? 0) + 1);
    return Array.from(next.entries());
  }, [blocks]);
  return (
    <RailSection title="Tools">
      {counts.map(([kind, count]) => (
        <RailRow key={kind} icon={PANEL_META[kind].icon} color={PANEL_META[kind].color} title={PANEL_META[kind].label} detail={`${count} open`} />
      ))}
      <SectionTitle>Local Endpoints</SectionTitle>
      {endpoints.length === 0 ? (
        <Muted>No local providers configured. Add Ollama, LM Studio, or OpenAI-compatible endpoints in Settings.</Muted>
      ) : (
        endpoints.map((endpoint) => (
          <RailRow
            key={endpoint.id}
            icon="server"
            color={endpoint.kind === "lmstudio" ? workspaceColorVar.purple : workspaceColorVar.blue}
            title={endpoint.name}
            detail={`${endpoint.kind} - ${endpoint.defaultModel || endpoint.baseUrl}`}
          />
        ))
      )}
      <SectionTitle>Agents</SectionTitle>
      {agents.length === 0 ? (
        <Muted>No CLI agents reported by the registry.</Muted>
      ) : (
        agents.slice(0, 6).map((agent) => (
          <RailRow
            key={`${agent.scope}:${agent.name}`}
            icon="sparkles"
            color={agent.color || workspaceColorVar.orange}
            title={agent.name || "Default"}
            detail={agent.model || agent.description || agent.scope}
          />
        ))
      )}
    </RailSection>
  );
}

function DiffContent({
  runs,
  liveGroups,
  workspace,
  blocks,
  eventsByRun,
}: {
  runs: AgentGraphRunSummary[];
  liveGroups: LiveAgentTaskGroup[];
  workspace: Workspace | null;
  blocks: Block[];
  eventsByRun: Record<string, AgentGraphEvent[]>;
}) {
  const reviewable = runs.filter(isReviewableRun);
  const previews = blocks.filter((block) => block.kind === "preview");
  const decision = shipDecision(runs, liveGroups);
  const packet = reviewPacketRows(reviewable, eventsByRun, previews);
  const changedFiles = changedFilesFromReviewEvents(reviewable, eventsByRun);
  return (
    <>
      <RailSection title="Review Packet">
        {packet.length === 0 ? (
          <Muted>No run, check, worktree, or handoff evidence has been recorded yet.</Muted>
        ) : (
          packet.map((item) => (
            <RailRow key={item.id} icon={item.icon} color={item.color} title={item.title} detail={item.detail} />
          ))
        )}
      </RailSection>
      <RailSection title="Ship Decision">
        <RailRow icon={decision.icon} color={decision.color} title={decision.title} detail={decision.detail} />
      </RailSection>
      <RailSection title="Changed Files">
        {changedFiles.length === 0 ? (
          <Muted>No changed-file list has been recorded yet.</Muted>
        ) : (
          changedFiles.slice(0, 8).map((path) => (
            <section key={path} style={sectionBox}>
              <RailRow icon="file" color={workspaceColorVar.blue} title={reviewPathBaseName(path)} detail={path} />
              <ChangedFileActions path={path} workspace={workspace} />
            </section>
          ))
        )}
      </RailSection>
      <RailSection title="Review Signals">
        {reviewable.length === 0 ? (
          <Muted>No changed-file or check signals have been recorded yet.</Muted>
        ) : (
          reviewable.slice(0, 8).map((run) => (
            <RailRow
              key={run.id}
              icon="diff"
              color={run.gitDirty ? workspaceColorVar.orange : workspaceColorVar.green}
              title={run.gitBranch || run.title}
              detail={run.gitHead || `${run.toolEventCount ?? 0} tool events`}
            />
          ))
        )}
      </RailSection>
      <RailSection title="Preview Status">
        {previews.length === 0 ? (
          <Muted>No Preview panes are open in this room.</Muted>
        ) : (
          previews.slice(0, 3).map((block) => {
            const url = previewUrlForBlock(workspace, block);
            const title = defaultBlockTitle(block);
            return (
              <section key={block.id} style={sectionBox}>
                <RailRow icon="eye" color={workspaceColorVar.pink} title={title} detail={url} />
                <PreviewActions url={url} label={title} />
              </section>
            );
          })
        )}
      </RailSection>
    </>
  );
}

function MemoryContent({ memoryFiles, runs }: { memoryFiles: MemoryFile[]; runs: AgentGraphRunSummary[] }) {
  return (
    <>
      <RailSection title="Read-only Memory">
        {memoryFiles.length === 0 ? (
          <Muted>No CLAUDE.md, AGENTS.md, GUIDE.md, or README.md found for this workspace.</Muted>
        ) : (
          memoryFiles.map((file) => (
            <section key={file.id} style={sectionBox}>
              <RailRow icon="brain" color={workspaceColorVar.purple} title={file.name} detail={file.path} />
              <p style={{ marginTop: 6, fontSize: 10, lineHeight: 1.45, color: text.muted }}>
                {file.excerpt}
              </p>
              <MemoryFileActions file={file} />
            </section>
          ))
        )}
      </RailSection>
      <RailSection title="Run Ledger Summaries">
        {runs.length === 0 ? (
          <Muted>No graph ledger summaries found under ~/.loom/agent-runs.</Muted>
        ) : (
          runs.slice(0, 5).map((run) => (
            <section key={run.id} style={sectionBox}>
              <RailRow icon={runStatusIcon(run.status)} color={runStatusColor(run.status)} title={run.title} detail={summaryChips(run).join(" · ")} />
              <CodeLine>{displayPath(run.ledgerPath)}</CodeLine>
              <LedgerActions run={run} />
            </section>
          ))
        )}
      </RailSection>
    </>
  );
}

function DetailsContent({ workspace, block, blocks }: { workspace: Workspace | null; block: Block | null; blocks: Block[] }) {
  return (
    <RailSection title="Details">
      {workspace && (
        <RailRow
          icon="layers"
          color={workspaceColorVar[workspace.colorName]}
          title={workspace.name}
          detail={ROOM_META[workspace.kindRaw]?.label ?? workspace.kindRaw}
        />
      )}
      {block ? (
        <RailRow icon={PANEL_META[block.kind].icon} color={PANEL_META[block.kind].color} title={defaultBlockTitle(block)} detail={PANEL_META[block.kind].label} />
      ) : (
        <Muted>Select a pane to inspect it.</Muted>
      )}
      <Muted>{blocks.length} pane(s) open in this room.</Muted>
    </RailSection>
  );
}

function RailSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section style={{ marginTop: 12 }}>
      <SectionTitle>{title}</SectionTitle>
      <div className="flex flex-col gap-2">{children}</div>
    </section>
  );
}

function SectionTitle({ children }: { children: ReactNode }) {
  return <div style={{ marginBottom: 7, fontSize: 9, fontWeight: 800, color: text.tertiary, textTransform: "uppercase" }}>{children}</div>;
}

function RailRow({ icon, color, title, detail }: { icon: keyof typeof Icons; color: string; title: string; detail?: string }) {
  const Icon = Icons[icon];
  return (
    <div className="flex min-w-0 gap-2">
      <Icon size={13} strokeWidth={2.2} color={color} style={{ flex: "0 0 auto", marginTop: 2 }} />
      <div className="min-w-0 flex-1">
        <div className="truncate" style={{ fontSize: 11, fontWeight: 700, color: text.primary }}>{title}</div>
        {detail && <div className="line-clamp-2" style={{ fontSize: 9, color: text.muted }}>{detail}</div>}
      </div>
    </div>
  );
}

function Muted({ children }: { children: ReactNode }) {
  return <div style={{ fontSize: 10, lineHeight: 1.45, color: text.muted }}>{children}</div>;
}

function CodeLine({ children }: { children: ReactNode }) {
  return (
    <div className="truncate" style={{ padding: 8, borderRadius: radius.row, background: surface.inset, fontSize: 10, fontFamily: "var(--font-mono)", color: text.muted }}>
      {children}
    </div>
  );
}

function FolderActions({ path, label }: { path: string; label: string }) {
  const copyPath = () => void navigator.clipboard?.writeText(path);
  const revealPath = () => void ipc.fs.reveal(path);

  return (
    <div className="flex items-center gap-1.5" style={{ marginTop: 7 }}>
      <RailActionButton title={`Copy ${label} folder path`} onClick={copyPath}>
        <Icons.copy size={11} strokeWidth={2.2} />
        Copy
      </RailActionButton>
      <RailActionButton title={`Reveal ${label} folder`} onClick={revealPath}>
        <Icons.folderOpen size={11} strokeWidth={2.2} />
        Reveal
      </RailActionButton>
    </div>
  );
}

function PreviewActions({ url, label }: { url: string; label: string }) {
  const copyUrl = () => void navigator.clipboard?.writeText(url);
  const openUrl = () => void window.open(url, "_blank", "noopener,noreferrer");

  return (
    <div className="flex items-center gap-1.5" style={{ marginTop: 7 }}>
      <RailActionButton title={`Copy ${label} preview URL`} onClick={copyUrl}>
        <Icons.copy size={11} strokeWidth={2.2} />
        Copy
      </RailActionButton>
      <RailActionButton title={`Open ${label} preview`} onClick={openUrl}>
        <Icons.go size={11} strokeWidth={2.2} />
        Open
      </RailActionButton>
    </div>
  );
}

function ChangedFileActions({ path, workspace }: { path: string; workspace: Workspace | null }) {
  const resolved = resolveReviewPath(workspace, path);
  const label = reviewPathBaseName(path);
  const copyPath = () => void navigator.clipboard?.writeText(resolved);
  const openPath = () => void ipc.shell.open(resolved);
  const revealPath = () => void ipc.fs.reveal(resolved);

  return (
    <div className="flex items-center gap-1.5" style={{ marginTop: 7 }}>
      <RailActionButton title={`Copy ${label} path`} onClick={copyPath}>
        <Icons.copy size={11} strokeWidth={2.2} />
        Copy
      </RailActionButton>
      <RailActionButton title={`Open ${label}`} onClick={openPath}>
        <Icons.file size={11} strokeWidth={2.2} />
        Open
      </RailActionButton>
      <RailActionButton title={`Reveal ${label}`} onClick={revealPath}>
        <Icons.folderOpen size={11} strokeWidth={2.2} />
        Reveal
      </RailActionButton>
    </div>
  );
}

function MemoryFileActions({ file }: { file: MemoryFile }) {
  const copyPath = () => void navigator.clipboard?.writeText(file.path);
  const openPath = () => void ipc.shell.open(file.path);
  const revealPath = () => void ipc.fs.reveal(file.path);

  return (
    <div className="flex items-center gap-1.5" style={{ marginTop: 7 }}>
      <RailActionButton title={`Copy ${file.name} path`} onClick={copyPath}>
        <Icons.copy size={11} strokeWidth={2.2} />
        Copy
      </RailActionButton>
      <RailActionButton title={`Open ${file.name}`} onClick={openPath}>
        <Icons.file size={11} strokeWidth={2.2} />
        Open
      </RailActionButton>
      <RailActionButton title={`Reveal ${file.name}`} onClick={revealPath}>
        <Icons.folderOpen size={11} strokeWidth={2.2} />
        Reveal
      </RailActionButton>
    </div>
  );
}

function LedgerActions({ run }: { run: AgentGraphRunSummary }) {
  const copyLedgerPath = () => void navigator.clipboard?.writeText(run.ledgerPath);
  const revealLedger = () => void ipc.agentGraph.reveal(run.id);

  return (
    <div className="flex items-center gap-1.5" style={{ marginTop: 6 }}>
      <RailActionButton title="Copy ledger path" onClick={copyLedgerPath}>
        <Icons.copy size={11} strokeWidth={2.2} />
        Copy
      </RailActionButton>
      <RailActionButton title="Reveal ledger" onClick={revealLedger}>
        <Icons.folderOpen size={11} strokeWidth={2.2} />
        Reveal
      </RailActionButton>
    </div>
  );
}

function RailActionButton({
  title,
  onClick,
  children,
}: {
  title: string;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      title={title}
      onClick={onClick}
      className="flex items-center gap-1"
      style={{
        padding: "4px 8px",
        borderRadius: 7,
        border: `1px solid ${surface.hairline}`,
        background: "color-mix(in srgb, " + surface.softPanel + ", transparent 35%)",
        color: text.muted,
        fontSize: 9,
        fontWeight: 700,
      }}
    >
      {children}
    </button>
  );
}

const sectionBox: CSSProperties = {
  padding: 10,
  borderRadius: radius.row,
  background: surface.inset,
};

function defaultBlockTitle(block: Block): string {
  if (block.customTitle?.trim()) return block.customTitle.trim();
  if (block.kind === "chat" && block.autoChatIndex) return block.autoChatIndex === 1 ? "Chat" : `Chat ${block.autoChatIndex}`;
  return PANEL_META[block.kind].label;
}

function previewUrlForBlock(workspace: Workspace | null, block: Block): string {
  return workspace
    ? defaultPreviewUrlFor(workspace, block.autoPreviewIndex ?? 0)
    : `http://localhost:${3000 + (block.autoPreviewIndex ?? 0)}`;
}

function summaryChips(run: AgentGraphRunSummary): string[] {
  return [
    run.status,
    run.modelLabel,
    run.gitBranch,
    (run.toolEventCount ?? 0) > 0 ? `${run.toolEventCount} tools` : null,
    (run.taskCount ?? 0) > 0 ? `${run.taskCount} tasks` : null,
    (run.childRunCount ?? 0) > 0 ? `${run.childRunCount} child runs` : null,
    (run.parentRunIds?.length ?? 0) > 0 ? `${run.parentRunIds?.length ?? 0} parents` : null,
  ].filter(Boolean) as string[];
}

function runStatusIcon(status: string): keyof typeof Icons {
  switch (status.toLowerCase()) {
    case "completed":
      return "checkCircle";
    case "failed":
    case "cancelled":
      return "failedCircle";
    default:
      return "workflow";
  }
}

function runStatusColor(status: string): string {
  switch (status.toLowerCase()) {
    case "completed":
      return workspaceColorVar.green;
    case "failed":
    case "cancelled":
      return workspaceColorVar.orange;
    default:
      return workspaceColorVar.blue;
  }
}

function eventIcon(type: string): keyof typeof Icons {
  switch (type) {
    case "run.completed":
    case "spawn.completed":
      return "checkCircle";
    case "run.failed":
    case "run.cancelled":
    case "spawn.failed":
      return "failedCircle";
    case "tool.started":
    case "tool.completed":
      return "terminal";
    case "handoff.written":
    case "handoff.accepted":
    case "handoff.rejected":
      return "rerun";
    case "attention.requested":
    case "andon.paused":
      return "failedCircle";
    default:
      return "listBulletRect";
  }
}

function eventColor(event: AgentGraphEvent): string {
  switch (event.type) {
    case "run.completed":
    case "spawn.completed":
    case "handoff.accepted":
      return workspaceColorVar.green;
    case "run.failed":
    case "run.cancelled":
    case "spawn.failed":
    case "handoff.rejected":
    case "attention.requested":
    case "andon.paused":
      return workspaceColorVar.orange;
    case "tool.completed":
      return event.payload?.status === "failed" ? workspaceColorVar.orange : workspaceColorVar.green;
    case "tool.started":
      return workspaceColorVar.purple;
    default:
      return workspaceColorVar.blue;
  }
}

function eventDetail(event: AgentGraphEvent): string {
  return compact(
    event.summary ||
      event.title ||
      event.payload?.tool ||
      event.payload?.status ||
      event.payload?.subject ||
      event.payload?.taskID ||
      event.payload?.path ||
      event.occurredAt
  );
}

type RunEvidence = {
  id: string;
  icon: keyof typeof Icons;
  color: string;
  title: string;
  detail?: string;
};

function runEvidence(events: AgentGraphEvent[]): RunEvidence[] {
  const newest = [...events].sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
  const evidence: RunEvidence[] = [];

  const review = newest.find((event) => payloadValue(event, ["reviewSummary", "review"]));
  const reviewDetail = review ? payloadValue(review, ["reviewSummary", "review"]) : null;
  if (reviewDetail) {
    evidence.push({ id: "review", icon: "file", color: workspaceColorVar.purple, title: "Review ready", detail: reviewDetail });
  }

  const failedTool = newest.find((event) => event.type === "tool.completed" && event.payload?.status === "failed");
  if (failedTool) {
    const tool = failedTool.payload?.tool || failedTool.title || "Tool";
    evidence.push({
      id: "failed-tool",
      icon: "failedCircle",
      color: workspaceColorVar.orange,
      title: `${tool} failed`,
      detail: compact(failedTool.summary || failedTool.payload?.status || "Tool needs attention."),
    });
  }

  const preview = newest.find((event) => (event.payload?.tool || event.title) === "preview_snapshot");
  if (preview) {
    evidence.push({
      id: "preview",
      icon: "eye",
      color: workspaceColorVar.pink,
      title: "Preview check",
      detail: compact(preview.summary || preview.payload?.status || "Preview snapshot recorded."),
    });
  }

  const handoff = newest.find((event) => ["handoff.written", "handoff.accepted", "handoff.rejected"].includes(event.type));
  if (handoff) {
    evidence.push({
      id: "handoff",
      icon: "rerun",
      color: eventColor(handoff),
      title: handoffTitle(handoff.type),
      detail: compact(handoff.summary || handoff.payload?.reviewSummary || handoff.title || "Handoff signal recorded."),
    });
  }

  const git = newest.find((event) => event.payload?.gitBranch || event.payload?.gitHead || event.payload?.gitDirty);
  if (git?.payload) {
    const gitParts = [
      git.payload.gitBranch,
      git.payload.gitHead,
      git.payload.gitDirty ? (git.payload.gitDirty === "true" ? "dirty" : "clean") : null,
    ].filter(Boolean) as string[];
    evidence.push({
      id: "git",
      icon: "diff",
      color: git.payload.gitDirty === "true" ? workspaceColorVar.orange : workspaceColorVar.green,
      title: "Git state",
      detail: gitParts.join(" - "),
    });
  }

  const attention = newest.find((event) => ["attention.requested", "andon.paused", "run.failed"].includes(event.type));
  if (attention) {
    evidence.push({
      id: "attention",
      icon: "failedCircle",
      color: workspaceColorVar.orange,
      title: "Attention needed",
      detail: compact(attention.summary || attention.title || attention.payload?.status || attention.type),
    });
  }

  return evidence.slice(0, 5);
}

function reviewPacketRows(
  runs: AgentGraphRunSummary[],
  eventsByRun: Record<string, AgentGraphEvent[]>,
  previews: Block[]
): RunEvidence[] {
  if (runs.length === 0) return [];

  const loadedEvents = runs
    .flatMap((run) => eventsByRun[run.id] ?? [])
    .sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
  const failedEvents = loadedEvents.filter(isAttentionEvent);
  const handoffEvents = loadedEvents.filter((event) =>
    ["handoff.written", "handoff.accepted", "handoff.rejected"].includes(event.type)
  );
  const previewEvents = loadedEvents.filter((event) => (event.payload?.tool || event.title) === "preview_snapshot");
  const toolNames = uniqueSorted([
    ...runs.flatMap((run) => run.toolNames ?? []),
    ...loadedEvents.map((event) => event.payload?.tool).filter(Boolean),
  ]);
  const toolEventCount = runs.reduce((total, run) => total + (run.toolEventCount ?? 0), 0);
  const completed = runs.filter((run) => run.status === "completed").length;
  const failed = runs.filter((run) => run.status === "failed" || run.status === "cancelled").length;
  const running = Math.max(0, runs.length - completed - failed);
  const branches = uniqueSorted(runs.map((run) => run.gitBranch).filter(Boolean));
  const dirtyCount = runs.filter((run) => run.gitDirty === true).length;
  const parentRunCount = uniqueSorted(runs.flatMap((run) => run.parentRunIds ?? [])).length;
  const childRunCount = runs.reduce((total, run) => total + (run.childRunCount ?? 0), 0);
  const lineageEventCount = runs.reduce((total, run) => total + (run.lineageEventCount ?? 0), 0);

  const rows: RunEvidence[] = [
    {
      id: "coverage",
      icon: "layers",
      color: failed > 0 ? workspaceColorVar.orange : workspaceColorVar.green,
      title: "Run coverage",
      detail: `${runs.length} runs - ${completed} complete - ${running} running - ${failed} blocked`,
    },
    {
      id: "checks",
      icon: "checkCircle",
      color: failedEvents.length === 0 ? workspaceColorVar.green : workspaceColorVar.orange,
      title: "Checks",
      detail:
        toolEventCount > 0
          ? `${toolEventCount} tool events - ${limitedList(toolNames, "tools recorded")}`
          : "No tool checks recorded yet.",
    },
  ];

  if (parentRunCount > 0 || childRunCount > 0 || lineageEventCount > 0) {
    rows.push({
      id: "lineage",
      icon: "workflow",
      color: workspaceColorVar.purple,
      title: "Lineage",
      detail: lineageSummary(parentRunCount, childRunCount, lineageEventCount),
    });
  }

  const failedEvent = failedEvents[0];
  if (failedEvent) {
    rows.push({
      id: "failed-evidence",
      icon: "failedCircle",
      color: workspaceColorVar.orange,
      title: `${failedEvents.length} attention signal${failedEvents.length === 1 ? "" : "s"}`,
      detail: compact(failedEvent.summary || failedEvent.title || failedEvent.payload?.tool || failedEvent.type),
    });
  }

  if (branches.length > 0 || runs.some((run) => run.gitDirty !== undefined && run.gitDirty !== null)) {
    rows.push({
      id: "worktrees",
      icon: "diff",
      color: dirtyCount > 0 ? workspaceColorVar.orange : workspaceColorVar.green,
      title: "Worktrees",
      detail: `${limitedList(branches, "no branch")} - ${dirtyCount > 0 ? `${dirtyCount} dirty` : "clean"}`,
    });
  }

  const handoff = handoffEvents[0];
  if (handoff) {
    rows.push({
      id: "handoffs",
      icon: "rerun",
      color: eventColor(handoff),
      title: `${handoffEvents.length} handoff${handoffEvents.length === 1 ? "" : "s"}`,
      detail: compact(handoff.summary || handoff.payload?.reviewSummary || handoff.title || handoffTitle(handoff.type)),
    });
  }

  const preview = previewEvents[0];
  if (preview) {
    rows.push({
      id: "preview-evidence",
      icon: "eye",
      color: workspaceColorVar.pink,
      title: "Preview evidence",
      detail: compact(preview.summary || preview.payload?.status || "Preview snapshot recorded."),
    });
  } else if (previews.length > 0) {
    rows.push({
      id: "preview-panes",
      icon: "eye",
      color: workspaceColorVar.pink,
      title: "Preview evidence",
      detail: `${previews.length} Preview pane${previews.length === 1 ? "" : "s"} open for manual checks.`,
    });
  }

  return rows.slice(0, 6);
}

function changedFilesFromReviewEvents(
  runs: AgentGraphRunSummary[],
  eventsByRun: Record<string, AgentGraphEvent[]>
): string[] {
  const seen = new Set<string>();
  const files: string[] = [];
  const events = runs
    .flatMap((run) => eventsByRun[run.id] ?? [])
    .sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
  for (const event of events) {
    const texts = [event.payload?.reviewSummary, event.payload?.review, event.summary].filter(
      (value): value is string => Boolean(value)
    );
    for (const textValue of texts) {
      for (const path of changedFilesInReviewText(textValue)) {
        if (seen.has(path)) continue;
        seen.add(path);
        files.push(path);
      }
    }
  }
  return files;
}

function changedFilesInReviewText(textValue: string): string[] {
  const files: string[] = [];
  let inChangedFiles = false;
  for (const rawLine of textValue.split("\n")) {
    const line = rawLine.trim();
    if (line === "Changed files:") {
      inChangedFiles = true;
      continue;
    }
    if (!inChangedFiles) continue;
    if (!line) break;
    if (!line.startsWith("- ")) break;
    const path = line.slice(2).trim();
    if (!path || path.startsWith("…and")) continue;
    files.push(path);
  }
  return files;
}

function reviewPathBaseName(path: string): string {
  const trimmed = path.replace(/[\\/]+$/, "");
  return trimmed.split(/[\\/]/).pop() || trimmed;
}

function resolveReviewPath(workspace: Workspace | null, path: string): string {
  const trimmed = path.trim();
  if (!trimmed || isAbsoluteLikePath(trimmed) || trimmed.startsWith("~")) return trimmed;
  const root = workspace?.folderPath?.replace(/[\\/]+$/, "");
  if (!root) return trimmed;
  const separator = root.includes("\\") ? "\\" : "/";
  return `${root}${separator}${trimmed.replace(/^[\\/]+/, "")}`;
}

function isAbsoluteLikePath(path: string): boolean {
  return /^([A-Za-z]:[\\/]|\\\\|\/)/.test(path);
}

function isReviewableRun(run: AgentGraphRunSummary): boolean {
  return Boolean(
    run.gitBranch ||
      run.gitDirty !== undefined ||
      run.gitHead ||
      (run.toolEventCount ?? 0) > 0 ||
      (run.taskCount ?? 0) > 0 ||
      (run.toolNames?.length ?? 0) > 0 ||
      (run.parentRunIds?.length ?? 0) > 0 ||
      (run.childRunCount ?? 0) > 0 ||
      (run.lineageEventCount ?? 0) > 0
  );
}

function isAttentionEvent(event: AgentGraphEvent): boolean {
  return (
    event.type === "run.failed" ||
    event.type === "spawn.failed" ||
    event.type === "handoff.rejected" ||
    event.type === "attention.requested" ||
    event.type === "andon.paused" ||
    (event.type === "tool.completed" && event.payload?.status === "failed")
  );
}

function uniqueSorted(values: (string | null | undefined)[]): string[] {
  return Array.from(new Set(values.map((value) => value?.trim()).filter(Boolean) as string[])).sort();
}

function limitedList(values: string[], empty: string, limit = 3): string {
  if (values.length === 0) return empty;
  const visible = values.slice(0, limit).join(", ");
  const remaining = values.length - Math.min(values.length, limit);
  return remaining > 0 ? `${visible} +${remaining}` : visible;
}

function lineageSummary(parentRunCount: number, childRunCount: number, eventCount: number): string {
  const parts = [
    childRunCount > 0 ? `${childRunCount} child run${childRunCount === 1 ? "" : "s"}` : null,
    parentRunCount > 0 ? `${parentRunCount} parent${parentRunCount === 1 ? "" : "s"}` : null,
    eventCount > 0 ? `${eventCount} lineage event${eventCount === 1 ? "" : "s"}` : null,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" - ") : "No lineage edges recorded.";
}

function payloadValue(event: AgentGraphEvent, keys: string[]): string | null {
  for (const key of keys) {
    const value = event.payload?.[key];
    if (value?.trim()) return compact(value);
  }
  return null;
}

function compact(raw: string, limit = 180): string {
  const value = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ")
    .trim();
  return value.length > limit ? `${value.slice(0, limit)}...` : value;
}

function handoffTitle(type: string): string {
  switch (type) {
    case "handoff.accepted":
      return "Handoff accepted";
    case "handoff.rejected":
      return "Handoff rejected";
    default:
      return "Handoff written";
  }
}

function displayPath(path: string): string {
  return path
    .replace(/^\/Users\/[^/]+/, "~")
    .replace(/^C:\\Users\\[^\\]+/i, "~");
}

type WorkflowSignals = {
  hasActiveAgents: boolean;
  hasCheckSignals: boolean;
  hasAttention: boolean;
  hasReviewSignals: boolean;
  shipReady: boolean;
};

function workflowSignals(runs: AgentGraphRunSummary[], liveGroups: LiveAgentTaskGroup[]): WorkflowSignals {
  const hasRunningRun = runs.some((run) => isRunningStatus(run.status));
  const hasActiveAgents = liveGroups.length > 0 || hasRunningRun;
  const hasCheckSignals = runs.some((run) => (run.toolEventCount ?? 0) > 0 || (run.toolNames?.length ?? 0) > 0);
  const hasAttention = runs.some((run) => isAttentionStatus(run.status) || run.gitDirty === true);
  const hasCompletedEvidence = runs.some(
    (run) =>
      isCompletedStatus(run.status) &&
      run.gitDirty !== true &&
      ((run.toolEventCount ?? 0) > 0 ||
        (run.taskCount ?? 0) > 0 ||
        (run.toolNames?.length ?? 0) > 0 ||
        (run.childRunCount ?? 0) > 0 ||
        (run.lineageEventCount ?? 0) > 0 ||
        Boolean(run.gitHead) ||
        Boolean(run.gitBranch))
  );
  return {
    hasActiveAgents,
    hasCheckSignals,
    hasAttention,
    hasReviewSignals: hasAttention || hasCompletedEvidence || hasCheckSignals,
    shipReady: hasCompletedEvidence && !hasAttention && !hasActiveAgents,
  };
}

function shipDecision(runs: AgentGraphRunSummary[], liveGroups: LiveAgentTaskGroup[]): {
  icon: keyof typeof Icons;
  color: string;
  title: string;
  detail: string;
} {
  const signals = workflowSignals(runs, liveGroups);
  if (signals.shipReady) {
    return {
      icon: "checkCircle",
      color: workspaceColorVar.green,
      title: "Ready for review",
      detail: "Completed run with clean ledger signals.",
    };
  }
  if (signals.hasAttention) {
    return {
      icon: "failedCircle",
      color: workspaceColorVar.orange,
      title: "Attention needed",
      detail: "Failed, cancelled, or dirty run signals are present.",
    };
  }
  if (signals.hasActiveAgents) {
    return {
      icon: "workflow",
      color: workspaceColorVar.blue,
      title: "In progress",
      detail: "Live or running agents are still producing context.",
    };
  }
  if (signals.hasCheckSignals) {
    return {
      icon: "file",
      color: workspaceColorVar.purple,
      title: "Review pending",
      detail: "Tool and check signals are ready to inspect.",
    };
  }
  return {
    icon: "workflow",
    color: text.muted,
    title: "No ship signal",
    detail: "Runs will promote this once checks and review evidence land.",
  };
}

function isCompletedStatus(status: string): boolean {
  return status.toLowerCase() === "completed";
}

function isAttentionStatus(status: string): boolean {
  return ["failed", "cancelled"].includes(status.toLowerCase());
}

function isRunningStatus(status: string): boolean {
  return ["running", "pending", "in_progress", "in-progress"].includes(status.toLowerCase());
}

function filterLiveGroupsForWorkspace(liveGroups: LiveAgentTaskGroup[], workspace: Workspace | null): LiveAgentTaskGroup[] {
  if (!workspace?.folderPath) return liveGroups;
  const root = normalizedPath(workspace.folderPath);
  return liveGroups.filter((group) => {
    const candidate = normalizedPath(group.workspacePath);
    if (!candidate) return true;
    return candidate === root || candidate.startsWith(`${root}/`) || candidate.startsWith(`${root}\\`);
  });
}

function normalizedPath(path?: string | null): string {
  return path?.trim().replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase() ?? "";
}

function liveGroupTitle(group: LiveAgentTaskGroup): string {
  const source = String(group.source || "agent");
  return group.modelLabel ? `${source} - ${group.modelLabel}` : source;
}
