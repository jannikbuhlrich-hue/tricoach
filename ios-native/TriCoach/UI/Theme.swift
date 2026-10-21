import SwiftUI

extension Sport {
    var tint: Color {
        switch self {
        case .swim: return Color(red: 0.20, green: 0.72, blue: 0.95)
        case .bike: return Color(red: 1.00, green: 0.58, blue: 0.15)
        case .run: return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .strength: return .purple
        case .other: return .gray
        }
    }
}

enum Theme {
    static let corner: CGFloat = 20
    static let spacing: CGFloat = 16
    static let accent = Color(red: 0.95, green: 0.27, blue: 0.40)
    static let fitness = Color(red: 0.35, green: 0.55, blue: 1.0)
    static let fatigue = Color(red: 0.95, green: 0.35, blue: 0.55)
    static let form = Color(red: 1.0, green: 0.80, blue: 0.20)

    static func zoneColor(_ index: Int) -> Color {
        switch index {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .yellow
        case 5: return .orange
        case 6: return .red
        default: return .purple
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .dark: return "Dunkel"
        case .light: return "Hell"
        case .system: return "System"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
