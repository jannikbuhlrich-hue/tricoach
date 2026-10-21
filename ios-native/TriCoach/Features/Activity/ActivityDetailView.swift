import SwiftUI
import Charts
import MapKit

struct ActivityDetailView: View {
    let activity: Activity
    @Environment(TrainingStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    enum Metric: String, CaseIterable, Identifiable {
        case heartRate = "HF", pace = "Pace", power = "Leistung", cadence = "Kadenz", altitude = "Höhe"
        var id: String { rawValue }
    }
    @State private var metric: Metric = .heartRate

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                summary
                if activity.hasGPS {
                    Map {
                        MapPolyline(coordinates: activity.track)
                            .stroke(activity.sport.tint, lineWidth: 4)
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                }
                chartCard
                sportSpecific
                lapsCard
            }
            .padding()
        }
        .navigationTitle(activity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                if supportsMultipleWindows {
                    Button { openWindow(id: "activity", value: activity.id) } label: {
                        Image(systemName: "macwindow.on.rectangle")
                    }
                    .accessibilityLabel("In neuem Fenster öffnen")
                }
            }
        }
    }

    private var shareText: String {
        "\(activity.name): \(Fmt.km(activity.distance)) in \(Fmt.duration(activity.duration))"
            + (activity.tss.map { " · TSS \(Int($0))" } ?? "") + " – via TriCoach"
    }

    private var summary: some View {
        TileGrid {
            MetricTile(title: "Dauer", value: Fmt.duration(activity.duration), symbol: "timer", tint: activity.sport.tint)
            MetricTile(title: "Distanz", value: activity.sport == .swim ? Fmt.meters(activity.distance) : Fmt.km(activity.distance, digits: 2),
                       symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: activity.sport.tint)
            MetricTile(title: activity.sport == .bike ? "Geschwindigkeit" : "Pace",
                       value: paceText(activity.avgSpeed), symbol: "speedometer", tint: activity.sport.tint)
            if let hr = activity.avgHeartRate {
                MetricTile(title: "Ø Herzfrequenz", value: "\(hr)", unit: "bpm",
                           subtitle: activity.maxHeartRate.map { "max \($0)" }, symbol: "heart.fill", tint: .red)
            }
            if let tss = activity.tss {
                MetricTile(title: "TSS", value: "\(Int(tss))", subtitle: activity.aerobicTrainingEffect.map { "Aerober TE \(Fmt.number($0, digits: 1))" },
                           symbol: "flame.fill", tint: .orange)
            }
            if let gain = activity.elevationGain, gain > 0 {
                MetricTile(title: "Höhenmeter", value: Fmt.number(gain), unit: "m", symbol: "mountain.2.fill", tint: .brown)
            }
        }
    }

    private func paceText(_ speed: Double) -> String {
        switch activity.sport {
        case .bike: return Fmt.speedKmh(speed)
        case .swim: return Fmt.swimPace(speed: speed)
        default: return Fmt.pace(speed: speed)
        }
    }

    private func value(_ s: Sample) -> Double? {
        switch metric {
        case .heartRate: return s.heartRate.map(Double.init)
        case .pace: return s.speed.map { activity.sport == .bike ? $0 * 3.6 : $0 }
        case .power: return s.power.map(Double.init)
        case .cadence: return s.cadence.map(Double.init)
        case .altitude: return s.altitude
        }
    }

    private var availableMetrics: [Metric] {
        Metric.allCases.filter { m in
            switch m {
            case .heartRate: return activity.samples.contains { $0.heartRate != nil }
            case .pace: return activity.samples.contains { $0.speed != nil }
            case .power: return activity.samples.contains { $0.power != nil }
            case .cadence: return activity.samples.contains { $0.cadence != nil }
            case .altitude: return activity.samples.contains { $0.altitude != nil }
            }
        }
    }

    /// Für Charts auf ~400 Punkte reduzieren
    private var chartSamples: [Sample] {
        let step = max(1, activity.samples.count / 400)
        return stride(from: 0, to: activity.samples.count, by: step).map { activity.samples[$0] }
    }

    @ViewBuilder
    private var chartCard: some View {
        if !availableMetrics.isEmpty {
            Card(title: "Verlauf", symbol: "chart.xyaxis.line") {
                Picker("Metrik", selection: $metric) {
                    ForEach(availableMetrics) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Chart(chartSamples, id: \.offset) { s in
                    if let v = value(s) {
                        LineMark(x: .value("Minute", s.offset / 60), y: .value(metric.rawValue, v))
                            .foregroundStyle(metric == .heartRate ? Color.red : activity.sport.tint)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel("Minuten")
                .frame(height: 200)

                if metric == .heartRate {
                    let zones = ZoneCalculator.heartRateZones(lthr: store.profile.lactateThresholdHR)
                    let tiz = ZoneCalculator.timeInZones(samples: activity.samples, zones: zones) { $0.heartRate.map(Double.init) }
                    let total = max(1, tiz.values.reduce(0, +))
                    ForEach(zones) { z in
                        ProgressRow(title: z.name, progress: (tiz[z.index] ?? 0) / total,
                                    detail: Fmt.hoursMinutes(tiz[z.index] ?? 0), tint: Theme.zoneColor(z.index))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sportSpecific: some View {
        if let run = activity.run, run.avgGroundContactTime != nil || run.avgCadence != nil {
            Card(title: "Laufdynamik", symbol: "figure.run.motion") {
                TileGrid {
                    if let c = run.avgCadence { MetricTile(title: "Kadenz", value: Fmt.number(c), unit: "spm", symbol: "metronome", tint: Sport.run.tint) }
                    if let s = run.avgStrideLength { MetricTile(title: "Schrittlänge", value: Fmt.number(s, digits: 2), unit: "m", symbol: "ruler", tint: Sport.run.tint) }
                    if let g = run.avgGroundContactTime { MetricTile(title: "Bodenkontakt", value: Fmt.number(g), unit: "ms", symbol: "shoeprints.fill", tint: Sport.run.tint) }
                    if let v = run.avgVerticalOscillation { MetricTile(title: "Vert. Bewegung", value: Fmt.number(v, digits: 1), unit: "cm", symbol: "arrow.up.and.down", tint: Sport.run.tint) }
                }
            }
        }
        if let bike = activity.bike {
            Card(title: "Leistung", symbol: "bolt.fill") {
                TileGrid {
                    if let ap = bike.avgPower { MetricTile(title: "Ø Leistung", value: "\(ap)", unit: "W", symbol: "bolt", tint: Sport.bike.tint) }
                    if let np = bike.normalizedPower {
                        MetricTile(title: "Normalized Power", value: "\(np)", unit: "W",
                                   subtitle: "IF \(Fmt.number(Double(np) / Double(store.profile.ftp), digits: 2))",
                                   symbol: "bolt.fill", tint: Sport.bike.tint)
                    }
                    if let vi = BikeAnalytics.variabilityIndex(activity) {
                        MetricTile(title: "Variability Index", value: Fmt.number(vi, digits: 2), symbol: "waveform", tint: Sport.bike.tint)
                    }
                    if let cad = bike.avgCadence { MetricTile(title: "Kadenz", value: "\(cad)", unit: "rpm", symbol: "metronome", tint: Sport.bike.tint) }
                }
            }
        }
        if let swim = activity.swim, !swim.lengths.isEmpty {
            Card(title: "Bahnen & SWOLF", symbol: "water.waves") {
                Chart(swim.lengths.filter { $0.strokes > 0 }) { l in
                    BarMark(x: .value("Bahn", l.index + 1), y: .value("SWOLF", l.swolf))
                        .foregroundStyle(Sport.swim.tint.gradient)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
                HStack {
                    if let s = swim.avgSwolf { Text("Ø SWOLF \(Fmt.number(s, digits: 1))") }
                    Spacer()
                    if let r = swim.avgStrokeRate { Text("\(Fmt.number(r)) Züge/min") }
                    Spacer()
                    if let d = swim.distancePerStroke { Text("\(Fmt.number(d, digits: 2)) m/Zug") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var lapsCard: some View {
        if !activity.laps.isEmpty {
            Card(title: "Runden", symbol: "list.number") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("#"); Text("Zeit"); Text("Distanz"); Text(activity.sport == .bike ? "km/h" : "Pace"); Text("HF")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(activity.laps) { lap in
                        GridRow {
                            Text("\(lap.index + 1)").foregroundStyle(lap.isInterval ? activity.sport.tint : .primary)
                            Text(Fmt.duration(lap.duration))
                            Text(activity.sport == .swim ? Fmt.meters(lap.distance) : Fmt.km(lap.distance, digits: 2))
                            Text(paceText(lap.avgSpeed ?? 0))
                            Text(lap.avgHeartRate.map(String.init) ?? "–")
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }
}

/// Fenster-Variante für iPad Multi-Window
struct ActivityWindowView: View {
    let activityID: String?
    @Environment(TrainingStore.self) private var store

    var body: some View {
        NavigationStack {
            if let id = activityID, let activity = store.activity(id: id) {
                ActivityDetailView(activity: activity)
            } else {
                EmptyStateView(title: "Aktivität nicht gefunden", message: "Bitte erneut synchronisieren.", symbol: "questionmark.circle")
            }
        }
    }
}
