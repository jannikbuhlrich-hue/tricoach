import SwiftUI

@main
struct TriCoachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TrainingStore.shared
    @State private var registry = ModuleRegistry.shared
    @AppStorage("appearance") private var appearance: AppearanceMode = .dark
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ModuleRegistry.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(registry)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .task {
                    await SyncService.shared.syncIfStale()
                    SyncService.shared.startHealthKitObserver()
                    SyncService.shared.scheduleAppRefresh()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await SyncService.shared.syncIfStale() } }
        }
        .backgroundTask(.appRefresh(SyncService.refreshTaskID)) {
            await SyncService.shared.backgroundRefresh()
        }

        // iPad Multi-Window: Aktivität in eigenem Fenster
        WindowGroup("Aktivität", id: "activity", for: String.self) { $activityID in
            ActivityWindowView(activityID: activityID)
                .environment(store)
                .environment(registry)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
