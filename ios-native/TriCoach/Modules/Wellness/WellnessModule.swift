import SwiftUI
import Charts

struct WellnessModule: AppModule {
    let id = "wellness"
    let title = "Schlaf & Stress"
    let symbol = "bed.double.fill"
    let tint = Color.indigo
    let category = ModuleCategory.feature

    func makeView(store: TrainingStore) -> AnyView { AnyView(WellnessView()) }

    func dashboardTiles(store: TrainingStore) -> [DashboardTile] {
        guard let w = store.todayWellness else { return [] }
        return [DashboardTile(title: "Schlaf", value: w.sleep.map { Fmt.hoursMinutes($0.total) } ?? "–",
                              subtitle: w.sleep?.score.map { "Score \($0)" }, symbol: symbol, tint: tint)]
    }
}

struct SleepStage: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(stage)" }
    let date: Date
    let stage: String
    let hours: Double
}

struct WellnessView: View {
    @Environment(TrainingStore.self) private var store

    private var last28: [DailyWellness] { Array(store.wellness.suffix(28)) }

    private var sleepStages: [SleepStage] {
        last28.suffix(14).flatMap { w -> [SleepStage] in
            guard let s = w.sleep else { return [] }
            return [
                SleepStage(date: w.date, stage: "Tief", hours: s.deep / 3600),
                SleepStage(date: w.date, stage: "Leicht", hours: s.light / 3600),
                SleepStage(date: w.date, stage: "REM", hours: s.rem / 3600),
                SleepStage(date: w.date, stage: "Wach", hours: s.awake / 3600)
            ]
        }
    }

    private var hrvBaseline: Double? { last28.compactMap(\.hrvNightlyAvg).mean }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                todayTiles
                Card(title: "Schlafphasen (14 Tage)", symbol: "moon.zzz.fill") {
                    Chart(sleepStages) { s in
                        BarMark(x: .value("Tag", s.date, unit: .day), y: .value("Stunden", s.hours))
                            .foregroundStyle(by: .value("Phase", s.stage))
                    }
                    .chartForegroundStyleScale(["Tief": Color.indigo, "Leicht": Color.blue, "REM": Color.purple, "Wach": Color.orange])
                    .frame(height: 200)
                }
                Card(title: "HRV-Trend", symbol: "waveform.path.ecg.rectangle") {
                    Chart {
                        ForEach(last28.filter { $0.hrvNightlyAvg != nil }) { w in
                            LineMark(x: .value("Tag", w.date), y: .value("HRV", w.hrvNightlyAvg ?? 0))
                                .foregroundStyle(.green)
                                .interpolationMethod(.catmullRom)
                        }
                        if let base = hrvBaseline {
                            RuleMark(y: .value("Basis", base))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(.secondary)
                                .annotation(position: .top, alignment: .leading) {
                                    Text("Ø \(Int(base)) ms").font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    Text("Liegt die HRV mehrere Tage deutlich unter der Basis, ist das ein Signal für Erholungsbedarf.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Card(title: "Ruhepuls & Stress", symbol: "heart.text.square") {
                    Chart {
                        ForEach(last28.filter { $0.restingHeartRate != nil }) { w in
                            LineMark(x: .value("Tag", w.date), y: .value("Wert", w.restingHeartRate ?? 0), series: .value("Kurve", "Ruhepuls"))
                                .foregroundStyle(.red)
                        }
                        ForEach(last28.filter { $0.avgStress != nil }) { w in
                            LineMark(x: .value("Tag", w.date), y: .value("Wert", w.avgStress ?? 0), series: .value("Kurve", "Stress"))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(height: 180)
                    HStack(spacing: 16) {
                        Label("Ruhepuls (bpm)", systemImage: "circle.fill").foregroundStyle(.red)
                        Label("Garmin-Stress (0–100)", systemImage: "circle.fill").foregroundStyle(.orange)
                    }
                    .font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle("Schlaf & Stress")
    }

    @ViewBuilder
    private var todayTiles: some View {
        if let w = store.todayWellness {
            TileGrid {
                if let s = w.sleep {
                    MetricTile(title: "Schlaf", value: Fmt.hoursMinutes(s.total), subtitle: s.score.map { "Score \($0)/100" },
                               symbol: "bed.double.fill", tint: .indigo)
                }
                if let hrv = w.hrvNightlyAvg {
                    MetricTile(title: "HRV", value: "\(Int(hrv))", unit: "ms",
                               subtitle: hrvBaseline.map { "Basis \(Int($0)) ms" }, symbol: "waveform.path.ecg", tint: .green)
                }
                if let rhr = w.restingHeartRate {
                    MetricTile(title: "Ruhepuls", value: "\(rhr)", unit: "bpm", symbol: "heart.fill", tint: .red)
                }
                if let stress = w.avgStress {
                    MetricTile(title: "Stress", value: "\(stress)", subtitle: stress < 26 ? "ruhig" : (stress < 51 ? "niedrig" : "erhöht"),
                               symbol: "brain.head.profile", tint: .orange)
                }
                if let bb = w.bodyBatteryHigh {
                    MetricTile(title: "Body Battery", value: "\(bb)", subtitle: w.bodyBatteryLow.map { "min \($0)" },
                               symbol: "battery.75percent", tint: .teal)
                }
                if let vo2 = w.vo2maxRun {
                    MetricTile(title: "VO2max Laufen", value: Fmt.number(vo2, digits: 1),
                               subtitle: w.vo2maxBike.map { "Rad \(Fmt.number($0, digits: 1))" }, symbol: "lungs.fill", tint: .mint)
                }
            }
        } else {
            EmptyStateView(title: "Keine Wellness-Daten", message: "Garmin oder Apple Health verbinden.", symbol: "bed.double")
        }
    }
}
