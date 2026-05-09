import AppKit
import SwiftUI

/// Adaptive theme. Surface colors resolve per macOS appearance so light mode
/// is "first-class" — set Appearance in Settings to System, Light, or Dark.
/// Accent colors stay constant since the brand reads on either background.
enum LoomTheme {
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

    /// Darker pane background — terminals, agent chat. Stays inky in both
    /// modes because terminals are conventionally dark.
    static let terminalSurface = Color(red: 0.018, green: 0.022, blue: 0.026)

    // Brand accents — constant across modes.
    static let blue   = Color(red: 0.18, green: 0.50, blue: 0.96)
    static let green  = Color(red: 0.23, green: 0.86, blue: 0.46)
    static let orange = Color(red: 0.95, green: 0.39, blue: 0.18)
    static let pink   = Color(red: 0.95, green: 0.20, blue: 0.55)

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
