import { useState, type ReactNode } from "react";
import { Icons } from "../../lib/icons";
import { surface, text, radius } from "../../lib/theme";
import { KanbanCard } from "./KanbanCard";
import type { KanbanColumn as KanbanColumnData } from "../../lib/ipc";

type Props = {
  column: KanbanColumnData;
  onAdd: (title: string) => Promise<void>;
  onMove: (cardId: string) => void;
  onDelete: (cardId: string) => void;
};

// Mirrors KanbanColumnView in Loom/Kanban/KanbanPaneView.swift.
// 14 px rounded panel, header with count badge, vertical card list, add affordance.
export function KanbanColumn({ column, onAdd, onMove, onDelete }: Props) {
  const [adding, setAdding] = useState(false);

  return (
    <div
      className="flex w-56 flex-none flex-col"
      style={{
        background: surface.panel,
        border: `1px solid ${surface.hairline}`,
        borderRadius: radius.panel,
        overflow: "hidden",
      }}
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        const cardId = e.dataTransfer.getData("loom/card-id");
        if (cardId) onMove(cardId);
      }}
    >
      <div
        className="flex items-center justify-between flex-none"
        style={{
          padding: "7px 12px",
          background: surface.inset,
          borderBottom: `1px solid ${surface.hairline}`,
        }}
      >
        <span style={{ fontSize: 11, fontWeight: 600, color: text.primary }}>
          {column.name}
        </span>
        <CountBadge>{column.cards.length}</CountBadge>
      </div>

      <div className="scrollbar-thin flex flex-1 flex-col gap-1.5 overflow-y-auto p-2">
        {column.cards.map((card) => (
          <KanbanCard
            key={card.id}
            card={card}
            onDelete={() => onDelete(card.id)}
          />
        ))}
        {adding ? (
          <AddCardForm
            onAdd={async (t) => {
              await onAdd(t);
              setAdding(false);
            }}
            onCancel={() => setAdding(false)}
          />
        ) : (
          <button
            onClick={() => setAdding(true)}
            className="flex items-center gap-1.5 transition-colors"
            style={{
              padding: "5px 8px",
              fontSize: 11,
              borderRadius: 6,
              background: "transparent",
              color: text.tertiary,
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = surface.softPanel as string;
              e.currentTarget.style.color = text.muted as string;
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = "transparent";
              e.currentTarget.style.color = text.tertiary as string;
            }}
          >
            <Icons.plus size={11} strokeWidth={2} />
            Add card
          </button>
        )}
      </div>
    </div>
  );
}

function CountBadge({ children }: { children: ReactNode }) {
  return (
    <span
      className="font-mono"
      style={{
        background: surface.softPanel,
        borderRadius: 999,
        padding: "1px 6px",
        fontSize: 10,
        fontWeight: 600,
        color: text.muted,
      }}
    >
      {children}
    </span>
  );
}

function AddCardForm({
  onAdd,
  onCancel,
}: {
  onAdd: (title: string) => Promise<void>;
  onCancel: () => void;
}) {
  const [v, setV] = useState("");
  return (
    <textarea
      autoFocus
      value={v}
      onChange={(e) => setV(e.target.value)}
      onBlur={() => {
        if (v.trim()) onAdd(v.trim());
        else onCancel();
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          if (v.trim()) onAdd(v.trim());
        }
        if (e.key === "Escape") onCancel();
      }}
      rows={2}
      placeholder="Card title…"
      className="w-full resize-none focus:outline-none"
      style={{
        padding: "7px 10px",
        fontSize: 12,
        borderRadius: 8,
        background: "var(--color-loom-bg-from)",
        border: `1px solid ${surface.hairline}`,
        color: text.primary,
      }}
    />
  );
}

