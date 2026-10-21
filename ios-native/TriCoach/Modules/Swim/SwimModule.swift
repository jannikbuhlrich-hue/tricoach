import SwiftUI
import Charts

struct SwimModule: AppModule {
    let id = "swim"
    let title = "Schwimmen"
    let symbol = Sport.swim.symbol
    let tint = Sport.swim.tint
    let category = ModuleCategory.sport
    var sport: Sport? { .swim }

    func makeView(store: TrainingStore) -> AnyView {
        AnyView(SwimAnalysisView(viewModel: SwimAnalysisViewModel(store: store)))
    }

    func dashboardTiles(store: TrainingStore) -> [DashboardTile] {
        let week = store.totals(sport: .swim, in: Calendar.training.weekInterval(containing: Date()))
        return [DashboardTile(title: "Schwimmen (Woche)", value: Fmt.meters(week.distance),
                              subtitle: "\(week.count)× · \(Fmt.hoursMinutes(week.duration))",
                              symbol: symbol, tint: tint)]
    }
}

@MainActor
@Observable
final class SwimAnalysisViewModel {
    let store: TrainingStore

    init(store: TrainingStore) { self.store = store }

    var swims: [Activity] { store.activities.filter { $0.sport == .swim } }
    var trend: [SwimTrendPoint] { SwimAnalytics.trend(activities: swims) }
    var css: TimeInterval? { SwimAnalytics.estimateCSS(activities: swims) }
    var bins: [StrokeRateBin] { SwimAnalytics.strokeRateBins(activities: swims) }
    var optimal: (strokes: Int, swolf: Double)? { SwimAnalytics.optimalStrokeCount(activities: swims) }
    var latestTechnique: (Activity, TechniqueReport)? {
        for a in swims { if let r = SwimAnalytics.technique(a) { return (a, r) } }
        return nil
    }
    var bestRate: StrokeRateBin? { bins.max { $0.speed < $1.speed } }

    func applyCSS() {
        guard let css else { return }
        store.profile.css = css.rounded()
        store.recalculateLoad()
    }
}

struct SwimAnalysisView: View {
    @State var viewModel: SwimAnalysisViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                overviewCard
                swolfCard
                frequencyCard
                techniqueCard
            }
            .padding()
        }
        .navigationTitle("Schwimmen")
    }

    private var overviewCard: some View {
        Card(title: "Schwimmform", symbol: "drop.fill") {
            TileGrid {
                MetricTile(title: "CSS (geschätzt)", value: viewModel.css.map(Fmt.paceValue) ?? "–", unit: "/100m",
                           subtitle: "Profil: \(Fmt.paceValue(viewModel.store.profile.css))",
                           symbol: "speedometer", tint: Sport.swim.tint)
                MetricTile(title: "Ø SWOLF", value: viewModel.trend.last.map { Fmt.number($0.swolf) } ?? "–",
                           subtitle: "letzte Einheit", symbol: "water.waves", tint: Sport.swim.tint)
                if let dps = viewModel.trend.last?.distancePerStroke {
                    MetricTile(title: "Distanz/Zug", value: Fmt.number(dps, digits: 2), unit: "m",
                               symbol: "arrow.left.and.right", tint: Sport.swim.tint)
                }
                if let opt = viewModel.optimal {
                    MetricTile(title: "Optimale Zugzahl", value: "\(opt.strokes)", unit: "/Bahn",
                               subtitle: "SWOLF \(Fmt.number(opt.swolf, digits: 1))", symbol: "target", tint: Sport.swim.tint)
                }
            }
            if let css = viewModel.css, abs(css - viewModel.store.profile.css) >= 2 {
                Button("Profil-CSS auf \(Fmt.paceValue(css)) setzen") { viewModel.applyCSS() }
                    .buttonStyle(.borderedProminent).tint(Sport.swim.tint)
            }
        }
    }

    private var swolfCard: some View {
        Card(title: "SWOLF-Trend", symbol: "chart.line.downtrend.xyaxis") {
            Chart(viewModel.trend) { p in
                LineMark(x: .value("Datum", p.date), y: .value("SWOLF", p.swolf))
                    .foregroundStyle(Sport.swim.tint)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Datum", p.date), y: .value("SWOLF", p.swolf))
                    .foregroundStyle(Sport.swim.tint.opacity(0.5))
                    .symbolSize(18)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            Text("SWOLF = Sekunden + Züge pro Bahn (Kraul, ohne Drills). Niedriger ist besser.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var frequencyCard: some View {
        Card(title: "Frequenzanalyse", symbol: "metronome") {
            if viewModel.bins.isEmpty {
                Text("Zu wenig Bahndaten (FIT-Import oder Garmin-Sync nötig).").foregroundStyle(.secondary)
            } else {
                Chart(viewModel.bins) { b in
                    BarMark(x: .value("Züge/min", "\(b.rate)"), y: .value("Pace s/100m", 100 / b.speed))
                        .foregroundStyle(b.rate == viewModel.bestRate?.rate ? Sport.swim.tint : Sport.swim.tint.opacity(0.35))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                if let best = viewModel.bestRate {
                    Text("Schnellste Pace bei ~\(best.rate) Zügen/min (\(Fmt.swimPace(speed: best.speed))). Mit Tempo-Trainer gezielt in diesem Bereich schwimmen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var techniqueCard: some View {
        if let tech = viewModel.latestTechnique {
            let report = tech.1
            Card(title: "Technikindikatoren · \(Fmt.shortDate(tech.0.startDate))", symbol: "figure.pool.swim") {
                TileGrid {
                    MetricTile(title: "Zugzahl-Konstanz", value: Fmt.number(report.strokeConsistency, digits: 1), unit: "% CV",
                               symbol: "equal.circle", tint: report.strokeConsistency > 8 ? .orange : .green)
                    MetricTile(title: "Tempoabfall", value: Fmt.number(report.dropOff, digits: 1), unit: "%",
                               symbol: "arrow.down.right", tint: report.dropOff > 5 ? .orange : .green)
                }
                ForEach(report.tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb").font(.subheadline)
                }
            }
        }
    }
}
