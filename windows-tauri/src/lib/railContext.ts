import { useCallback, useEffect, useMemo, useState } from "react";
import { railTabsForContext } from "./commands";
import { LOOM_REFRESH_RUNS } from "./events";
import { ipc, type AgentGraphRunSummary, type Workspace } from "./ipc";
import type { Block } from "../modules/workspace/LayoutPersistence";

export type MemoryFile = {
  id: string;
  name: string;
  path: string;
  excerpt: string;
  characterCount: number;
};

export function useRightRailContext(workspace: Workspace | null, blocks: Pick<Block, "kind">[]) {
  const [runs, setRuns] = useState<AgentGraphRunSummary[]>([]);
  const [memoryFiles, setMemoryFiles] = useState<MemoryFile[]>([]);

  const refreshRuns = useCallback(() => {
    ipc.agentGraph.list().then(setRuns).catch(() => setRuns([]));
  }, []);

  useEffect(() => {
    refreshRuns();
    window.addEventListener(LOOM_REFRESH_RUNS, refreshRuns);
    return () => window.removeEventListener(LOOM_REFRESH_RUNS, refreshRuns);
  }, [refreshRuns]);

  useEffect(() => {
    let active = true;
    loadMemoryFiles(workspace).then((files) => {
      if (active) setMemoryFiles(files);
    });
    return () => {
      active = false;
    };
  }, [workspace?.id, workspace?.folderPath]);

  const scopedRuns = useMemo(() => filterRunsForWorkspace(runs, workspace), [runs, workspace?.folderPath]);
  const railTabs = useMemo(
    () => railTabsForContext({ workspace, blocks, runs: scopedRuns, hasMemoryFiles: memoryFiles.length > 0 }),
    [workspace?.id, workspace?.folderPath, workspace?.kindRaw, blocks, scopedRuns, memoryFiles.length]
  );

  return { runs, scopedRuns, memoryFiles, railTabs, refreshRuns };
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

async function loadMemoryFiles(workspace: Workspace | null): Promise<MemoryFile[]> {
  if (!workspace?.folderPath) return [];
  const names = ["CLAUDE.md", "AGENTS.md", "GUIDE.md", "README.md"];
  const files = await Promise.all(
    names.map(async (name) => {
      const path = joinPath(workspace.folderPath, name);
      try {
        const raw = await ipc.fs.read(path);
        const trimmed = raw.trim();
        if (!trimmed) return null;
        return {
          id: path,
          name,
          path,
          characterCount: trimmed.length,
          excerpt: trimmed.length > 420 ? `${trimmed.slice(0, 420)}...` : trimmed,
        };
      } catch {
        return null;
      }
    })
  );
  return files.filter((file): file is MemoryFile => Boolean(file));
}

function normalizedWorkspacePath(path?: string | null): string {
  return path?.trim().replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase() ?? "";
}

function joinPath(root: string, name: string): string {
  const sep = root.includes("\\") ? "\\" : "/";
  return `${root.replace(/[\\/]+$/, "")}${sep}${name}`;
}
