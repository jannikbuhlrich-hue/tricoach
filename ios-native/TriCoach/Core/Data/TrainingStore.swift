import Foundation
import Observation

/// Zentrale Datenhaltung (Repository) der App.
/// Views/ViewModels lesen hier, Datenquellen schreiben über `sync()`.
@MainActor
@Observable
final class TrainingStore {
    static let shared = TrainingStore()

    // MARK: Persistierter Zustand
    // Manuelles Observation-Muster (access/withMutation), damit jede Änderung sofort gespeichert wird.

    @ObservationIgnored private var _profile: AthleteProfile
    @ObservationIgnored private var _planned: [PlannedWorkout]
    @ObservationIgnored private var _races: [RaceGoal]
    @ObservationIgnored private var _fuelLog: [FuelLogEntry]
    @ObservationIgnored private var _enabledSources: Set<DataSourceKind>
    @ObservationIgnored private var _calendarSyncEnabled: Bool

    var profile: AthleteProfile {
        get { access(keyPath: \.profile); return _profile }
        set { withMutation(keyPath: \.profile) { _profile = newValue }; persistState() }
    }
    var planned: [PlannedWorkout] {
        get { access(keyPath: \.planned); return _planned }
        set { withMutation(keyPath: \.planned) { _planned = newValue }; persistState() }
    }
    var races: [RaceGoal] {
        get { access(keyPath: \.races); return _races }
        set { withMutation(keyPath: \.races) { _races = newValue }; persistState() }
    }
    var fuelLog: [FuelLogEntry] {
        get { access(keyPath: \.fuelLog); return _fuelLog }
        set { withMutation(keyPath: \.fuelLog) { _fuelLog = newValue }; persistState() }
    }
    var enabledSources: Set<DataSourceKind> {
        get { access(keyPath: \.enabledSources); return _enabledSources }
        set { withMutation(keyPath: \.enabledSources) { _enabledSources = newValue }; persistState() }
    }
    var calendarSyncEnabled: Bool {
        get { access(keyPath: \.calendarSyncEnabled); return _calendarSyncEnabled }
        set { withMutation(keyPath: \.calendarSyncEnabled) { _calendarSyncEnabled = newValue }; persistState() }
    }

    // MARK: Abgeleiteter Zustand

    private(set) var activities: [Activity] = []
    private(set) var wellness: [DailyWellness] = []
    private(set) var loadSeries: [LoadPoint] = []
    private(set) var isSyncing = false
    private(set) var lastSync: Date? = nil
    private(set) var lastErrors: [String] = []

    @ObservationIgnored private let persistence: LocalPersistence

    init() {
        let persistence = LocalPersistence()
        self.persistence = persistence
        let state = persistence.loadState()
        _profile = state?.profile ?? AthleteProfile()
        _planned = state?.planned ?? []
        _races = state?.races ?? [RaceGoal(name: "Mein Saisonhöhepunkt",
                                           date: Calendar.training.date(byAdding: .day, value: 70, to: Date()) ?? Date(),
                                           format: .olympic)]
        _fuelLog = state?.fuelLog ?? []
        _enabledSources = state?.enabledSources ?? [.mock]
        _calendarSyncEnabled = state?.calendarSyncEnabled ?? false
        lastSync = state?.lastSync
        if let cache = persistence.loadCache() {
            activities = cache.activities
            wellness = cache.wellness
            recomputeDerived()
        }
    }

    // MARK: Sync

    func makeSources() -> [any TrainingDataSource] {
        var sources: [any TrainingDataSource] = []
        if enabledSources.contains(.mock) { sources.append(MockDataSource(profile: profile)) }
        if enabledSources.contains(.healthKit), HealthKitDataSource.isAvailable { sources.append(HealthKitDataSource()) }
        if enabledSources.contains(.fitFile) { sources.append(FITImportDataSource()) }
        if enabledSources.contains(.garmin), let garmin = GarminAPIClient.makeIfConfigured() { sources.append(garmin) }
        return sources
    }

    /// Lädt Aktivitäten + Wellness aus allen aktiven Quellen und führt sie zusammen.
    func sync(daysBack: Int = 150) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let to = Date()
        let from = Calendar.training.date(byAdding: .day, value: -daysBack, to: to) ?? to
        let sources = makeSources()

        var activityLists: [[Activity]] = []
        var wellnessLists: [[DailyWellness]] = []
        var errors: [String] = []

