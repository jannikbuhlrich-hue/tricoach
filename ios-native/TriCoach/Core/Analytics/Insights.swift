import Foundation

struct Insight: Identifiable, Hashable {
    enum Kind: String { case strength, weakness, warning, info }
    var id = UUID()
    let kind: Kind
    let sport: Sport?
    let title: String
    let detail: String
}

struct SportScore: Identifiable, Hashable {
    var id: Sport { sport }
    let sport: Sport
    /// 0–100, relativ zu Referenzwerten ambitionierter Altersklassen-Athleten
    let performance: Double
    /// Einheiten pro Woche (letzte 4 Wochen)
    let frequency: Double
    let label: String
}

/// Automatische Stärken/Schwächen-Analyse über alle drei Disziplinen.
enum StrengthWeaknessAnalyzer {
    static func scores(activities: [Activity], profile: AthleteProfile) -> [SportScore] {
        let cutoff = Date().addingTimeInterval(-28 * 86_400)
        func freq(_ s: Sport) -> Double { Double(activities.filter { $0.sport == s && $0.startDate >= cutoff }.count) / 4 }

        let vdot = RunPredictor.estimateVDOT(from: activities) ?? RunPredictor.vdot(distance: 10_000, time: profile.thresholdPace * 10 * 1.04)
        let run = normalize(vdot, worst: 35, best: 70)
        let bike = normalize(BikeAnalytics.estimateFTP(activities: activities, profile: profile).wattsPerKg, worst: 2.0, best: 5.0)
        let css = SwimAnalytics.estimateCSS(activities: activities) ?? profile.css
        let swim = normalize(-css, worst: -140, best: -75)

        return [
            SportScore(sport: .swim, performance: swim, frequency: freq(.swim), label: "CSS \(Fmt.paceValue(css)) /100m"),
            SportScore(sport: .bike, performance: bike, frequency: freq(.bike),
                       label: "\(Fmt.number(BikeAnalytics.estimateFTP(activities: activities, profile: profile).wattsPerKg, digits: 1)) W/kg"),
            SportScore(sport: .run, performance: run, frequency: freq(.run), label: "VDOT \(Fmt.number(vdot, digits: 1))")
        ]
    }

    static func insights(activities: [Activity], profile: AthleteProfile, load: LoadPoint?) -> [Insight] {
        var result: [Insight] = []
        let scores = scores(activities: activities, profile: profile)
        if let strongest = scores.max(by: { $0.performance < $1.performance }),
           let weakest = scores.min(by: { $0.performance < $1.performance }) {
            result.append(Insight(kind: .strength, sport: strongest.sport, title: "Stärke: \(strongest.sport.displayName)",
                                  detail: "\(strongest.label) – Leistungsindex \(Int(strongest.performance))/100."))
            if weakest.sport != strongest.sport {
                result.append(Insight(kind: .weakness, sport: weakest.sport, title: "Potenzial: \(weakest.sport.displayName)",
                                      detail: "\(weakest.label) – größter Hebel für deine Gesamtzeit. Schlüsseleinheiten hier priorisieren."))
            }
        }
        for s in scores where s.frequency < 1.5 {
            result.append(Insight(kind: .warning, sport: s.sport, title: "Wenig \(s.sport.displayName)",
                                  detail: "Nur \(Fmt.number(s.frequency, digits: 1)) Einheiten/Woche. Für Fortschritt mindestens 2–3."))
        }

        // Intensitätsverteilung (HF) letzte 4 Wochen
        let cutoff = Date().addingTimeInterval(-28 * 86_400)
        let zones = ZoneCalculator.heartRateZones(lthr: profile.lactateThresholdHR)
        var tiz: [Int: TimeInterval] = [:]
        for a in activities where a.startDate >= cutoff {
            for (k, v) in ZoneCalculator.timeInZones(samples: a.samples, zones: zones, value: { $0.heartRate.map(Double.init) }) {
                tiz[k, default: 0] += v
            }
        }
        let total = tiz.values.reduce(0, +)
        if total > 0 {
            let easy = ((tiz[1] ?? 0) + (tiz[2] ?? 0)) / total
            let middle = (tiz[3] ?? 0) / total
            if middle > 0.25 {
                result.append(Insight(kind: .warning, sport: nil, title: "Zu viel „Grauzone“",
                                      detail: "\(Int(middle * 100)) % in Z3. Polarisiert trainieren: locker wirklich locker, hart wirklich hart."))
            } else if easy > 0.7 {
                result.append(Insight(kind: .info, sport: nil, title: "Gute Intensitätsverteilung",
                                      detail: "\(Int(easy * 100)) % im Grundlagenbereich – solide Basis."))
            }
        }

        // Aerobe Entkopplung bei langen Läufen
        if let decoupling = RunAnalytics.recentDecoupling(activities: activities), decoupling > 5 {
            result.append(Insight(kind: .warning, sport: .run, title: "Aerobe Entkopplung \(Fmt.number(decoupling, digits: 1)) %",
                                  detail: "Pace:HF driftet in langen Läufen. Mehr lange, lockere Läufe in Z2."))
        }

        if let tsb = load?.tsb, tsb < -30 {
            result.append(Insight(kind: .warning, sport: nil, title: "Hohe Ermüdung",
                                  detail: "TSB \(Int(tsb)). Risiko für Übertraining – Entlastung einplanen."))
        }
        return result
    }

    private static func normalize(_ value: Double, worst: Double, best: Double) -> Double {
        min(100, max(0, (value - worst) / (best - worst) * 100))
    }
}
