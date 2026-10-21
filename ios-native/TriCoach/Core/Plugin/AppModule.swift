import SwiftUI
import Observation

enum ModuleCategory: String, CaseIterable {
    case sport = "Disziplinen"
    case feature = "Werkzeuge"
}

struct DashboardTile: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var subtitle: String?
    let symbol: String
    let tint: Color
}

/// Plugin-Schnittstelle. Eine neue Sportart oder ein neues Feature =
/// ein Ordner unter Modules/ mit einem Typ, der `AppModule` implementiert,
/// plus eine Zeile in `ModuleRegistry.registerDefaults()`.
/// Navigation (Sidebar/Tabs) und Dashboard-Kacheln erscheinen automatisch.
@MainActor
protocol AppModule {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    var tint: Color { get }
    var category: ModuleCategory { get }
    var sport: Sport? { get }
    func makeView(store: TrainingStore) -> AnyView
    func dashboardTiles(store: TrainingStore) -> [DashboardTile]
}

extension AppModule {
    var sport: Sport? { nil }
    func dashboardTiles(store: TrainingStore) -> [DashboardTile] { [] }
}

@MainActor
@Observable
final class ModuleRegistry {
    static let shared = ModuleRegistry()

    private(set) var modules: [any AppModule] = []

    func register(_ module: any AppModule) {
        guard !modules.contains(where: { $0.id == module.id }) else { return }
        modules.append(module)
    }

    func module(id: String) -> (any AppModule)? { modules.first { $0.id == id } }

    func modules(in category: ModuleCategory) -> [any AppModule] { modules.filter { $0.category == category } }

    func module(for sport: Sport) -> (any AppModule)? { modules.first { $0.sport == sport } }

    static func registerDefaults() {
        shared.register(SwimModule())
        shared.register(BikeModule())
        shared.register(RunModule())
        shared.register(RaceModule())
        shared.register(WellnessModule())
        shared.register(HeatmapModule())
        // Neue Module hier registrieren, z. B. shared.register(StrengthModule())
    }
}
