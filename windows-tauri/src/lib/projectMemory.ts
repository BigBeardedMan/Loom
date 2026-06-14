import { ipc, type FsNode, type Workspace } from "./ipc";

export type MemoryFile = {
  id: string;
  name: string;
  relativePath: string;
  path: string;
  excerpt: string;
  characterCount: number;
};

const MEMORY_CANDIDATES = ["CLAUDE.md", "AGENTS.md", "GUIDE.md", "README.md"];
const MEMORY_LOOKUP = new Set(MEMORY_CANDIDATES.map((name) => name.toLowerCase()));
const MEMORY_PRIORITY = new Map(MEMORY_CANDIDATES.map((name, index) => [name.toLowerCase(), index]));

export async function loadWorkspaceMemoryFiles(workspace: Pick<Workspace, "folderPath"> | null, maxFiles = 8): Promise<MemoryFile[]> {
  if (!workspace?.folderPath || maxFiles <= 0) return [];
  const root = workspace.folderPath;
  let tree: FsNode;
  try {
    tree = await ipc.fs.walk(root, 3, false);
  } catch {
    return [];
  }

  const candidates = flattenMemoryCandidates(tree, root);
  candidates.sort((a, b) => {
    if (a.componentCount !== b.componentCount) return a.componentCount - b.componentCount;
    if (a.priority !== b.priority) return a.priority - b.priority;
    return a.relativePath.localeCompare(b.relativePath);
  });

  const files: MemoryFile[] = [];
  const seen = new Set<string>();
  for (const candidate of candidates) {
    if (files.length >= maxFiles) break;
    const key = normalizePath(candidate.node.path);
    if (seen.has(key)) continue;
    seen.add(key);
    try {
      const raw = await ipc.fs.read(candidate.node.path);
      const trimmed = raw.trim();
      if (!trimmed) continue;
      files.push({
        id: candidate.node.path,
        name: candidate.node.name,
        relativePath: candidate.relativePath,
        path: candidate.node.path,
        characterCount: candidate.node.size || trimmed.length,
        excerpt: truncateText(trimmed, 420),
      });
    } catch {
      // Files can disappear between walk and read.
    }
  }
  return files;
}

export async function formatWorkspaceMemoryForPrompt(
  workspace: Pick<Workspace, "folderPath">,
  {
    maxPerFileChars = 1800,
    maxTotalChars = 5000,
  }: { maxPerFileChars?: number; maxTotalChars?: number } = {}
): Promise<string> {
  const files = await loadWorkspaceMemoryFiles(workspace);
  const sections: string[] = [];
  let totalLength = 0;
  for (const file of files) {
    try {
      const raw = await ipc.fs.read(file.path);
      const trimmed = raw.trim();
      if (!trimmed) continue;
      const body = truncateText(trimmed, maxPerFileChars);
      const section = `## ${file.relativePath}\n\n${body}`;
      sections.push(section);
      totalLength += section.length;
      if (totalLength >= maxTotalChars) break;
    } catch {
      // Missing memory files are expected.
    }
  }
  return truncateText(sections.join("\n\n"), maxTotalChars, "\n\n...(truncated)");
}

type Candidate = {
  node: FsNode;
  relativePath: string;
  componentCount: number;
  priority: number;
};

function flattenMemoryCandidates(root: FsNode, rootPath: string): Candidate[] {
  const candidates: Candidate[] = [];
  const visit = (node: FsNode) => {
    if (!node.isDir && MEMORY_LOOKUP.has(node.name.toLowerCase())) {
      const relativePath = relativeProjectPath(rootPath, node.path);
      candidates.push({
        node,
        relativePath,
        componentCount: relativePath.split(/[\\/]+/).filter(Boolean).length,
        priority: MEMORY_PRIORITY.get(node.name.toLowerCase()) ?? MEMORY_CANDIDATES.length,
      });
    }
    for (const child of node.children ?? []) visit(child);
  };
  visit(root);
  return candidates;
}

function relativeProjectPath(rootPath: string, path: string): string {
  const root = rootPath.replace(/\\/g, "/").replace(/\/+$/, "");
  const candidate = path.replace(/\\/g, "/");
  if (candidate.toLowerCase().startsWith(`${root.toLowerCase()}/`)) {
    return candidate.slice(root.length + 1);
  }
  return candidate.split("/").filter(Boolean).pop() ?? path;
}

function normalizePath(path: string): string {
  return path.replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

function truncateText(text: string, max: number, suffix = "..."): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}${suffix}`;
}
