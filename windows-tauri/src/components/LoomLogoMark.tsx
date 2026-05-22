// Mirrors Loom/App/LoomLogoMark.swift. Stacked terminal-windows mark on a
// near-black canvas; same art the macOS AppIcon set is rendered from, so the
// Windows titlebar matches what users see on every other Loom surface.
type Props = { size?: number };

export function LoomLogoMark({ size = 20 }: Props) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      fill="none"
      aria-label="Loom"
    >
      <rect width="100" height="100" rx="22.5" fill="#0a0a0a" />
      <g transform="translate(18.85 25.08) scale(0.89)">
        <rect
          x="14"
          y="14"
          width="56"
          height="42"
          rx="5"
          fill="#18181b"
          stroke="#3f3f46"
          strokeWidth="1.2"
        />
        <rect
          x="7"
          y="7"
          width="56"
          height="42"
          rx="5"
          fill="#1c1c20"
          stroke="#52525b"
          strokeWidth="1.2"
        />
        <circle cx="11" cy="11" r="1.5" fill="#52525b" />
        <circle cx="16" cy="11" r="1.5" fill="#3f3f46" />
        <rect
          x="0"
          y="0"
          width="56"
          height="42"
          rx="5"
          fill="#27272a"
          stroke="#a1a1aa"
          strokeWidth="1.2"
        />
        <circle cx="6" cy="6" r="1.8" fill="#5eead4" />
        <circle cx="12" cy="6" r="1.8" fill="#a1a1aa" opacity="0.4" />
        <circle cx="18" cy="6" r="1.8" fill="#a1a1aa" opacity="0.25" />
        <rect x="6" y="16" width="3" height="2" fill="#5eead4" />
        <rect x="12" y="16" width="20" height="2" fill="#a1a1aa" opacity="0.5" />
        <rect x="6" y="22" width="3" height="2" fill="#5eead4" />
        <rect x="12" y="22" width="14" height="2" fill="#a1a1aa" opacity="0.5" />
        <rect x="6" y="28" width="3" height="2" fill="#5eead4" />
        <rect x="12" y="28" width="6" height="2" fill="#5eead4" />
      </g>
    </svg>
  );
}
