import type { Workspace } from "../../lib/ipc";

export function defaultPreviewUrlFor(workspace: Workspace, autoIndex: number): string {
  if (workspace.previewUrl) return workspace.previewUrl;
  return `http://localhost:${3000 + autoIndex}`;
}
