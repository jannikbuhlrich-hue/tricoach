import Foundation
import BackgroundTasks
import HealthKit
import UIKit

/// „Live-Sync“: holt neue Einheiten so schnell wie möglich nach dem Training.
///
/// Drei Wege, je nach Datenquelle:
/// 1. Garmin-API: Garmin pusht innerhalb von Sekunden nach dem Uhr-Sync an dein Backend →
///    Backend schickt eine stille APNs-Push → `handleRemoteNotification` startet den Sync.
/// 2. Apple Health: `HKObserverQuery` + Background Delivery meldet neue Workouts sofort.
/// 3. Fallback: BGAppRefreshTask + Sync beim Öffnen der App.
@MainActor
final class SyncService {
    static let shared = SyncService()
    static let refreshTaskID = "de.tricoach.refresh"

    private let healthStore = HKHealthStore()
    private var observerStarted = false

    func syncIfStale(store: TrainingStore = .shared, maxAge: TimeInterval = 300) async {
        if let last = store.lastSync, Date().timeIntervalSince(last) < maxAge { return }
        await store.sync()
    }

    // MARK: Hintergrund-Refresh

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func backgroundRefresh() async {
        scheduleAppRefresh()
        await TrainingStore.shared.sync(daysBack: 14)
    }

    // MARK: Apple Health Observer

    func startHealthKitObserver() {
        guard !observerStarted, HKHealthStore.isHealthDataAvailable(),
              TrainingStore.shared.enabledSources.contains(.healthKit) else { return }
        observerStarted = true
        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await TrainingStore.shared.sync(daysBack: 14)
                completion()
            }
        }
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    // MARK: Garmin Push (über eigenes Backend)

    func registerForPush() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        guard let backend = GarminConfig.backendURL,
              let session = KeychainStore.get(GarminConfig.sessionTokenKey) else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: backend.appendingPathComponent("v1/devices"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["apnsToken": token])
        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    /// Stille Push mit `{"aps":{"content-available":1},"type":"garmin.activity"}`
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard (userInfo["type"] as? String)?.hasPrefix("garmin") == true else { return .noData }
        let before = TrainingStore.shared.activities.count
        await TrainingStore.shared.sync(daysBack: 3)
        return TrainingStore.shared.activities.count > before ? .newData : .noData
    }
}

/// AppDelegate nur für Push-Registrierung (SwiftUI hat dafür kein eigenes API).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if GarminConfig.isConnected { SyncService.shared.registerForPush() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SyncService.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await SyncService.shared.handleRemoteNotification(userInfo)
    }
}
