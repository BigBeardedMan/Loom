import { useEffect, useState } from "react";
import { Plus } from "lucide-react";
import { ipc, type KanbanBoard, type KanbanCard, type Workspace } from "../../lib/ipc";

export function KanbanPane({ workspace }: { workspace: Workspace }) {
  const [board, setBoard] = useState<KanbanBoard | null>(null);
  const [adding, setAdding] = useState<string | null>(null);

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
    if (!title.trim()) return;
    await ipc.kanban.createCard({
      columnId,
      title: title.trim(),
      projectPath: workspace.folderPath,
    });
    setAdding(null);
    load();
  };

  const moveCard = async (card: KanbanCard, newColumnId: string) => {
    await ipc.kanban.moveCard(card.id, newColumnId);
    load();
  };

  const deleteCard = async (id: string) => {
    await ipc.kanban.deleteCard(id);
    load();
  };

  return (
    <div className="flex h-full flex-col bg-loom-bg">
      <div className="flex items-center justify-between border-b border-loom-border bg-loom-panel px-3 py-1.5">
        <span className="text-xs font-medium uppercase tracking-wider text-loom-text-mute">
          Tasks
        </span>
      </div>
      <div className="scrollbar-thin flex-1 overflow-x-auto">
        <div className="flex h-full min-w-max gap-2 p-2">
          {board?.columns.map((col) => (
            <div
              key={col.id}
              className="flex w-48 flex-none flex-col rounded-md border border-loom-border bg-loom-panel"
              onDragOver={(e) => e.preventDefault()}
              onDrop={(e) => {
                const cardId = e.dataTransfer.getData("loom/card-id");
                if (!cardId) return;
                const card = board?.columns
                  .flatMap((c) => c.cards)
                  .find((c) => c.id === cardId);
                if (card && card.columnId !== col.id) moveCard(card, col.id);
              }}
            >
              <div className="flex items-center justify-between border-b border-loom-border px-2 py-1 text-xs">
                <span className="font-medium text-loom-text">{col.name}</span>
                <span className="text-loom-text-mute">{col.cards.length}</span>
              </div>
              <div className="scrollbar-thin flex flex-1 flex-col gap-1 overflow-y-auto p-1.5">
                {col.cards.map((card) => (
                  <div
                    key={card.id}
                    draggable
                    onDragStart={(e) =>
                      e.dataTransfer.setData("loom/card-id", card.id)
                    }
                    className="group cursor-grab rounded border border-loom-border bg-loom-bg px-2 py-1.5 text-xs text-loom-text-dim hover:border-loom-accent hover:text-loom-text active:cursor-grabbing"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <span className="flex-1">{card.title}</span>
                      <button
                        className="invisible text-loom-text-mute hover:text-loom-text group-hover:visible"
                        onClick={() => deleteCard(card.id)}
                        aria-label="Delete card"
                      >
                        ×
                      </button>
                    </div>
                  </div>
                ))}
                {adding === col.id ? (
                  <AddCardForm
                    onAdd={(t) => addCard(col.id, t)}
                    onCancel={() => setAdding(null)}
                  />
                ) : (
                  <button
                    onClick={() => setAdding(col.id)}
                    className="flex items-center gap-1 rounded px-1.5 py-1 text-xs text-loom-text-mute hover:bg-loom-panel-elev hover:text-loom-text"
                  >
                    <Plus className="h-3 w-3" />
                    Add card
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function AddCardForm({
  onAdd,
  onCancel,
}: {
  onAdd: (title: string) => void;
  onCancel: () => void;
}) {
  const [v, setV] = useState("");
  return (
    <textarea
      autoFocus
      value={v}
      onChange={(e) => setV(e.target.value)}
      onBlur={() => {
        if (v.trim()) onAdd(v);
        else onCancel();
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          onAdd(v);
        }
        if (e.key === "Escape") onCancel();
      }}
      rows={2}
      placeholder="Card title…"
      className="w-full resize-none rounded border border-loom-border bg-loom-bg px-2 py-1 text-xs text-loom-text outline-none focus:border-loom-accent"
    />
  );
}
