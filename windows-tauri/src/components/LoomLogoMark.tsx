// Mirrors Loom/App/LoomLogoMark.swift gradient mark.
// Stylized "L" inside a square with the workspace brand gradient.
type Props = { size?: number };

export function LoomLogoMark({ size = 20 }: Props) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 32 32"
      fill="none"
      aria-label="Loom"
    >
      <defs>
        <linearGradient id="loomMark" x1="0" y1="0" x2="32" y2="32">
          <stop offset="0%" stopColor="#F24620" />
          <stop offset="50%" stopColor="#F23388" />
          <stop offset="100%" stopColor="#9E57F0" />
        </linearGradient>
      </defs>
      <rect x="1" y="1" width="30" height="30" rx="7" fill="url(#loomMark)" />
      <path
        d="M11 9v14h10"
        stroke="white"
        strokeWidth="2.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
