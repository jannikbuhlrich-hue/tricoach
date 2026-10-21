import Foundation

struct SleepSummary: Codable, Hashable, Sendable {
    var total: TimeInterval
    var deep: TimeInterval
    var light: TimeInterval
    var rem: TimeInterval
    var awake: TimeInterval
    /// Garmin Sleep Score 0–100 (falls vorhanden)
    var score: Int?
}

/// Tageswerte aus Garmin Health API bzw. Apple Health.
struct DailyWellness: Identifiable, Codable, Hashable, Sendable {
    var id: Date { date }
    /// Tagesbeginn (lokal)
    var date: Date
    var restingHeartRate: Int?
    /// nächtlicher HRV-Mittelwert (ms, RMSSD bei Garmin / SDNN bei Apple)
    var hrvNightlyAvg: Double?
    var sleep: SleepSummary?
    var avgStress: Int?
    var bodyBatteryHigh: Int?
    var bodyBatteryLow: Int?
    /// Garmin Trainingsbereitschaft – nicht in jeder API-Stufe verfügbar, sonst nil
    var trainingReadiness: Int?
    var recoveryTimeHours: Double?
    var vo2maxRun: Double?
    var vo2maxBike: Double?
    var steps: Int?
    var source: DataSourceKind
}
