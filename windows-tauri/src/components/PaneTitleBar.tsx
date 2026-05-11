import type { ReactNode } from "react";
import { paneTitleBar, surface, text } from "../lib/theme";

type Props = {
  icon?: ReactNode;
  iconColor?: string;
  title: string;
  subtitle?: string;
  right?: ReactNode;
  variant?: "light" | "dark";
};

// Mirrors the repeated title-bar block in every macOS pane:
// rgba(0, 0, 0, 0.16) strip with bottom hairline, 12/9 padding,
// 12 pt semibold title; left icon + right controls slots.
export function PaneTitleBar({
  icon,
  iconColor,
  title,
  subtitle,
  right,
  variant = "light",
}: Props) {
  const bg =
    variant === "dark" ? "rgba(0, 0, 0, 0.32)" : "rgba(0, 0, 0, 0.16)";
  const border =
    variant === "dark"
      ? "rgba(255, 255, 255, 0.10)"
      : surface.hairline;
  return (
    <div
      className="flex items-center gap-2 flex-none"
      style={{
        padding: `${paneTitleBar.paddingV}px ${paneTitleBar.paddingH}px`,
        background: bg,
        borderBottom: `1px solid ${border}`,
      }}
    >
      {icon && (
        <span
          className="flex items-center justify-center"
          style={{ color: iconColor ?? text.muted, fontSize: 11 }}
        >
          {icon}
        </span>
      )}
      <span
        className="truncate"
        style={{
          fontSize: paneTitleBar.titleSize,
          fontWeight: paneTitleBar.titleWeight,
          color: text.primary,
        }}
      >
        {title}
      </span>
      {subtitle && (
        <span
          className="truncate font-mono"
          style={{ fontSize: 11, color: text.muted }}
        >
          · {subtitle}
        </span>
      )}
      <div className="ml-auto flex items-center gap-1">{right}</div>
    </div>
  );
}
