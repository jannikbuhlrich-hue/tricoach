import Foundation
import Observation

struct WeeklyVolume: Identifiable, Hashable {
    var id: String { "\(week.timeIntervalSince1970)-\(sport.rawValue)" }
    let week: Date
    let sport: Sport
    let hours: Double
}

struct RacePreparation: Identifiable, Hashable {
    var id: UUID { race.id }
    let race: RaceGoal
    let daysLeft: Int
    let fitnessProgress: Double   // CTL / Ziel-CTL
    let timeProgress: Double      // Anteil der Vorbereitung (16 Wochen) verstrichen
    let predicted: TimeInterval
}

@MainActor
@Observable
final class DashboardViewModel {
    enum Period: String, CaseIterable, Identifiable {
        case week = "Woche", month = "Monat"
        var id: String { rawValue }
    }

    let store: TrainingStore
    var period: Period = .week
    private(set) var recommendations: [Recommendation] = []
    private(set) var insights: [Insight] = []
    var coach: any CoachingEngine = RuleBasedCoach()

    init(store: TrainingStore) { self.store = store }

    var interval: DateInterval {
        period == .week ? Calendar.training.weekInterval(containing: Date()) : Calendar.training.monthInterval(containing: Date())
    }

    var previousInterval: DateInterval {
        let cal = Calendar.training
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        let start = cal.date(byAdding: component, value: -1, to: interval.start) ?? interval.start
        return DateInterval(start: start, end: interval.start)
    }

    func totals(_ sport: Sport?) -> TrainingStore.Totals { store.totals(sport: sport, in: interval) }
    func previousTotals(_ sport: Sport?) -> TrainingStore.Totals { store.totals(sport: sport, in: previousInterval) }

    var readiness: ReadinessResult {
        ReadinessCalculator.evaluate(wellness: store.wellness, load: store.currentLoad, activities: store.activities)
    }

    var todayPlanned: [PlannedWorkout] { store.planned(on: Date()) }

    var loadSeries: [LoadPoint] { Array(store.loadSeries.suffix(90)) }

    var weeklyVolume: [WeeklyVolume] {
        let cal = Calendar.training
        let thisWeek = cal.weekInterval(containing: Date()).start
        var result: [WeeklyVolume] = []
        for back in (0..<10).reversed() {
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { continue }
            let interval = DateInterval(start: start, duration: 7 * 86_400)
            for sport in Sport.triathlon {
                let hours = store.totals(sport: sport, in: interval).duration / 3600
                result.append(WeeklyVolume(week: start, sport: sport, hours: hours))
            }
        }
        return result
    }

    /// Zeit in HF-Zonen im gewählten Zeitraum
    var heartRateZones: [(zone: TrainingZone, time: TimeInterval)] {
        let zones = ZoneCalculator.heartRateZones(lthr: store.profile.lactateThresholdHR)
        var tiz: [Int: TimeInterval] = [:]
        for a in store.activities(in: interval) {
            for (k, v) in ZoneCalculator.timeInZones(samples: a.samples, zones: zones, value: { $0.heartRate.map(Double.init) }) {
                tiz[k, default: 0] += v
            }
        }
        return zones.map { ($0, tiz[$0.index] ?? 0) }
    }

    var racePreparations: [RacePreparation] {
        let cal = Calendar.training
        let ctl = store.currentLoad?.ctl ?? 0
        return store.races
            .filter { $0.date >= cal.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
            .map { race in
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: race.date)).day ?? 0
                let prep = 16.0 * 7
                let prediction = RaceSplitPredictor.predict(format: race.format, profile: store.profile,
                                                            hilliness: race.bikeHilliness, temperatureC: race.expectedTemperatureC)
                return RacePreparation(race: race, daysLeft: days, fitnessProgress: ctl / race.format.targetCTL,
                                       timeProgress: 1 - min(1, Double(days) / prep), predicted: prediction.total)
            }
    }

    var recentActivities: [Activity] { Array(store.activities.prefix(8)) }

    /// Analysen sind rechenintensiv → explizit nach Sync aktualisieren statt bei jedem Render.
    func refreshAnalysis() async {
        insights = StrengthWeaknessAnalyzer.insights(activities: store.activities, profile: store.profile, load: store.currentLoad)
        let context = CoachingContext(activities: store.activities, wellness: store.wellness, profile: store.profile,
                                      load: store.currentLoad, readiness: readiness, insights: insights,
                                      nextRace: store.nextRace, planned: store.planned)
        recommendations = await coach.recommendations(for: context)
    }

    func accept(_ recommendation: Recommendation) async {
        guard let workout = recommendation.suggestedWorkout else { return }
        await store.addPlanned(workout)
        recommendations.removeAll { $0.id == recommendation.id }
    }
}
