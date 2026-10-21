import SwiftUI
import Charts

struct DashboardView: View {
    @State var viewModel: DashboardViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                header
                Picker("Zeitraum", selection: $viewModel.period) {
                    ForEach(DashboardViewModel.Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                triathlonTiles
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: Theme.spacing) {
                        volumeCard
                        loadCard
                    }
                    HStack(alignment: .top, spacing: Theme.spacing) {
                        zonesCard
                        insightsCard
                    }
                } else {
                    volumeCard
                    loadCard
                    zonesCard
                    insightsCard
                }
                raceCard
                recommendationsCard
                recentCard
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .refreshable {
            await viewModel.store.sync()
            await viewModel.refreshAnalysis()
        }
        .task(id: viewModel.store.lastSync) { await viewModel.refreshAnalysis() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.store.isSyncing { ProgressView() }
            }
        }
    }

    // MARK: Kopfbereich

    private var header: some View {
        let r = viewModel.readiness
        let load = viewModel.store.currentLoad
        return HStack(spacing: 20) {
            RingGauge(value: Double(r.score) / 100, label: "\(r.score)", caption: "Bereitschaft",
                      tint: r.level == .high ? .green : (r.level == .moderate ? .yellow : .red))
            VStack(alignment: .leading, spacing: 6) {
                Text(Fmt.dayTitle(Date())).font(.subheadline).foregroundStyle(.secondary)
                if viewModel.todayPlanned.isEmpty {
                    Text("Heute nichts geplant").font(.title3.weight(.semibold))
                } else {
                    ForEach(viewModel.todayPlanned) { w in
                        Label("\(w.title) · \(Fmt.hoursMinutes(w.plannedDuration))", systemImage: w.isCompleted ? "checkmark.circle.fill" : w.sport.symbol)
                            .font(.headline)
                            .foregroundStyle(w.isCompleted ? .green : w.sport.tint)
                    }
                }
                HStack(spacing: 12) {
                    statPill("Fitness", value: load?.ctl, color: Theme.fitness)
                    statPill("Ermüdung", value: load?.atl, color: Theme.fatigue)
                    statPill("Form", value: load?.tsb, color: Theme.form)
                }
                if r.recoveryHoursLeft > 1 {
                    Label("Erholung noch \(Int(r.recoveryHoursLeft)) h", systemImage: "bed.double.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private func statPill(_ title: String, value: Double?, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value.map { Fmt.number($0) } ?? "–").font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Kacheln

    private var triathlonTiles: some View {
        TileGrid {
            ForEach(Sport.triathlon) { sport in
                let t = viewModel.totals(sport)
                let prev = viewModel.previousTotals(sport)
                let delta = prev.duration > 0 ? (t.duration - prev.duration) / prev.duration * 100 : 0
                NavigationLink(value: Route.module(sport.rawValue)) {
                    MetricTile(title: sport.displayName,
                               value: sport == .swim ? Fmt.meters(t.distance) : Fmt.km(t.distance, digits: sport == .bike ? 0 : 1),
                               subtitle: "\(t.count)× · \(Fmt.hoursMinutes(t.duration)) · \(delta >= 0 ? "+" : "")\(Int(delta)) %",
                               symbol: sport.symbol, tint: sport.tint)
                }
                .buttonStyle(.plain)
            }
            let all = viewModel.totals(nil)
            MetricTile(title: "Gesamt", value: Fmt.hoursMinutes(all.duration),
                       subtitle: "TSS \(Int(all.tss)) · \(all.count) Einheiten", symbol: "sum", tint: Theme.accent)
        }
    }

    private var volumeCard: some View {
        Card(title: "Umfang pro Woche", symbol: "chart.bar.xaxis") {
            Chart(viewModel.weeklyVolume) { v in
                BarMark(x: .value("Woche", v.week, unit: .weekOfYear), y: .value("Stunden", v.hours))
                    .foregroundStyle(by: .value("Sport", v.sport.displayName))
            }
            .chartForegroundStyleScale([
                Sport.swim.displayName: Sport.swim.tint,
                Sport.bike.displayName: Sport.bike.tint,
                Sport.run.displayName: Sport.run.tint
            ])
            .frame(height: 200)
        }
    }

    private var loadCard: some View {
        Card(title: "Fitness · Ermüdung · Form", symbol: "waveform.path.ecg") {
            Chart(viewModel.loadSeries) { p in
                LineMark(x: .value("Datum", p.date), y: .value("Wert", p.ctl), series: .value("Kurve", "Fitness (CTL)"))
                    .foregroundStyle(Theme.fitness)
                LineMark(x: .value("Datum", p.date), y: .value("Wert", p.atl), series: .value("Kurve", "Ermüdung (ATL)"))
                    .foregroundStyle(Theme.fatigue.opacity(0.7))
                BarMark(x: .value("Datum", p.date, unit: .day), y: .value("TSB", p.tsb))
                    .foregroundStyle(p.tsb >= 0 ? Theme.form.opacity(0.5) : Color.gray.opacity(0.3))
            }
            .frame(height: 200)
            HStack(spacing: 16) {
                Label("Fitness", systemImage: "circle.fill").foregroundStyle(Theme.fitness)
                Label("Ermüdung", systemImage: "circle.fill").foregroundStyle(Theme.fatigue)
                Label("Form", systemImage: "circle.fill").foregroundStyle(Theme.form)
            }
            .font(.caption)
        }
    }

    private var zonesCard: some View {
        let zones = viewModel.heartRateZones
        let total = max(1, zones.reduce(0) { $0 + $1.time })
        return Card(title: "HF-Zonen (\(viewModel.period.rawValue))", symbol: "heart.fill") {
            ForEach(zones, id: \.zone.index) { item in
                ProgressRow(title: item.zone.name, progress: item.time / total,
                            detail: "\(Fmt.hoursMinutes(item.time)) · \(Int(item.time / total * 100)) %",
                            tint: Theme.zoneColor(item.zone.index))
            }
        }
    }

    private var insightsCard: some View {
        Card(title: "Stärken & Schwächen", symbol: "sparkle.magnifyingglass") {
            if viewModel.insights.isEmpty {
                Text("Analyse läuft …").foregroundStyle(.secondary)
            }
            ForEach(viewModel.insights) { InsightRow(insight: $0) }
        }
    }

    @ViewBuilder
    private var raceCard: some View {
        if !viewModel.racePreparations.isEmpty {
            Card(title: "Wettkampfvorbereitung", symbol: "flag.checkered") {
                ForEach(viewModel.racePreparations) { prep in
                    NavigationLink(value: Route.race(prep.race.id)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(prep.race.name).font(.headline)
                                Spacer()
                                Text("in \(prep.daysLeft) Tagen").font(.subheadline).foregroundStyle(.secondary)
                            }
                            ProgressRow(title: "Fitness (CTL) vs. Ziel", progress: prep.fitnessProgress,
                                        detail: "\(Int(prep.fitnessProgress * 100)) %", tint: Theme.fitness)
                            ProgressRow(title: "Vorbereitung", progress: prep.timeProgress,
                                        detail: "\(Int(prep.timeProgress * 100)) %", tint: Theme.accent)
                            Text("Prognose: \(Fmt.duration(prep.predicted)) · \(prep.race.format.displayName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recommendationsCard: some View {
        Card(title: "Trainingsempfehlungen", symbol: "brain.head.profile") {
            if viewModel.recommendations.isEmpty {
                Text("Alles im grünen Bereich – Plan weiter so umsetzen.").foregroundStyle(.secondary)
            }
            ForEach(viewModel.recommendations) { rec in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: rec.sport?.symbol ?? "sparkles")
                        .foregroundStyle(rec.sport?.tint ?? Theme.accent)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.title).font(.subheadline.weight(.semibold))
                        Text(rec.detail).font(.caption).foregroundStyle(.secondary)
                        if rec.suggestedWorkout != nil {
                            Button("In Kalender übernehmen") { Task { await viewModel.accept(rec) } }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var recentCard: some View {
        Card(title: "Letzte Einheiten", symbol: "clock.arrow.circlepath") {
            ForEach(viewModel.recentActivities) { a in
                NavigationLink(value: Route.activity(a.id)) { ActivityRow(activity: a) }
                    .buttonStyle(.plain)
                Divider()
            }
        }
    }
}