        await withTaskGroup(of: (DataSourceKind, [Activity], [DailyWellness], String?).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        async let a = source.fetchActivities(from: from, to: to)
                        async let w = source.fetchWellness(from: from, to: to)
                        return (source.kind, try await a, try await w, nil)
                    } catch {
                        return (source.kind, [], [], "\(source.kind.displayName): \(error.localizedDescription)")
                    }
                }
            }
            for await (_, a, w, err) in group {
                activityLists.append(a)
                wellnessLists.append(w)
                if let err { errors.append(err) }
            }
        }

        var merged = ActivityMerger.merge(activityLists)
        for i in merged.indices { merged[i].tss = TrainingLoad.tss(for: merged[i], profile: profile) }
        activities = merged
        wellness = ActivityMerger.mergeWellness(wellnessLists)
        lastErrors = errors
        lastSync = Date()
        linkCompletedWorkouts()
        recomputeDerived()
        persistence.saveCache(.init(activities: activities, wellness: wellness))
        persistState()
    }

    /// TSS neu berechnen, z. B. nach Änderung von FTP/Schwellenwerten.
    func recalculateLoad() {
        for i in activities.indices { activities[i].tss = TrainingLoad.tss(for: activities[i], profile: profile) }
        recomputeDerived()
    }

    private func recomputeDerived() {
        let end = Calendar.training.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let start = Calendar.training.date(byAdding: .day, value: -180, to: end) ?? end
        loadSeries = TrainingLoad.performanceSeries(activities: activities, from: start, to: end)
    }

    /// Verknüpft erledigte Einheiten mit geplanten (gleicher Tag + Sportart).
    private func linkCompletedWorkouts() {
        let cal = Calendar.training
        for i in planned.indices where planned[i].completedActivityID == nil {
            if let match = activities.first(where: { $0.sport == planned[i].sport && cal.isDate($0.startDate, inSameDayAs: planned[i].date) }) {
                planned[i].completedActivityID = match.id
            }
        }
    }

    // MARK: Planung

    func addPlanned(_ workout: PlannedWorkout) async {
        var workout = workout
        if calendarSyncEnabled {
            workout.calendarEventIdentifier = try? await CalendarSyncService.shared.upsert(workout)
        }
        planned.append(workout)
        planned.sort { $0.date < $1.date }
    }

    func updatePlanned(_ workout: PlannedWorkout) async {
        guard let index = planned.firstIndex(where: { $0.id == workout.id }) else { return }
        var workout = workout
        if calendarSyncEnabled {
            workout.calendarEventIdentifier = try? await CalendarSyncService.shared.upsert(workout)
        }
        planned[index] = workout
    }

    func deletePlanned(_ workout: PlannedWorkout) {
        if let id = workout.calendarEventIdentifier { CalendarSyncService.shared.removeEvent(identifier: id) }
        planned.removeAll { $0.id == workout.id }
    }

    func logFuel(_ item: FuelItem) { fuelLog.append(FuelLogEntry(time: Date(), item: item)) }

    // MARK: Persistenz

    private func persistState() {
        persistence.saveState(.init(profile: profile, planned: planned, races: races, fuelLog: fuelLog,
                                    enabledSources: enabledSources, calendarSyncEnabled: calendarSyncEnabled,
                                    lastSync: lastSync))
    }
}

// MARK: - Abfragen

extension TrainingStore {
    func activities(sport: Sport? = nil, in interval: DateInterval) -> [Activity] {
        activities.filter { (sport == nil || $0.sport == sport) && interval.contains($0.startDate) }
    }

    func activity(id: String) -> Activity? { activities.first { $0.id == id } }

    struct Totals: Hashable {
        var count = 0
        var distance = 0.0
        var duration: TimeInterval = 0
        var tss = 0.0
        var elevation = 0.0
    }

    func totals(sport: Sport? = nil, in interval: DateInterval) -> Totals {
        activities(sport: sport, in: interval).reduce(into: Totals()) { t, a in
            t.count += 1
            t.distance += a.distance
            t.duration += a.duration
            t.tss += a.tss ?? 0
            t.elevation += a.elevationGain ?? 0
        }
    }

    func planned(on day: Date) -> [PlannedWorkout] {
        planned.filter { Calendar.training.isDate($0.date, inSameDayAs: day) }
    }

    var todayWellness: DailyWellness? {
        wellness.last { Calendar.training.isDateInToday($0.date) } ?? wellness.last
    }

    var nextRace: RaceGoal? {
        races.filter { $0.date >= Calendar.training.startOfDay(for: Date()) }.min { $0.date < $1.date }
    }

    var currentLoad: LoadPoint? {
        loadSeries.last { $0.date <= Date() }
    }
}

// MARK: - Lokale Persistenz (JSON in Application Support)

struct PersistedState: Codable {
    var profile: AthleteProfile
    var planned: [PlannedWorkout]
    var races: [RaceGoal]
    var fuelLog: [FuelLogEntry]
    var enabledSources: Set<DataSourceKind>
    var calendarSyncEnabled: Bool
    var lastSync: Date?
}

struct PersistedCache: Codable {
    var activities: [Activity]
    var wellness: [DailyWellness]
}

/// Bewusst simpel gehalten – für große Datenmengen später auf SwiftData/SQLite umstellen.
final class LocalPersistence: @unchecked Sendable {
    private let folder: URL
    private let queue = DispatchQueue(label: "de.tricoach.persistence", qos: .utility)

    init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TriCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private var stateURL: URL { folder.appendingPathComponent("state.json") }
    private var cacheURL: URL { folder.appendingPathComponent("cache.json") }

    func loadState() -> PersistedState? { load(stateURL) }
    func loadCache() -> PersistedCache? { load(cacheURL) }
    func saveState(_ state: PersistedState) { save(state, to: stateURL) }
    func saveCache(_ cache: PersistedCache) { save(cache, to: cacheURL) }

    private func load<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        queue.async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
