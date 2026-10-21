import Foundation

struct SwimTrendPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let swolf: Double
    let distancePerStroke: Double?
    let strokeRate: Double?
    let pace: TimeInterval   // s/100 m (nur aktive Bahnen)
}

struct StrokeRateBin: Identifiable, Hashable {
    var id: Int { rate }
    let rate: Int          // Züge/min (5er-Klassen)
    let speed: Double      // m/s
    let swolf: Double
    let count: Int
}

struct TechniqueReport: Hashable {
    /// Variationskoeffizient der Zugzahl (%) – niedrig = stabile Technik
    let strokeConsistency: Double
    /// Tempoverlust letztes vs. erstes Viertel (%)
    let dropOff: Double
    let distancePerStroke: Double?
    let avgSwolf: Double?
    let tips: [String]
}

/// Schwimmspezifische Analysen
enum SwimAnalytics {
    private static func freestyle(_ a: Activity) -> [SwimLength] {
        (a.swim?.lengths ?? []).filter { $0.strokeType == .freestyle && $0.strokes > 0 && $0.duration > 0 }
    }

    static func trend(activities: [Activity]) -> [SwimTrendPoint] {
        activities
            .filter { $0.sport == .swim }
            .compactMap { a -> SwimTrendPoint? in
                let lengths = freestyle(a)
                guard let pool = a.swim?.poolLength, !lengths.isEmpty,
                      let swolf = lengths.map({ Double($0.swolf) }).mean else { return nil }
                let time = lengths.reduce(0) { $0 + $1.duration }
                return SwimTrendPoint(date: a.startDate, swolf: swolf,
                                      distancePerStroke: a.swim?.distancePerStroke,
                                      strokeRate: lengths.map(\.strokeRate).mean,
                                      pace: time / (pool * Double(lengths.count)) * 100)
            }
            .sorted { $0.date < $1.date }
    }

    /// CSS = (T400 − T200) / 2 aus den schnellsten zusammenhängenden aktiven Bahnen der letzten 60 Tage.
    static func estimateCSS(activities: [Activity], days: Int = 60) -> TimeInterval? {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var best200 = Double.infinity, best400 = Double.infinity
        for a in activities where a.sport == .swim && a.startDate >= cutoff {
            guard let pool = a.swim?.poolLength, pool > 0 else { continue }
            let times = freestyle(a).map(\.duration)
            let n200 = Int((200 / pool).rounded()), n400 = Int((400 / pool).rounded())
            if let t = bestWindow(times, n200) { best200 = min(best200, t) }
            if let t = bestWindow(times, n400) { best400 = min(best400, t) }
        }
        guard best200.isFinite, best400.isFinite, best400 > best200 else { return nil }
        return (best400 - best200) / 2
    }

    private static func bestWindow(_ values: [Double], _ n: Int) -> Double? {
        guard n > 0, values.count >= n else { return nil }
        var sum = values[0..<n].reduce(0, +), best = sum
        if values.count > n {
            for i in n..<values.count { sum += values[i] - values[i - n]; best = min(best, sum) }
        }
        return best
    }

    /// Frequenzanalyse: Geschwindigkeit & SWOLF je Zugfrequenz-Klasse.
    static func strokeRateBins(activities: [Activity], days: Int = 60) -> [StrokeRateBin] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var groups: [Int: [(Double, Double)]] = [:]
        for a in activities where a.sport == .swim && a.startDate >= cutoff {
            guard let pool = a.swim?.poolLength else { continue }
            for l in freestyle(a) {
                let bin = Int((l.strokeRate / 5).rounded()) * 5
                groups[bin, default: []].append((pool / l.duration, Double(l.swolf)))
            }
        }
        return groups.compactMap { rate, values -> StrokeRateBin? in
            guard values.count >= 5 else { return nil }
            return StrokeRateBin(rate: rate, speed: values.map(\.0).mean ?? 0,
                                 swolf: values.map(\.1).mean ?? 0, count: values.count)
        }
        .sorted { $0.rate < $1.rate }
    }

    /// SWOLF-Optimierung: Zugzahl pro Bahn mit dem niedrigsten SWOLF.
    static func optimalStrokeCount(activities: [Activity]) -> (strokes: Int, swolf: Double)? {
        var groups: [Int: [Double]] = [:]
        for a in activities where a.sport == .swim {
            for l in freestyle(a) { groups[l.strokes, default: []].append(Double(l.swolf)) }
        }
        return groups
            .filter { $0.value.count >= 10 }
            .compactMap { k, v in v.mean.map { (k, $0) } }
            .min { $0.1 < $1.1 }
            .map { (strokes: $0.0, swolf: $0.1) }
    }

    static func technique(_ a: Activity) -> TechniqueReport? {
        let lengths = freestyle(a)
        guard lengths.count >= 8 else { return nil }
        let strokes = lengths.map { Double($0.strokes) }
        let cv = (strokes.standardDeviation ?? 0) / (strokes.mean ?? 1) * 100
        let quarter = max(1, lengths.count / 4)
        let firstPace = lengths.prefix(quarter).map(\.duration).mean ?? 0
        let lastPace = lengths.suffix(quarter).map(\.duration).mean ?? 0
        let dropOff = firstPace > 0 ? (lastPace - firstPace) / firstPace * 100 : 0
        let dps = a.swim?.distancePerStroke

        var tips: [String] = []
        if cv > 8 { tips.append("Zugzahl schwankt stark – Technik zerfällt unter Ermüdung. Kurze Serien mit fixer Zugzahl schwimmen.") }
        if dropOff > 5 { tips.append("Tempo bricht hinten raus ein (\(Fmt.number(dropOff, digits: 1)) %). Mehr CSS-Serien mit kurzen Pausen.") }
        if let dps, dps < 1.4 { tips.append("Wenig Vortrieb pro Zug (\(Fmt.number(dps, digits: 2)) m). Catch-up- und Abschlag-Drills, Ellbogen hoch.") }
        if tips.isEmpty { tips.append("Stabile Technik über die Einheit – weiter so.") }

        return TechniqueReport(strokeConsistency: cv, dropOff: dropOff, distancePerStroke: dps,
                               avgSwolf: lengths.map { Double($0.swolf) }.mean, tips: tips)
    }
}
