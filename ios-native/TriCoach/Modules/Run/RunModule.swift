import SwiftUI
import Charts

struct RunModule: AppModule {
    let id = "run"
    let title = "Laufen"
    let symbol = Sport.run.symbol
    let tint = Sport.run.tint
    let category = ModuleCategory.sport
    var sport: Sport? { .run }

    func makeView(store: TrainingStore) -> AnyView {
        AnyView(RunAnalysisView(viewModel: RunAnalysisViewModel(store: store)))
    }

    func dashboardTiles(store: TrainingStore) -> [DashboardTile] {
        let week = store.totals(sport: .run, in: Calendar.training.weekInterval(containing: Date()))
        return [DashboardTile(title: "Laufen (Woche)", value: Fmt.km(week.distance),
                              subtitle: "\(week.count)× · \(Fmt.hoursMinutes(week.duration))",
                              symbol: symbol, tint: tint)]
    }
}

@MainActor
@Observable
final class RunAnalysisViewModel {
    let store: TrainingStore
    var selectedIntervalSession: Activity? = nil

    init(store: TrainingStore) {
        self.store = store
        selectedIntervalSession = intervalSessions.first
    }

    var runs: [Activity] { store.activities.filter { $0.sport == .run } }
    var intervalSessions: [Activity] { runs.filter { RunAnalytics.intervals($0) != nil } }
    var intervalAnalysis: IntervalAnalysis? { selectedIntervalSession.flatMap(RunAnalytics.intervals) }
    var economy: [EconomyPoint] { RunAnalytics.economyTrend(activities: runs, profile: store.profile) }
    var predictions: (vdot: Double, times: [(String, TimeInterval)]) { RunAnalytics.predictions(activities: runs, profile: store.profile) }
    var weekly: [(week: Date, km: Double)] { RunAnalytics.weeklyDistance(activities: runs) }
    var decoupling: Double? { RunAnalytics.recentDecoupling(activities: runs) }

    var latestDynamics: RunDynamics? { runs.first(where: { $0.run?.avgGroundContactTime != nil })?.run }

    var efTrendText: String {
        let values = economy.suffix(12).map(\.efficiencyFactor)
        guard let slope = values.trendSlope, let mean = values.mean, mean > 0 else { return "zu wenig Daten" }
        let pct = slope * Double(values.count) / mean * 100
        return pct >= 0 ? "+\(Fmt.number(pct, digits: 1)) % (ökonomischer)" : "\(Fmt.number(pct, digits: 1)) %"
    }
}

