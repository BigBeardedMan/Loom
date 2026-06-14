import { useCallback, useEffect, useMemo, useState } from "react";
import { railTabsForContext } from "./commands";
import { LOOM_REFRESH_RUNS } from "./events";
import { ipc, type AgentGraphRunSummary, type LiveAgentTaskGroup, type Workspace } from "./ipc";
import { loadWorkspaceMemoryFiles, type MemoryFile } from "./projectMemory";
import type { Block } from "../modules/workspace/LayoutPersistence";

export type { MemoryFile } from "./projectMemory";

export function useRightRailContext(workspace: Workspace | null, blocks: Pick<Block, "kind">[]) {
  const [runs, setRuns] = useState<AgentGraphRunSummary[]>([]);
  const [liveGroups, setLiveGroups] = useState<LiveAgentTaskGroup[]>([]);
  const [memoryFiles, setMemoryFiles] = useState<MemoryFile[]>([]);

  const refreshRuns = useCallback(() => {
    ipc.agentGraph.list().then(setRuns).catch(() => setRuns([]));
    ipc.liveTasks.list().then(setLiveGroups).catch(() => setLiveGroups([]));
  }, []);

  useEffect(() => {
    refreshRuns();
    window.addEventListener(LOOM_REFRESH_RUNS, refreshRuns);
    return () => window.removeEventListener(LOOM_REFRESH_RUNS, refreshRuns);
  }, [refreshRuns]);

  useEffect(() => {
    let active = true;
    loadWorkspaceMemoryFiles(workspace).then((files) => {
      if (active) setMemoryFiles(files);
    });
    return () => {
      active = false;
    };
  }, [workspace?.id, workspace?.folderPath]);

  const scopedRuns = useMemo(() => filterRunsForWorkspace(runs, workspace), [runs, workspace?.folderPath]);
  const scopedLiveGroups = useMemo(() => filterLiveGroupsForWorkspace(liveGroups, workspace), [liveGroups, workspace?.folderPath]);
  const railTabs = useMemo(
    () => railTabsForContext({ workspace, blocks, runs: scopedRuns, hasMemoryFiles: memoryFiles.length > 0 }),
    [workspace?.id, workspace?.folderPath, workspace?.kindRaw, blocks, scopedRuns, memoryFiles.length]
  );

  return { runs, scopedRuns, liveGroups, scopedLiveGroups, memoryFiles, railTabs, refreshRuns };
}

export function filterRunsForWorkspace(runs: AgentGraphRunSummary[], workspace: Workspace | null): AgentGraphRunSummary[] {
  if (!workspace?.folderPath) return runs;
  const root = normalizedWorkspacePath(workspace.folderPath);
  return runs.filter((run) => {
    if (!run.workspacePath) return false;
    const candidate = normalizedWorkspacePath(run.workspacePath);
    return candidate === root || candidate.startsWith(`${root}/`) || candidate.startsWith(`${root}\\`);
  });
}

export function filterLiveGroupsForWorkspace(liveGroups: LiveAgentTaskGroup[], workspace: Workspace | null): LiveAgentTaskGroup[] {
  if (!workspace?.folderPath) return liveGroups;
  const root = normalizedWorkspacePath(workspace.folderPath);
  return liveGroups.filter((group) => {
    const candidate = normalizedWorkspacePath(group.workspacePath);
    if (!candidate) return true;
    return candidate === root || candidate.startsWith(`${root}/`) || candidate.startsWith(`${root}\\`);
  });
}

function normalizedWorkspacePath(path?: string | null): string {
  return path?.trim().replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase() ?? "";
}
