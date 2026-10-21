import Foundation

struct FTPEstimate: Hashable {
    let watts: Int
    let wattsPerKg: Double
    let source: String
    /// true, wenn die Schätzung deutlich vom Profilwert abweicht
    let suggestsUpdate: Bool
}

struct AeroPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let cda: Double
}

struct PowerCurvePoint: Identifiable, Hashable {
    var id: Int { seconds }
    let seconds: Int
    let watts: Int

    var label: String {
        seconds < 60 ? "\(seconds)s" : (seconds < 3600 ? "\(seconds / 60)m" : "\(seconds / 3600)h")
    }
}

/// Radspezifische Analysen
enum BikeAnalytics {
    /// Beste Mean-Max-Werte über alle Fahrten im Zeitraum
    static func bestCurve(activities: [Activity], days: Int = 90) -> [PowerCurvePoint] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var best: [Int: Int] = [:]
        for a in activities where a.sport == .bike && a.startDate >= cutoff {
            for (d, w) in a.bike?.powerCurve ?? [:] { best[d] = max(best[d] ?? 0, w) }
        }
        return best.map { PowerCurvePoint(seconds: $0.key, watts: $0.value) }.sorted { $0.seconds < $1.seconds }
    }

    /// FTP-Schätzung aus 20-min (×0,95), 60-min und 8-min (×0,9) Bestwerten der letzten 6 Wochen.
    /// Ohne echte Maximalbelastung unterschätzen solche Werte – dann bleibt der Profilwert gültig.
    static func estimateFTP(activities: [Activity], profile: AthleteProfile) -> FTPEstimate {
        let curve = Dictionary(uniqueKeysWithValues: bestCurve(activities: activities, days: 42).map { ($0.seconds, $0.watts) })
        var candidates: [(Double, String)] = []
        if let p20 = curve[1200] { candidates.append((Double(p20) * 0.95, "95 % der besten 20 min")) }
        if let p60 = curve[3600] { candidates.append((Double(p60), "beste 60 min")) }
        if let p8 = curve[480] { candidates.append((Double(p8) * 0.9, "90 % der besten 8 min")) }

        if let best = candidates.max(by: { $0.0 < $1.0 }), best.0 >= Double(profile.ftp) * 0.93 {
            let watts = Int(best.0.rounded())
            return FTPEstimate(watts: watts, wattsPerKg: Double(watts) / profile.weightKg, source: best.1,
                               suggestsUpdate: abs(watts - profile.ftp) > max(5, profile.ftp / 40))
        }
        return FTPEstimate(watts: profile.ftp, wattsPerKg: profile.ftpPerKg,
                           source: "Profilwert (keine Maximalbelastung in 6 Wochen erkannt)", suggestsUpdate: false)
    }

    /// CdA-Trend aus stationären, flachen Abschnitten jeder Fahrt (Median).
    /// Ohne Wind-/Luftdichtedaten ist das ein Relativ-Indikator für Positionsverbesserungen.
    static func aeroTrend(activities: [Activity], profile: AthleteProfile) -> [AeroPoint] {
        activities
            .filter { $0.sport == .bike }
            .compactMap { a -> AeroPoint? in
                var estimates: [Double] = []
                let s = a.samples
                guard s.count > 2 else { return nil }
                for i in 1..<s.count {
                    guard let p = s[i].power, let v = s[i].speed,
                          let alt = s[i].altitude, let prevAlt = s[i - 1].altitude,
                          let prevV = s[i - 1].speed else { continue }
                    let dt = s[i].offset - s[i - 1].offset
                    guard dt > 0, abs(alt - prevAlt) / max(v * dt, 1) < 0.004, abs(v - prevV) < 0.3 else { continue }
                    if let cda = AeroModel.estimateCdA(power: Double(p), speed: v, mass: profile.systemMass) {
                        estimates.append(cda)
                    }
                }
                guard estimates.count > 30, let median = estimates.median else { return nil }
                return AeroPoint(date: a.startDate, cda: median)
            }
            .sorted { $0.date < $1.date }
    }

    static func timeInPowerZones(activities: [Activity], ftp: Int, days: Int = 28) -> [Int: TimeInterval] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let zones = ZoneCalculator.powerZones(ftp: ftp)
        var result: [Int: TimeInterval] = [:]
        for a in activities where a.sport == .bike && a.startDate >= cutoff {
            for (k, v) in ZoneCalculator.timeInZones(samples: a.samples, zones: zones, value: { $0.power.map(Double.init) }) {
                result[k, default: 0] += v
            }
        }
        return result
    }

    /// Variability Index (NP/AP) – > 1,05 = unruhig gefahren
    static func variabilityIndex(_ a: Activity) -> Double? {
        guard let np = a.bike?.normalizedPower, let ap = a.bike?.avgPower, ap > 0 else { return nil }
        return Double(np) / Double(ap)
    }
}
