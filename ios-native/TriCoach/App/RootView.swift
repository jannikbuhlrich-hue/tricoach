import SwiftUI

enum Route: Hashable {
    case module(String)
    case activity(String)
    case race(UUID)
    case settings
}

enum SidebarItem: Hashable {
    case dashboard, calendar, settings
    case module(String)
}

/// iPhone: TabView · iPad: NavigationSplitView mit Sidebar (Split View & Stage Manager)
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular { SplitRootView() } else { TabRootView() }
    }
}

struct SplitRootView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(ModuleRegistry.self) private var registry
    @State private var selection: SidebarItem? = .dashboard
    @State private var path = NavigationPath()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Übersicht") {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill").tag(SidebarItem.dashboard)
                    Label("Kalender", systemImage: "calendar").tag(SidebarItem.calendar)
                }
                ForEach(ModuleCategory.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(registry.modules(in: category), id: \.id) { module in
                            Label(module.title, systemImage: module.symbol)
                                .foregroundStyle(module.tint)
                                .tag(SidebarItem.module(module.id))
                        }
                    }
                }
                Section {
                    Label("Einstellungen", systemImage: "gearshape").tag(SidebarItem.settings)
                }
            }
            .navigationTitle("TriCoach")
        } detail: {
            NavigationStack(path: $path) {
                ScreenFactory.view(for: selection ?? .dashboard, store: store, registry: registry)
                    .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            }
        }
        .onChange(of: selection) { path = NavigationPath() }
    }
}

struct TabRootView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        TabView {
            tab(.dashboard).tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            tab(.calendar).tabItem { Label("Kalender", systemImage: "calendar") }
            NavigationStack {
                AnalysisHubView()
                    .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            }
            .tabItem { Label("Analyse", systemImage: "chart.xyaxis.line") }
            tab(.module("race")).tabItem { Label("Wettkampf", systemImage: "flag.checkered") }
            tab(.settings).tabItem { Label("Mehr", systemImage: "gearshape") }
        }
    }

    private func tab(_ item: SidebarItem) -> some View {
        NavigationStack {
            ScreenFactory.view(for: item, store: store, registry: registry)
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }
}

@MainActor
enum ScreenFactory {
    @ViewBuilder
    static func view(for item: SidebarItem, store: TrainingStore, registry: ModuleRegistry) -> some View {
        switch item {
        case .dashboard:
            DashboardView(viewModel: makeDashboardViewModel(store: store))
        case .calendar:
            CalendarView(viewModel: CalendarViewModel(store: store))
        case .settings:
            SettingsView()
        case .module(let id):
            if let module = registry.module(id: id) {
                module.makeView(store: store)
            } else {
                EmptyStateView(title: "Modul fehlt", message: id, symbol: "puzzlepiece")
            }
        }
    }

    static func makeDashboardViewModel(store: TrainingStore) -> DashboardViewModel {
        let vm = DashboardViewModel(store: store)
        if UserDefaults.standard.bool(forKey: "useLLMCoach"), let backend = GarminConfig.backendURL {
            vm.coach = LLMCoach(endpoint: backend.appendingPathComponent("v1/coach"))
        }
        return vm
    }
}

struct RouteDestination: View {
    let route: Route
    @Environment(TrainingStore.self) private var store
    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        switch route {
        case .module(let id):
            ScreenFactory.view(for: .module(id), store: store, registry: registry)
        case .activity(let id):
            if let activity = store.activity(id: id) {
                ActivityDetailView(activity: activity)
            } else {
                EmptyStateView(title: "Nicht gefunden", message: "Aktivität existiert nicht mehr.", symbol: "questionmark")
            }
        case .race(let id):
            RaceDetailView(viewModel: RaceDetailViewModel(store: store, raceID: id))
        case .settings:
            SettingsView()
        }
    }
}

/// Übersicht aller Analyse-Module (iPhone-Tab)
struct AnalysisHubView: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(TrainingStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                ForEach(ModuleCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).font(.title3.weight(.semibold))
                    TileGrid {
                        ForEach(registry.modules(in: category), id: \.id) { module in
                            NavigationLink(value: Route.module(module.id)) {
                                let tile = module.dashboardTiles(store: store).first
                                MetricTile(title: module.title, value: tile?.value ?? "Öffnen",
                                           subtitle: tile?.subtitle, symbol: module.symbol, tint: module.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Analyse")
    }
}
