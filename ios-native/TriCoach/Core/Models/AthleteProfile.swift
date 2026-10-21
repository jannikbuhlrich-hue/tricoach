import Foundation

/// Leistungsdaten des Athleten – Basis für Zonen, TSS und Prognosen.
struct AthleteProfile: Codable, Hashable, Sendable {
    var name: String = "Athlet"
    var weightKg: Double = 68
    var heightCm: Double = 182
    var maxHeartRate: Int = 195
    var restingHeartRate: Int = 48
    /// Laktatschwellen-Herzfrequenz (LTHR)
    var lactateThresholdHR: Int = 172
    /// Functional Threshold Power (W)
    var ftp: Int = 260
    /// Schwellentempo Laufen in s/km
    var thresholdPace: TimeInterval = 250
    /// Critical Swim Speed in s/100 m
    var css: TimeInterval = 95
    var bikeWeightKg: Double = 8.5

    var thresholdRunSpeed: Double { 1000 / thresholdPace }
    var cssSpeed: Double { 100 / css }
    var ftpPerKg: Double { Double(ftp) / weightKg }
    var systemMass: Double { weightKg + bikeWeightKg }
}
