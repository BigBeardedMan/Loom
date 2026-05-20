import AppKit
import SwiftUI

/// Adaptive theme. Surface colors resolve per macOS appearance so light mode
/// is "first-class" — set Appearance in Settings to System, Light, or Dark.
/// Accent colors stay constant since the brand reads on either background.
enum LoomTheme {
    static let panelRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let controlRadius: CGFloat = 7

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
        light: Color(red: 0.99, green: 0.99, blue: 1.0).opacity(0.96),
        dark:  Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.92)
    )

    static let chrome = adaptive(
        light: Color(red: 0.98, green: 0.985, blue: 0.995).opacity(0.88),
        dark:  Color(red: 0.048, green: 0.052, blue: 0.06).opacity(0.9)
    )

    static let softPanel = adaptive(
        light: Color(red: 0.95, green: 0.95, blue: 0.97).opacity(0.94),
        dark:  Color(red: 0.085, green: 0.09, blue: 0.105).opacity(0.9)
    )

    /// Slightly darker than `panel` — used for headers and inset content.
    static let inset = adaptive(
        light: Color(red: 0.93, green: 0.94, blue: 0.96).opacity(0.6),
        dark:  Color.black.opacity(0.18)
    )

    static let hairline = adaptive(
        light: Color.black.opacity(0.10),
        dark:  Color.white.opacity(0.12)
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

    // Brand accents — constant across modes.
    static let blue   = Color(red: 0.18, green: 0.50, blue: 0.96)
    static let green  = Color(red: 0.23, green: 0.86, blue: 0.46)
    static let orange = Color(red: 0.95, green: 0.39, blue: 0.18)
    static let pink   = Color(red: 0.95, green: 0.20, blue: 0.55)

    static let purple = Color(red: 0.62, green: 0.40, blue: 0.95)
    static let yellow = Color(red: 0.96, green: 0.77, blue: 0.20)

    static func panelShadow(active: Bool = false) -> Color {
        .black.opacity(active ? 0.34 : 0.18)
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
                .background(isActive ? tint : LoomTheme.softPanel.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: LoomTheme.controlRadius)
                        .stroke(isActive ? tint.opacity(0.6) : LoomTheme.hairline, lineWidth: 1)
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
