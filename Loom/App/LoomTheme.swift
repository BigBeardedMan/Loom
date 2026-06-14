import AppKit
import SwiftUI

/// Adaptive theme. Surface colors resolve per macOS appearance so light mode
/// is "first-class" — set Appearance in Settings to System, Light, or Dark.
/// Accent colors stay constant since the brand reads on either background.
enum LoomTheme {
    static let panelRadius: CGFloat = 8
    static let rowRadius: CGFloat = 6
    static let controlRadius: CGFloat = 6

    static var background: LinearGradient {
        LinearGradient(
            colors: [backgroundStart, backgroundEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static let backgroundStart = adaptive(
        light: Color(red: 0.965, green: 0.97,  blue: 0.98),
        dark:  Color(red: 0.02,  green: 0.025, blue: 0.03)
    )
    private static let backgroundEnd = adaptive(
        light: Color(red: 0.93,  green: 0.94, blue: 0.96),
        dark:  Color(red: 0.035, green: 0.04, blue: 0.045)
    )

    static let panel = adaptive(
        light: Color(red: 0.992, green: 0.993, blue: 0.996).opacity(0.94),
        dark:  Color(red: 0.045, green: 0.049, blue: 0.056).opacity(0.9)
    )

    static let chrome = adaptive(
        light: Color(red: 0.972, green: 0.976, blue: 0.986).opacity(0.74),
        dark:  Color(red: 0.038, green: 0.042, blue: 0.049).opacity(0.72)
    )

    static let softPanel = adaptive(
        light: Color(red: 0.943, green: 0.948, blue: 0.96).opacity(0.68),
        dark:  Color(red: 0.082, green: 0.087, blue: 0.1).opacity(0.62)
    )

    /// Slightly darker than `panel` — used for headers and inset content.
    static let inset = adaptive(
        light: Color(red: 0.93, green: 0.938, blue: 0.952).opacity(0.44),
        dark:  Color.black.opacity(0.13)
    )

    static let hairline = adaptive(
        light: Color.black.opacity(0.085),
        dark:  Color.white.opacity(0.095)
    )

    static let primaryText = adaptive(
        light: Color.black.opacity(0.92),
        dark:  Color.white.opacity(0.94)
    )

    static let mutedText = adaptive(
        light: Color.black.opacity(0.55),
        dark:  Color.white.opacity(0.55)
    )

    static let tertiaryText = adaptive(
        light: Color.black.opacity(0.34),
        dark:  Color.white.opacity(0.35)
    )

    /// Darker pane background — terminals, agent chat. Stays inky in both
    /// modes because terminals are conventionally dark.
    static let terminalSurface = Color(red: 0.018, green: 0.022, blue: 0.026)

    static let shellRail = adaptive(
        light: Color(red: 0.948, green: 0.954, blue: 0.968).opacity(0.64),
        dark:  Color(red: 0.03, green: 0.034, blue: 0.042).opacity(0.64)
    )

    static let shellInspector = adaptive(
        light: Color(red: 0.972, green: 0.977, blue: 0.988).opacity(0.7),
        dark:  Color(red: 0.041, green: 0.045, blue: 0.054).opacity(0.7)
    )

    static let shellStatus = adaptive(
        light: Color(red: 0.94, green: 0.95, blue: 0.97).opacity(0.42),
        dark:  Color.black.opacity(0.12)
    )

    // Brand accents — constant across modes.
    static let blue   = Color(red: 0.18, green: 0.50, blue: 0.96)
    static let green  = Color(red: 0.23, green: 0.86, blue: 0.46)
    static let orange = Color(red: 0.95, green: 0.39, blue: 0.18)
    static let pink   = Color(red: 0.95, green: 0.20, blue: 0.55)

    static let purple = Color(red: 0.62, green: 0.40, blue: 0.95)
    static let yellow = Color(red: 0.96, green: 0.77, blue: 0.20)

    static func panelShadow(active: Bool = false) -> Color {
        .black.opacity(active ? 0.26 : 0.08)
    }

    static func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(mutedText)
            .tracking(0.55)
    }

    /// Build a Color that picks `dark` under any dark-mode appearance and
    /// `light` otherwise. Wraps NSColor's dynamic provider.
    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkVariants: [NSAppearance.Name] = [
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]
            let isDark = appearance.bestMatch(from: darkVariants) != nil
            return NSColor(isDark ? dark : light)
        })
    }
}

extension View {
    /// Flip the cursor to a pointing hand while hovering, back to arrow on
    /// exit. Use for clickable elements that don't carry obvious button
    /// chrome (banner image, capsule pills, custom controls). Uses
    /// `NSCursor.set()` rather than push/pop so rapid hover transitions
    /// don't leak items onto the cursor stack.
    func pointingHandCursor() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

struct LoomNotificationBadge: View {
    var value: Int = 1

    var body: some View {
        Text("\(value)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(LoomTheme.pink)
            .clipShape(Circle())
            .overlay(Circle().stroke(LoomTheme.panel, lineWidth: 1.5))
            .shadow(color: LoomTheme.pink.opacity(0.45), radius: 4, x: 0, y: 1)
            .accessibilityLabel("\(value) usage limit warning")
    }
}

struct LoomIconButton: View {
    let systemName: String
    var help: String
    var tint: Color = LoomTheme.mutedText
    var isActive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .white : tint)
                .frame(width: 26, height: 24)
                .background(isActive ? tint : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: LoomTheme.controlRadius)
                        .stroke(isActive ? tint.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: LoomTheme.controlRadius))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

struct LoomStatusPill: View {
    let title: String
    var systemImage: String?
    var tint: Color = LoomTheme.mutedText
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? .white : tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(filled ? tint : tint.opacity(0.12))
        .overlay(Capsule().stroke(filled ? tint.opacity(0.5) : tint.opacity(0.22), lineWidth: 1))
        .clipShape(Capsule())
    }
}

struct LoomEmptyState: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color = LoomTheme.mutedText

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tint.opacity(0.75))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LoomTheme.primaryText)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(LoomTheme.mutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(LoomTheme.softPanel.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: LoomTheme.panelRadius)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LoomTheme.panelRadius))
    }
}
