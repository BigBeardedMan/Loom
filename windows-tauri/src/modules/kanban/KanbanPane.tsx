import { useEffect, useState } from "react";
import { Icons } from "../../lib/icons";
import { PaneTitleBar } from "../../components/PaneTitleBar";
import { surface } from "../../lib/theme";
import { ipc, type KanbanBoard, type Workspace } from "../../lib/ipc";
import { KanbanColumn } from "./KanbanColumn";

// Mirrors Loom/Kanban/KanbanPaneView.swift.
// PaneTitleBar header + horizontal column strip with KanbanColumn children.
export function KanbanPane({ workspace }: { workspace: Workspace }) {
  const [board, setBoard] = useState<KanbanBoard | null>(null);

  const load = async () => {
    try {
      const b = await ipc.kanban.getBoard(workspace.id);
      setBoard(b);
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [workspace.id]);

  const addCard = async (columnId: string, title: string) => {
    await ipc.kanban.createCard({
      columnId,
      title,
      projectPath: workspace.folderPath,
    });
    load();
  };

  const moveCard = async (cardId: string, newColumnId: string) => {
    await ipc.kanban.moveCard(cardId, newColumnId);
    load();
  };

  const deleteCard = async (id: string) => {
    await ipc.kanban.deleteCard(id);
    load();
  };

  const totalCards = board?.columns.reduce((a, c) => a + c.cards.length, 0) ?? 0;

  return (
    <div className="flex h-full flex-col" style={{ background: surface.panel }}>
      <PaneTitleBar
        icon={<Icons.checkCircle size={11} strokeWidth={2.2} color="var(--color-ws-orange)" />}
        title="Tasks"
        right={
          <span
            className="font-mono"
            style={{
              fontSize: 10,
              fontWeight: 600,
              color: "var(--color-loom-text-muted)",
              padding: "1px 6px",
              borderRadius: 999,
              background: "rgba(255, 255, 255, 0.05)",
            }}
          >
            {totalCards}
          </span>
        }
      />
      <div className="scrollbar-thin flex-1 overflow-x-auto">
        <div className="flex h-full min-w-max gap-2.5 p-3">
          {board?.columns.map((col) => (
            <KanbanColumn
              key={col.id}
              column={col}
              onAdd={(title) => addCard(col.id, title)}
              onMove={(cardId) => moveCard(cardId, col.id)}
              onDelete={deleteCard}
            />
          ))}
        </div>
      </div>
    </div>
  );
}
