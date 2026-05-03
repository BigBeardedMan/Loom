import SwiftUI

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.stars"
        }
    }

    /// nil ⇒ inherit the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

extension View {
    /// Apply the user's `loom.appearance` preference. Reads from `@AppStorage`
    /// so toggling in Settings instantly re-themes every window.
    func loomAppearance() -> some View {
        modifier(LoomAppearanceModifier())
    }
}

private struct LoomAppearanceModifier: ViewModifier {
    @AppStorage("loom.appearance") private var raw: String = AppearanceSetting.dark.rawValue

    private var setting: AppearanceSetting {
        AppearanceSetting(rawValue: raw) ?? .dark
    }

    func body(content: Content) -> some View {
        content.preferredColorScheme(setting.colorScheme)
    }
}
