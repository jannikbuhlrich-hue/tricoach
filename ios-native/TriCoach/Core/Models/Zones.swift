import Foundation

struct TrainingZone: Identifiable, Hashable, Codable, Sendable {
    var id: Int { index }
    let index: Int
    let name: String
    let lower: Double
    let upper: Double

    func contains(_ value: Double) -> Bool { value >= lower && value < upper }
}

enum ZoneMetric: String, CaseIterable, Identifiable {
    case heartRate, pace, power
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .heartRate: return "Herzfrequenz"
        case .pace: return "Pace"
        case .power: return "Leistung"
        }
    }
}

enum ZoneCalculator {
    /// HF-Zonen nach Joe Friel (basierend auf LTHR)
    static func heartRateZones(lthr: Int) -> [TrainingZone] {
        let l = Double(lthr)
        return [
            TrainingZone(index: 1, name: "Z1 Regeneration", lower: 0, upper: l * 0.85),
            TrainingZone(index: 2, name: "Z2 Grundlage", lower: l * 0.85, upper: l * 0.90),
            TrainingZone(index: 3, name: "Z3 Tempo", lower: l * 0.90, upper: l * 0.95),
            TrainingZone(index: 4, name: "Z4 Schwelle", lower: l * 0.95, upper: l * 1.00),
            TrainingZone(index: 5, name: "Z5 VO2max", lower: l * 1.00, upper: 260)
        ]
    }

    /// Leistungszonen nach Coggan (basierend auf FTP)
    static func powerZones(ftp: Int) -> [TrainingZone] {
        let f = Double(ftp)
        return [
            TrainingZone(index: 1, name: "Z1 Aktive Erholung", lower: 0, upper: f * 0.55),
            TrainingZone(index: 2, name: "Z2 Ausdauer", lower: f * 0.55, upper: f * 0.75),
            TrainingZone(index: 3, name: "Z3 Tempo", lower: f * 0.75, upper: f * 0.90),
            TrainingZone(index: 4, name: "Z4 Schwelle", lower: f * 0.90, upper: f * 1.05),
            TrainingZone(index: 5, name: "Z5 VO2max", lower: f * 1.05, upper: f * 1.20),
            TrainingZone(index: 6, name: "Z6 Anaerob", lower: f * 1.20, upper: f * 1.50),
            TrainingZone(index: 7, name: "Z7 Neuromuskulär", lower: f * 1.50, upper: 3000)
        ]
    }

    /// Pace-Zonen als Geschwindigkeit (m/s), damit „höher = härter“ wie bei HF/Watt gilt.
    static func runSpeedZones(thresholdPace: TimeInterval) -> [TrainingZone] {
        let t = 1000 / thresholdPace
        return [
            TrainingZone(index: 1, name: "Z1 Locker", lower: 0, upper: t * 0.78),
            TrainingZone(index: 2, name: "Z2 Grundlage", lower: t * 0.78, upper: t * 0.88),
            TrainingZone(index: 3, name: "Z3 Marathon", lower: t * 0.88, upper: t * 0.95),
            TrainingZone(index: 4, name: "Z4 Schwelle", lower: t * 0.95, upper: t * 1.02),
            TrainingZone(index: 5, name: "Z5 Intervall", lower: t * 1.02, upper: 15)
        ]
    }

    static func swimSpeedZones(css: TimeInterval) -> [TrainingZone] {
        let c = 100 / css
        return [
            TrainingZone(index: 1, name: "Z1 Locker", lower: 0, upper: c * 0.85),
            TrainingZone(index: 2, name: "Z2 Grundlage", lower: c * 0.85, upper: c * 0.93),
            TrainingZone(index: 3, name: "Z3 Tempo", lower: c * 0.93, upper: c * 0.98),
            TrainingZone(index: 4, name: "Z4 CSS", lower: c * 0.98, upper: c * 1.03),
            TrainingZone(index: 5, name: "Z5 Sprint", lower: c * 1.03, upper: 5)
        ]
    }

    /// Zeit in Zonen (Sekunden) – Pausen > 60 s zwischen Samples werden ignoriert.
    static func timeInZones(samples: [Sample], zones: [TrainingZone], value: (Sample) -> Double?) -> [Int: TimeInterval] {
        var result: [Int: TimeInterval] = [:]
        guard samples.count > 1 else { return result }
        for i in 1..<samples.count {
            let dt = samples[i].offset - samples[i - 1].offset
            guard dt > 0, dt < 60, let v = value(samples[i]) else { continue }
            if let zone = zones.first(where: { $0.contains(v) }) {
                result[zone.index, default: 0] += dt
            }
        }
        return result
    }
}
