import Foundation

/// Jede Datenquelle (Garmin, Apple Health, FIT-Dateien, Mock) implementiert dieses Protokoll.
/// Neue Quellen (z. B. Wahoo, Strava) lassen sich so ohne Änderungen am Rest der App ergänzen.
protocol TrainingDataSource: Sendable {
    var kind: DataSourceKind { get }
    func fetchActivities(from: Date, to: Date) async throws -> [Activity]
    func fetchWellness(from: Date, to: Date) async throws -> [DailyWellness]
}

enum DataSourceError: LocalizedError {
    case notConfigured(String)
    case notAuthorized
    case invalidResponse(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "\(what) ist nicht konfiguriert."
        case .notAuthorized: return "Keine Berechtigung – bitte in den Einstellungen verbinden."
        case .invalidResponse(let code): return "Server antwortet mit Status \(code)."
        case .decoding(let msg): return "Daten konnten nicht gelesen werden: \(msg)"
        }
    }
}

/// Führt Aktivitäten aus mehreren Quellen zusammen und entfernt Duplikate
/// (gleiche Sportart, Start innerhalb von 3 Minuten). Die Quelle mit höherer Priorität gewinnt.
enum ActivityMerger {
    static func merge(_ lists: [[Activity]]) -> [Activity] {
        let all = lists.flatMap { $0 }.sorted { $0.source.priority > $1.source.priority }
        var result: [Activity] = []
        for activity in all {
            let duplicate = result.contains {
                $0.sport == activity.sport && abs($0.startDate.timeIntervalSince(activity.startDate)) < 180
            }
            if !duplicate { result.append(activity) }
        }
        return result.sorted { $0.startDate > $1.startDate }
    }

    static func mergeWellness(_ lists: [[DailyWellness]]) -> [DailyWellness] {
        var byDay: [Date: DailyWellness] = [:]
        for item in lists.flatMap({ $0 }).sorted(by: { $0.source.priority < $1.source.priority }) {
            let day = Calendar.training.startOfDay(for: item.date)
            if var existing = byDay[day] {
                // Höhere Priorität überschreibt nur vorhandene Werte
                existing.restingHeartRate = item.restingHeartRate ?? existing.restingHeartRate
                existing.hrvNightlyAvg = item.hrvNightlyAvg ?? existing.hrvNightlyAvg
                existing.sleep = item.sleep ?? existing.sleep
                existing.avgStress = item.avgStress ?? existing.avgStress
                existing.bodyBatteryHigh = item.bodyBatteryHigh ?? existing.bodyBatteryHigh
                existing.bodyBatteryLow = item.bodyBatteryLow ?? existing.bodyBatteryLow
                existing.trainingReadiness = item.trainingReadiness ?? existing.trainingReadiness
                existing.recoveryTimeHours = item.recoveryTimeHours ?? existing.recoveryTimeHours
                existing.vo2maxRun = item.vo2maxRun ?? existing.vo2maxRun
                existing.vo2maxBike = item.vo2maxBike ?? existing.vo2maxBike
                existing.steps = item.steps ?? existing.steps
                existing.source = item.source
                byDay[day] = existing
            } else {
                var copy = item
                copy.date = day
                byDay[day] = copy
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
}
