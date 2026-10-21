import Foundation

struct LoadPoint: Identifiable, Hashable, Sendable {
    var id: Date { date }
    let date: Date
    let tss: Double
    /// Fitness (Chronic Training Load, 42 Tage)
    let ctl: Double
    /// Ermüdung (Acute Training Load, 7 Tage)
    let atl: Double
    /// Form (Training Stress Balance) = CTL − ATL des Vortags
    let tsb: Double
}

/// TSS-Modelle à la TrainingPeaks + Performance Management Chart.
enum TrainingLoad {
    static func tss(for a: Activity, profile: AthleteProfile) -> Double {
        let hours = a.duration / 3600
        guard hours > 0 else { return 0 }
        switch a.sport {
        case .bike:
            if let np = a.bike?.normalizedPower, np > 0, profile.ftp > 0 {
                let intensity = Double(np) / Double(profile.ftp)
                return hours * intensity * intensity * 100
            }
        case .run:
            if a.distance > 0 {
                // rTSS über Normalized Graded Pace ≈ Durchschnittspace (flaches Gelände)
                let intensity = a.avgSpeed / profile.thresholdRunSpeed
                return hours * intensity * intensity * 100
            }
        case .swim:
            if a.distance > 0 {
                // sTSS: dritte Potenz wegen des quadratisch steigenden Wasserwiderstands
                let intensity = a.avgSpeed / profile.cssSpeed
                return hours * pow(intensity, 3) * 100
            }
        default:
            break
        }
        return hrTSS(a, profile: profile)
    }

    /// Fallback über Herzfrequenz
    static func hrTSS(_ a: Activity, profile: AthleteProfile) -> Double {
        let hours = a.duration / 3600
        guard let hr = a.avgHeartRate else { return hours * 40 }
        let reserve = Double(profile.lactateThresholdHR - profile.restingHeartRate)
        guard reserve > 0 else { return hours * 40 }
        let intensity = min(1.2, max(0.3, Double(hr - profile.restingHeartRate) / reserve))
        return hours * intensity * intensity * 100
    }

    static func dailyTSS(_ activities: [Activity]) -> [Date: Double] {
        var map: [Date: Double] = [:]
        for a in activities { map[Calendar.training.startOfDay(for: a.startDate), default: 0] += a.tss ?? 0 }
        return map
    }

    /// Performance Management Chart. `future` erlaubt Projektionen (z. B. Tapering).
    static func performanceSeries(activities: [Activity], from: Date, to: Date,
                                  future: [Date: Double] = [:],
                                  seedCTL: Double = 0, seedATL: Double = 0) -> [LoadPoint] {
        let cal = Calendar.training
        var daily = dailyTSS(activities)
        for (day, tss) in future { daily[cal.startOfDay(for: day), default: 0] += tss }
        let earliest = activities.map(\.startDate).min() ?? from
        var ctl = seedCTL, atl = seedATL
        var points: [LoadPoint] = []
        let start = min(earliest, from)
        for day in cal.days(from: start, to: to) {
            let tss = daily[day] ?? 0
            let tsb = ctl - atl
            ctl += (tss - ctl) / 42
            atl += (tss - atl) / 7
            if day >= cal.startOfDay(for: from) {
                points.append(LoadPoint(date: day, tss: tss, ctl: ctl, atl: atl, tsb: tsb))
            }
        }
        return points
    }
}
