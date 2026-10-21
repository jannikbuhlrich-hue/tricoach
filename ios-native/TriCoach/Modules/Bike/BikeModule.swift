import SwiftUI
import Charts

struct BikeModule: AppModule {
    let id = "bike"
    let title = "Radfahren"
    let symbol = Sport.bike.symbol
    let tint = Sport.bike.tint
    let category = ModuleCategory.sport
    var sport: Sport? { .bike }

    func makeView(store: TrainingStore) -> AnyView {
        AnyView(BikeAnalysisView(viewModel: BikeAnalysisViewModel(store: store)))
    }

    func dashboardTiles(store: TrainingStore) -> [DashboardTile] {
        let week = store.totals(sport: .bike, in: Calendar.training.weekInterval(containing: Date()))
        return [DashboardTile(title: "Rad (Woche)", value: Fmt.km(week.distance, digits: 0),
                              subtitle: "\(week.count)× · \(Fmt.hoursMinutes(week.duration)) · \(Int(week.elevation)) Hm",
                              symbol: symbol, tint: tint)]
    }
}

@MainActor
@Observable
final class BikeAnalysisViewModel {
    let store: TrainingStore
    var curveDays = 90

    init(store: TrainingStore) { self.store = store }

    var rides: [Activity] { store.activities.filter { $0.sport == .bike } }
    var ftp: FTPEstimate { BikeAnalytics.estimateFTP(activities: rides, profile: store.profile) }
    var curve: [PowerCurvePoint] { BikeAnalytics.bestCurve(activities: rides, days: curveDays) }
    var aero: [AeroPoint] { BikeAnalytics.aeroTrend(activities: rides, profile: store.profile) }
    var zones: [TrainingZone] { ZoneCalculator.powerZones(ftp: store.profile.ftp) }
    var timeInZones: [Int: TimeInterval] { BikeAnalytics.timeInPowerZones(activities: rides, ftp: store.profile.ftp) }

    var aeroChangeText: String {
        let values = aero.map(\.cda)
        guard values.count > 4, let first = values.prefix(5).mean, let last = values.suffix(5).mean else { return "–" }
        let pct = (last - first) / first * 100
        let watts = AeroModel.power(speed: 10, cda: first, mass: store.profile.systemMass)
            - AeroModel.power(speed: 10, cda: last, mass: store.profile.systemMass)
        return "\(Fmt.number(pct, digits: 1)) % CdA ≈ \(Int(watts)) W Ersparnis bei 36 km/h"
    }

    func applyFTP() {
        store.profile.ftp = ftp.watts
        store.recalculateLoad()
    }
}

struct BikeAnalysisView: View {
    @State var viewModel: BikeAnalysisViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                ftpCard
                curveCard
                zonesCard
                aeroCard
            }
            .padding()
        }
        .navigationTitle("Radfahren")
    }

    private var ftpCard: some View {
        let ftp = viewModel.ftp
        return Card(title: "FTP-Schätzung", symbol: "bolt.fill") {
            TileGrid {
                MetricTile(title: "FTP", value: "\(ftp.watts)", unit: "W", subtitle: ftp.source,
                           symbol: "bolt.fill", tint: Sport.bike.tint)
                MetricTile(title: "Watt/kg", value: Fmt.number(ftp.wattsPerKg, digits: 2), unit: "W/kg",
                           subtitle: "bei \(Fmt.number(viewModel.store.profile.weightKg)) kg",
                           symbol: "scalemass", tint: Sport.bike.tint)
            }
            if ftp.suggestsUpdate {
                Button("Profil-FTP auf \(ftp.watts) W setzen") { viewModel.applyFTP() }
                    .buttonStyle(.borderedProminent)
                    .tint(Sport.bike.tint)
            }
        }
    }

    private var curveCard: some View {
        Card(title: "Leistungskurve", symbol: "chart.xyaxis.line") {
            Picker("Zeitraum", selection: $viewModel.curveDays) {
                Text("42 Tage").tag(42)
                Text("90 Tage").tag(90)
                Text("180 Tage").tag(180)
            }
            .pickerStyle(.segmented)
            Chart(viewModel.curve) { p in
                LineMark(x: .value("Dauer", p.label), y: .value("Watt", p.watts))
                    .foregroundStyle(Sport.bike.tint)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Dauer", p.label), y: .value("Watt", p.watts))
                    .foregroundStyle(Sport.bike.tint.opacity(0.15).gradient)
                    .interpolationMethod(.monotone)
            }
            .frame(height: 200)
        }
    }

    private var zonesCard: some View {
        let tiz = viewModel.timeInZones
        let total = max(1, tiz.values.reduce(0, +))
        return Card(title: "Leistungszonen (28 Tage)", symbol: "square.stack.3d.up") {
            ForEach(viewModel.zones) { z in
                ProgressRow(title: z.name,
                            progress: (tiz[z.index] ?? 0) / total,
                            detail: "\(Int(z.lower))–\(z.upper > 2000 ? "∞" : String(Int(z.upper))) W · \(Fmt.hoursMinutes(tiz[z.index] ?? 0))",
                            tint: Theme.zoneColor(z.index))
            }
        }
    }

    private var aeroCard: some View {
        Card(title: "Aerodynamik-Trend (CdA)", symbol: "wind") {
            if viewModel.aero.isEmpty {
                Text("Benötigt Fahrten mit Leistung, Geschwindigkeit und Höhe.").foregroundStyle(.secondary)
            } else {
                Chart(viewModel.aero) { p in
                    PointMark(x: .value("Datum", p.date), y: .value("CdA", p.cda))
                        .foregroundStyle(Sport.bike.tint.opacity(0.6))
                    LineMark(x: .value("Datum", p.date), y: .value("CdA", p.cda))
                        .foregroundStyle(Sport.bike.tint)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                Text("Veränderung: \(viewModel.aeroChangeText). Schätzung aus flachen, gleichmäßigen Abschnitten – ohne Windkorrektur nur als Trend lesen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
