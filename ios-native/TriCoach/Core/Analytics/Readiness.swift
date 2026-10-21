import Foundation

struct ReadinessResult: Hashable {
    enum Level: String { case low = "Niedrig", moderate = "Mittel", high = "Hoch" }
    let score: Int
    let level: Level
    let fromGarmin: Bool
    let factors: [String]
    let recoveryHoursLeft: Double
}

/// Nutzt Garmins Trainingsbereitschaft, wenn vorhanden – sonst eigene Berechnung
/// aus Schlaf, HRV relativ zur 7-Tage-Basis, Ruhepuls und Form (TSB).
enum ReadinessCalculator {
    static func evaluate(wellness: [DailyWellness], load: LoadPoint?, activities: [Activity]) -> ReadinessResult {
        let today = wellness.last
        var factors: [String] = []
        var score: Double

        let recovery = recoveryHoursLeft(activities: activities, garmin: today?.recoveryTimeHours)

        if let garmin = today?.trainingReadiness {
            score = Double(garmin)
            factors.append("Garmin Trainingsbereitschaft")
        } else {
            score = 55
            if let sleepScore = today?.sleep?.score {
                score += Double(sleepScore - 70) * 0.5
                factors.append("Schlaf \(sleepScore)/100")
            }
            let baseline = wellness.dropLast().suffix(7).compactMap(\.hrvNightlyAvg).mean
            if let hrv = today?.hrvNightlyAvg, let baseline, baseline > 0 {
                let ratio = hrv / baseline
                score += (ratio - 1) * 150
                factors.append("HRV \(Int(hrv)) ms (Basis \(Int(baseline)))")
            }
            let rhrBase = wellness.dropLast().suffix(7).compactMap { $0.restingHeartRate.map(Double.init) }.mean
            if let rhr = today?.restingHeartRate, let rhrBase {
                score -= (Double(rhr) - rhrBase) * 3
                factors.append("Ruhepuls \(rhr) bpm")
            }
            if let tsb = load?.tsb {
                score += tsb * 0.8
                factors.append("Form (TSB) \(Int(tsb))")
            }
            score -= recovery * 0.4
        }

        let clamped = Int(min(100, max(0, score)).rounded())
        let level: ReadinessResult.Level = clamped < 40 ? .low : (clamped < 70 ? .moderate : .high)
        return ReadinessResult(score: clamped, level: level, fromGarmin: today?.trainingReadiness != nil,
                               factors: factors, recoveryHoursLeft: recovery)
    }

    /// Erholungszeit: Garmin-Wert oder Schätzung aus TSS der letzten Einheiten.
    static func recoveryHoursLeft(activities: [Activity], garmin: Double?) -> Double {
        if let garmin { return garmin }
        let now = Date()
        let recent = activities.filter { now.timeIntervalSince($0.endDate) < 72 * 3600 }
        let remaining = recent.map { a -> Double in
            let needed = min(72, (a.tss ?? 0) * 0.35)
            return max(0, needed - now.timeIntervalSince(a.endDate) / 3600)
        }
        return remaining.max() ?? 0
    }
}
