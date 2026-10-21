import Foundation

struct TaperPlan: Hashable {
    var days: Int
    /// Volumenreduktion 0…1 (0.45 = 45 % weniger)
    var reduction: Double
}

struct TaperResult: Hashable {
    let plan: TaperPlan
    let projection: [LoadPoint]
    let raceDayTSB: Double
    let raceDayCTL: Double
    let ctlLossPercent: Double

    var verdict: String {
        switch raceDayTSB {
        case ..<0: return "Zu müde am Renntag – Taper verlängern oder stärker reduzieren."
        case 0..<5: return "Leicht frisch – für B-Rennen ok."
        case 5...25 where ctlLossPercent < 12: return "Optimal: frisch bei erhaltener Fitness."
        case 5...25: return "Frisch, aber deutlicher Fitnessverlust – Taper kürzen."
        default: return "Zu viel Pause – Fitness geht verloren."
        }
    }
}

/// Simuliert die PMC bis zum Renntag und sucht den besten Taper.
enum TaperAnalyzer {
    static func baselineDailyTSS(activities: [Activity]) -> Double {
        let cutoff = Date().addingTimeInterval(-28 * 86_400)
        let recent = activities.filter { $0.startDate >= cutoff }
        return recent.reduce(0) { $0 + ($1.tss ?? 0) } / 28
    }

    static func simulate(activities: [Activity], current: LoadPoint?, raceDate: Date, plan: TaperPlan) -> TaperResult {
        let cal = Calendar.training
        let today = cal.startOfDay(for: Date())
        let race = cal.startOfDay(for: raceDate)
        let baseline = baselineDailyTSS(activities: activities)
        var future: [Date: Double] = [:]
        let taperStart = cal.date(byAdding: .day, value: -plan.days, to: race) ?? race
        for day in cal.days(from: cal.date(byAdding: .day, value: 1, to: today) ?? today, to: race) {
            if day >= race { future[day] = 0 }
            else if day >= taperStart { future[day] = baseline * (1 - plan.reduction) }
            else { future[day] = baseline }
        }
        let projection = TrainingLoad.performanceSeries(
            activities: [], from: today, to: race, future: future,
            seedCTL: current?.ctl ?? 0, seedATL: current?.atl ?? 0
        )
        let raceDay = projection.last
        let peakCTL = projection.map(\.ctl).max() ?? (current?.ctl ?? 0)
        let raceCTL = raceDay?.ctl ?? 0
        return TaperResult(plan: plan, projection: projection, raceDayTSB: raceDay?.tsb ?? 0, raceDayCTL: raceCTL,
                           ctlLossPercent: peakCTL > 0 ? (peakCTL - raceCTL) / peakCTL * 100 : 0)
    }

    /// Probiert Taper-Längen 5–21 Tage und Reduktionen 30–60 % durch.
    static func optimize(activities: [Activity], current: LoadPoint?, raceDate: Date) -> TaperResult? {
        var best: TaperResult?
        var bestScore = Double.infinity
        for days in stride(from: 5, through: 21, by: 2) {
            for reduction in stride(from: 0.3, through: 0.6, by: 0.05) {
                let r = simulate(activities: activities, current: current, raceDate: raceDate,
                                 plan: TaperPlan(days: days, reduction: reduction))
                // Ziel: TSB ≈ +15, Fitnessverlust minimal
                let score = abs(r.raceDayTSB - 15) + r.ctlLossPercent * 0.8
                if score < bestScore { bestScore = score; best = r }
            }
        }
        return best
    }
}
