import { useState } from "react";
import { Icons } from "../../lib/icons";
import { surface, text } from "../../lib/theme";
import { ipc, type KanbanCard } from "../../lib/ipc";

const STATUSES: { value: string; label: string }[] = [
  { value: "todo", label: "Todo" },
  { value: "inProgress", label: "In Progress" },
  { value: "inReview", label: "In Review" },
  { value: "complete", label: "Complete" },
  { value: "cancelled", label: "Cancelled" },
];

type Props = {
  card: KanbanCard;
  onClose: () => void;
  onSaved: () => void;
};

// Mirrors the macOS card edit sheet in Loom/Kanban/KanbanPaneView.swift.
// Title / instructions / status / agent / project path.
export function KanbanCardModal({ card, onClose, onSaved }: Props) {
  const [title, setTitle] = useState(card.title);
  const [instructions, setInstructions] = useState(card.instructions);
  const [taskKnowledge, setTaskKnowledge] = useState(card.taskKnowledge);
  const [statusRaw, setStatus] = useState(card.statusRaw);
  const [agentName, setAgentName] = useState(card.agentName);
  const [projectPath, setProjectPath] = useState(card.projectPath);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    setSaving(true);
    try {
      await ipc.kanban.updateCard(card.id, {
        title,
        instructions,
        taskKnowledge,
        statusRaw,
        agentName,
        projectPath,
      });
      onSaved();
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      style={{
        background: "rgba(0, 0, 0, 0.40)",
        backdropFilter: "blur(20px) saturate(180%)",
        WebkitBackdropFilter: "blur(20px) saturate(180%)",
      }}
      onClick={onClose}
    >
      <div
        className="flex flex-col"
        style={{
          width: 540,
          maxHeight: "85vh",
          background: surface.panel,
          border: `1px solid ${surface.hairline}`,
          borderRadius: 14,
          boxShadow: "0 24px 48px rgba(0, 0, 0, 0.45)",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div
          className="flex items-center justify-between flex-none"
          style={{ padding: "12px 16px", borderBottom: `1px solid ${surface.hairline}` }}
        >
          <span className="section-header">Edit Card</span>
          <button onClick={onClose} aria-label="Close" style={{ color: text.muted }}>
            <Icons.close size={14} strokeWidth={2} />
          </button>
        </div>
        <div
          className="scrollbar-thin flex-1 overflow-y-auto flex flex-col gap-3"
          style={{ padding: 16 }}
        >
          <Field label="Title">
            <input
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="w-full focus:outline-none"
              style={inputStyle}
            />
          </Field>
          <Field label="Status">
            <select
              value={statusRaw}
              onChange={(e) => setStatus(e.target.value)}
              className="w-full focus:outline-none"
              style={inputStyle}
            >
              {STATUSES.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Instructions">
            <textarea
              rows={4}
              value={instructions}
              onChange={(e) => setInstructions(e.target.value)}
              className="w-full focus:outline-none scrollbar-thin"
              style={{ ...inputStyle, resize: "vertical", fontFamily: "var(--font-mono)" }}
            />
          </Field>
          <Field label="Task Knowledge">
            <textarea
              rows={3}
              value={taskKnowledge}
              onChange={(e) => setTaskKnowledge(e.target.value)}
              className="w-full focus:outline-none scrollbar-thin"
              style={{ ...inputStyle, resize: "vertical", fontFamily: "var(--font-mono)" }}
            />
          </Field>
          <Field label="Agent">
            <input
              value={agentName}
              onChange={(e) => setAgentName(e.target.value)}
              className="w-full focus:outline-none"
              style={inputStyle}
            />
          </Field>
          <Field label="Project Path">
            <input
              value={projectPath}
              onChange={(e) => setProjectPath(e.target.value)}
              className="w-full focus:outline-none"
              style={{ ...inputStyle, fontFamily: "var(--font-mono)" }}
            />
          </Field>
        </div>
        <div
          className="flex items-center justify-end gap-2 flex-none"
          style={{ padding: 12, borderTop: `1px solid ${surface.hairline}` }}
        >
          <button
            onClick={onClose}
            style={{
              padding: "6px 14px",
              borderRadius: 8,
              fontSize: 12,
              fontWeight: 500,
              background: "transparent",
              border: `1px solid ${surface.hairline}`,
              color: text.muted,
            }}
          >
            Cancel
          </button>
          <button
            onClick={save}
            disabled={saving}
            style={{
              padding: "6px 14px",
              borderRadius: 8,
              fontSize: 12,
              fontWeight: 500,
              background: "var(--color-loom-accent)",
              color: "#fff",
              border: "none",
              opacity: saving ? 0.5 : 1,
            }}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label
        style={{
          display: "block",
          fontSize: 11,
          color: text.muted,
          marginBottom: 4,
          fontWeight: 500,
        }}
      >
        {label}
      </label>
      {children}
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  background: "var(--color-loom-bg-from)",
  border: `1px solid ${surface.hairline}`,
  borderRadius: 8,
  padding: "7px 10px",
  fontSize: 13,
  color: text.primary,
};