struct RunAnalysisView: View {
    @State var viewModel: RunAnalysisViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                predictionCard
                weeklyCard
                intervalCard
                economyCard
                dynamicsCard
            }
            .padding()
        }
        .navigationTitle("Laufen")
    }

    private var predictionCard: some View {
        let p = viewModel.predictions
        return Card(title: "Tempoprognosen · VDOT \(Fmt.number(p.vdot, digits: 1))", symbol: "stopwatch") {
            TileGrid {
                ForEach(p.times, id: \.0) { item in
                    MetricTile(title: item.0, value: Fmt.duration(item.1),
                               subtitle: Fmt.paceValue(item.1 / (distanceFor(item.0) / 1000)) + " /km",
                               symbol: "flag.checkered", tint: Sport.run.tint)
                }
            }
            Text("Basierend auf deinen schnellsten zusammenhängenden Abschnitten der letzten 60 Tage (Daniels-VDOT).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func distanceFor(_ name: String) -> Double {
        RunPredictor.standardDistances.first { $0.name == name }?.meters ?? 10_000
    }

    private var weeklyCard: some View {
        Card(title: "Wochenkilometer", symbol: "chart.bar.fill") {
            Chart(viewModel.weekly, id: \.week) { item in
                BarMark(x: .value("Woche", item.week, unit: .weekOfYear), y: .value("km", item.km))
                    .foregroundStyle(Sport.run.tint.gradient)
                    .cornerRadius(4)
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var intervalCard: some View {
        Card(title: "Intervallanalyse", symbol: "repeat") {
            if viewModel.intervalSessions.isEmpty {
                Text("Noch keine Intervalleinheiten mit Runden gefunden.").foregroundStyle(.secondary)
            } else {
                Picker("Einheit", selection: $viewModel.selectedIntervalSession) {
                    ForEach(viewModel.intervalSessions.prefix(10)) { a in
                        Text("\(Fmt.shortDate(a.startDate)) – \(a.name)").tag(Optional(a))
                    }
                }
                .pickerStyle(.menu)

                if let analysis = viewModel.intervalAnalysis {
                    Chart(analysis.reps) { rep in
                        BarMark(x: .value("Wdh.", "\(rep.index)"), y: .value("Pace s/km", 1000 / max(rep.speed, 0.1)))
                            .foregroundStyle(Sport.run.tint)
                        if let hr = rep.heartRate {
                            PointMark(x: .value("Wdh.", "\(rep.index)"), y: .value("HF", Double(hr)))
                                .foregroundStyle(.red)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)

                    HStack {
                        MetricTile(title: "Tempoverlust", value: Fmt.number(analysis.fadePercent, digits: 1), unit: "%",
                                   symbol: "arrow.down.right", tint: analysis.fadePercent > 3 ? .orange : .green)
                        MetricTile(title: "Gleichmäßigkeit", value: Fmt.number(analysis.paceVariation, digits: 1), unit: "% CV",
                                   symbol: "equal.circle", tint: analysis.paceVariation > 3 ? .orange : .green)
                        if let drift = analysis.heartRateDrift {
                            MetricTile(title: "HF-Drift", value: "\(drift > 0 ? "+" : "")\(drift)", unit: "bpm",
                                       symbol: "heart", tint: .red)
                        }
                    }
                }
            }
        }
    }

    private var economyCard: some View {
        Card(title: "Laufökonomie", symbol: "leaf") {
            Chart(viewModel.economy) { p in
                LineMark(x: .value("Datum", p.date), y: .value("EF", p.efficiencyFactor))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Sport.run.tint)
                PointMark(x: .value("Datum", p.date), y: .value("EF", p.efficiencyFactor))
                    .foregroundStyle(Sport.run.tint.opacity(0.5))
                    .symbolSize(20)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            Text("Efficiency Factor (m/min pro Herzschlag) lockerer Läufe. Trend: \(viewModel.efTrendText)")
                .font(.caption).foregroundStyle(.secondary)
            if let d = viewModel.decoupling {
                ProgressRow(title: "Aerobe Entkopplung", progress: d / 10,
                            detail: "\(Fmt.number(d, digits: 1)) % (Ziel < 5 %)", tint: d > 5 ? .orange : .green)
            }
        }
    }

    @ViewBuilder
    private var dynamicsCard: some View {
        if let dyn = viewModel.latestDynamics {
            Card(title: "Laufdynamik (letzter Lauf)", symbol: "figure.run.motion") {
                TileGrid {
                    if let c = dyn.avgCadence {
                        MetricTile(title: "Kadenz", value: Fmt.number(c), unit: "spm", symbol: "metronome", tint: Sport.run.tint)
                    }
                    if let s = dyn.avgStrideLength {
                        MetricTile(title: "Schrittlänge", value: Fmt.number(s, digits: 2), unit: "m", symbol: "ruler", tint: Sport.run.tint)
                    }
                    if let g = dyn.avgGroundContactTime {
                        MetricTile(title: "Bodenkontaktzeit", value: Fmt.number(g), unit: "ms",
                                   subtitle: g < 240 ? "sehr gut" : (g < 270 ? "gut" : "ausbaufähig"),
                                   symbol: "shoeprints.fill", tint: Sport.run.tint)
                    }
                    if let v = dyn.avgVerticalOscillation {
                        MetricTile(title: "Vertikale Bewegung", value: Fmt.number(v, digits: 1), unit: "cm",
                                   symbol: "arrow.up.and.down", tint: Sport.run.tint)
                    }
                    if let r = dyn.avgVerticalRatio {
                        MetricTile(title: "Vertikales Verhältnis", value: Fmt.number(r, digits: 1), unit: "%",
                                   symbol: "percent", tint: Sport.run.tint)
                    }
                    if let p = dyn.avgPower {
                        MetricTile(title: "Laufleistung", value: Fmt.number(p), unit: "W", symbol: "bolt.fill", tint: Sport.run.tint)
                    }
                }
            }
        }
    }
}
