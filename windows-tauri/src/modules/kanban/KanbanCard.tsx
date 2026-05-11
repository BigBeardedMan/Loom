import { Icons } from "../../lib/icons";
import { surface, text } from "../../lib/theme";
import type { KanbanCard as KanbanCardData } from "../../lib/ipc";

const statusTint: Record<string, string> = {
  todo: "var(--color-loom-text-muted)",
  inProgress: "var(--color-ws-blue)",
  inReview: "var(--color-ws-purple)",
  complete: "var(--color-ws-green)",
  cancelled: "var(--color-loom-text-tertiary)",
};

type Props = {
  card: KanbanCardData;
  onDelete: () => void;
  onEdit?: () => void;
};

// Mirrors KanbanCardView in Loom/Kanban/KanbanPaneView.swift.
// Rounded card with status stripe + drag handle, 12/9 padding, hairline border.
// Double-click opens the edit modal.
export function KanbanCard({ card, onDelete, onEdit }: Props) {
  const tint = statusTint[card.statusRaw] ?? statusTint.todo;
  const completed = card.statusRaw === "complete";
  const cancelled = card.statusRaw === "cancelled";

  return (
    <div
      draggable
      onDragStart={(e) => {
        e.dataTransfer.setData("loom/card-id", card.id);
        e.dataTransfer.effectAllowed = "move";
      }}
      onDoubleClick={onEdit}
      className="group cursor-grab active:cursor-grabbing flex flex-col gap-1"
      style={{
        padding: "9px 12px",
        background: "var(--color-loom-bg-from)",
        border: `1px solid ${surface.hairline}`,
        borderLeft: `2px solid ${tint}`,
        borderRadius: 10,
        boxShadow: "0 1px 3px rgba(0, 0, 0, 0.15)",
        transition: "border-color 120ms ease-out, transform 120ms ease-out",
      }}
    >
      <div className="flex items-start justify-between gap-2">
        <span
          className="flex-1"
          style={{
            fontSize: 12,
            fontWeight: 500,
            color: text.primary,
            textDecoration: completed ? "line-through" : "none",
            opacity: cancelled ? 0.55 : 1,
          }}
        >
          {card.title}
        </span>
        <button
          className="invisible rounded p-0.5 group-hover:visible"
          onClick={onDelete}
          aria-label="Delete card"
          style={{ color: text.tertiary }}
        >
          <Icons.close size={11} strokeWidth={2.2} />
        </button>
      </div>
      {card.instructions && (
        <span
          className="line-clamp-2"
          style={{ fontSize: 11, color: text.muted }}
        >
          {card.instructions}
        </span>
      )}
    </div>
  );
}
