import Foundation

struct IntervalRep: Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let duration: TimeInterval
    let distance: Double
    let speed: Double
    let heartRate: Int?
}

struct IntervalAnalysis: Hashable {
    let reps: [IntervalRep]
    /// Tempoverlust letzte vs. erste Wiederholung (%), positiv = langsamer geworden
    let fadePercent: Double
    /// Variationskoeffizient der Pace (%) – < 2 % = sehr gleichmäßig
    let paceVariation: Double
    /// HF-Anstieg über die Serie (bpm)
    let heartRateDrift: Int?
}

struct EconomyPoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    /// Efficiency Factor: m/min pro Herzschlag
    let efficiencyFactor: Double
    /// Running Effectiveness: (m/s) / (W/kg) – typ. 0,95–1,05
    let effectiveness: Double?
    let groundContactTime: Double?
    let cadence: Double?
}

/// Laufspezifische Analysen
enum RunAnalytics {
    static func intervals(_ a: Activity) -> IntervalAnalysis? {
        let work = a.laps.filter(\.isInterval)
        guard work.count >= 2 else { return nil }
        let reps = work.enumerated().map { i, lap in
            IntervalRep(index: i + 1, duration: lap.duration, distance: lap.distance,
                        speed: lap.avgSpeed ?? (lap.duration > 0 ? lap.distance / lap.duration : 0),
                        heartRate: lap.avgHeartRate)
        }
        let speeds = reps.map(\.speed)
        let first = speeds.first ?? 0, last = speeds.last ?? 0
        let fade = first > 0 ? (first - last) / first * 100 : 0
        let cv = (speeds.standardDeviation ?? 0) / (speeds.mean ?? 1) * 100
        var drift: Int?
        if let h1 = reps.first?.heartRate, let h2 = reps.last?.heartRate { drift = h2 - h1 }
        return IntervalAnalysis(reps: reps, fadePercent: fade, paceVariation: cv, heartRateDrift: drift)
    }

    static func efficiencyFactor(_ a: Activity) -> Double? {
        guard a.sport == .run, let hr = a.avgHeartRate, hr > 0, a.avgSpeed > 0 else { return nil }
        return a.avgSpeed * 60 / Double(hr)
    }

    /// Aerobe Entkopplung (Pa:HR) – Vergleich 1. vs. 2. Hälfte, Warm-up (10 min) ausgenommen.
    static func decoupling(_ a: Activity) -> Double? {
        let samples = a.samples.filter { $0.offset > 600 && ($0.speed ?? 0) > 0 && ($0.heartRate ?? 0) > 0 }
        guard samples.count > 40 else { return nil }
        let mid = samples.count / 2
        func ef(_ s: ArraySlice<Sample>) -> Double? {
            guard let v = s.compactMap(\.speed).mean, let h = s.compactMap({ $0.heartRate.map(Double.init) }).mean, h > 0 else { return nil }
            return v / h
        }
        guard let ef1 = ef(samples[..<mid]), let ef2 = ef(samples[mid...]), ef1 > 0 else { return nil }
        return (ef1 - ef2) / ef1 * 100
    }

    /// Durchschnittliche Entkopplung langer, lockerer Läufe der letzten 30 Tage.
    static func recentDecoupling(activities: [Activity]) -> Double? {
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return activities
            .filter { $0.sport == .run && $0.startDate >= cutoff && $0.duration >= 60 * 60 && $0.laps.allSatisfy { !$0.isInterval } }
            .compactMap(decoupling)
            .mean
    }

    static func economyTrend(activities: [Activity], profile: AthleteProfile) -> [EconomyPoint] {
        activities
            .filter { $0.sport == .run && $0.laps.allSatisfy { !$0.isInterval } }
            .compactMap { a -> EconomyPoint? in
                guard let ef = efficiencyFactor(a) else { return nil }
                let effectiveness = a.run?.avgPower.map { a.avgSpeed / ($0 / profile.weightKg) }
                return EconomyPoint(date: a.startDate, efficiencyFactor: ef, effectiveness: effectiveness,
                                    groundContactTime: a.run?.avgGroundContactTime, cadence: a.run?.avgCadence)
            }
            .sorted { $0.date < $1.date }
    }

    static func predictions(activities: [Activity], profile: AthleteProfile) -> (vdot: Double, times: [(String, TimeInterval)]) {
        let vdot = RunPredictor.estimateVDOT(from: activities)
            ?? RunPredictor.vdot(distance: 10_000, time: profile.thresholdPace * 10 * 1.04)
        let times = RunPredictor.standardDistances.map { ($0.name, RunPredictor.predictTime(vdot: vdot, distance: $0.meters)) }
        return (vdot, times)
    }

    static func weeklyDistance(activities: [Activity], weeks: Int = 12) -> [(week: Date, km: Double)] {
        let cal = Calendar.training
        let thisWeek = cal.weekInterval(containing: Date()).start
        return (0..<weeks).reversed().compactMap { back -> (Date, Double)? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { return nil }
            let interval = DateInterval(start: start, duration: 7 * 86_400)
            let km = activities.filter { $0.sport == .run && interval.contains($0.startDate) }.reduce(0) { $0 + $1.distance } / 1000
            return (start, km)
        }
    }
}
