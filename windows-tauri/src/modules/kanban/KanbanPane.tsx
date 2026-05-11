import { useEffect, useState } from "react";
import { useApp } from "../../lib/store";
import { surface } from "../../lib/theme";
import { ipc, type KanbanBoard, type KanbanCard, type Workspace } from "../../lib/ipc";
import { KanbanColumn } from "./KanbanColumn";
import { KanbanCardModal } from "./KanbanCardModal";

type Props = { workspace: Workspace; blockId?: string };

// Mirrors Loom/Kanban/KanbanPaneView.swift.
// Horizontal column strip with drag-to-move + double-click edit.
export function KanbanPane({ workspace, blockId }: Props) {
  const setBlockStatus = useApp((s) => s.setBlockStatus);
  const [board, setBoard] = useState<KanbanBoard | null>(null);
  const [editing, setEditing] = useState<KanbanCard | null>(null);

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

  useEffect(() => {
    if (!blockId || !board) return;
    const cards = board.columns.flatMap((c) => c.cards);
    const inProgress = cards.some(
      (c) => c.statusRaw === "inProgress" || c.statusRaw === "inReview"
    );
    setBlockStatus(blockId, inProgress ? "active" : "idle");
  }, [board, blockId, setBlockStatus]);

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

  return (
    <div className="flex h-full flex-col" style={{ background: surface.panel }}>
      <div className="scrollbar-thin flex-1 overflow-x-auto">
        <div className="flex h-full min-w-max gap-2.5 p-3">
          {board?.columns.map((col) => (
            <KanbanColumn
              key={col.id}
              column={col}
              onAdd={(title) => addCard(col.id, title)}
              onMove={(cardId) => moveCard(cardId, col.id)}
              onDelete={deleteCard}
              onEditCard={(card) => setEditing(card)}
            />
          ))}
        </div>
      </div>
      {editing && (
        <KanbanCardModal
          card={editing}
          onClose={() => setEditing(null)}
          onSaved={load}
        />
      )}
    </div>
  );
}
