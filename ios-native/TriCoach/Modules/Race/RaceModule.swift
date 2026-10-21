import SwiftUI
import Charts

struct RaceModule: AppModule {
    let id = "race"
    let title = "Wettkampf"
    let symbol = "flag.checkered"
    let tint = Theme.accent
    let category = ModuleCategory.feature

    func makeView(store: TrainingStore) -> AnyView { AnyView(RaceListView()) }
}

struct RaceListView: View {
    @Environment(TrainingStore.self) private var store
    @State private var editing: RaceGoal? = nil

    var body: some View {
        List {
            ForEach(store.races.sorted { $0.date < $1.date }) { race in
                NavigationLink(value: Route.race(race.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(race.name).font(.headline)
                        Text("\(race.format.displayName) · \(Fmt.dayTitle(race.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { store.races.removeAll { $0.id == race.id } } label: { Label("Löschen", systemImage: "trash") }
                    Button { editing = race } label: { Label("Bearbeiten", systemImage: "pencil") }
                }
            }
        }
        .overlay {
            if store.races.isEmpty {
                EmptyStateView(title: "Kein Wettkampf", message: "Lege dein Saisonziel an.", symbol: "flag.checkered")
            }
        }
        .navigationTitle("Wettkämpfe")
        .toolbar {
            Button {
                editing = RaceGoal(name: "Neuer Wettkampf",
                                   date: Calendar.training.date(byAdding: .month, value: 3, to: Date()) ?? Date(),
                                   format: .olympic)
            } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editing) { race in
            RaceEditor(race: race) { saved in
                if let i = store.races.firstIndex(where: { $0.id == saved.id }) { store.races[i] = saved }
                else { store.races.append(saved) }
            }
        }
    }
}

struct RaceEditor: View {
    @State var race: RaceGoal
    let onSave: (RaceGoal) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $race.name)
                DatePicker("Datum", selection: $race.date, displayedComponents: .date)
                Picker("Distanz", selection: $race.format) {
                    ForEach(RaceFormat.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Temperatur: \(Int(race.expectedTemperatureC)) °C", value: $race.expectedTemperatureC, in: 5...40)
                VStack(alignment: .leading) {
                    Text("Radstrecke: \(race.bikeHilliness < 0.2 ? "flach" : (race.bikeHilliness < 0.6 ? "wellig" : "hügelig"))")
                    Slider(value: $race.bikeHilliness, in: 0...1)
                }
            }
            .navigationTitle("Wettkampf")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { onSave(race); dismiss() } }
            }
        }
    }
}

// MARK: - Detail: Prognose, Tapering, Fueling

@MainActor
@Observable
final class RaceDetailViewModel {
    let store: TrainingStore
    let raceID: UUID
    var wetsuit = true
    var cda = 0.30

    init(store: TrainingStore, raceID: UUID) {
        self.store = store
        self.raceID = raceID
        if let latest = BikeAnalytics.aeroTrend(activities: store.activities.filter { $0.sport == .bike }.prefix(10).map { $0 },
                                                profile: store.profile).last {
            cda = (latest.cda * 100).rounded() / 100
        }
    }

    var race: RaceGoal? { store.races.first { $0.id == raceID } }

    var prediction: RaceSplitPrediction? {
        guard let race else { return nil }
        return RaceSplitPredictor.predict(format: race.format, profile: store.profile, cda: cda,
                                          hilliness: race.bikeHilliness, wetsuit: wetsuit,
                                          temperatureC: race.expectedTemperatureC)
    }

    var taper: TaperResult? {
        guard let race, race.date > Date() else { return nil }
        return TaperAnalyzer.optimize(activities: store.activities, current: store.currentLoad, raceDate: race.date)
    }

    var fueling: (FuelingTarget, [FuelingStep])? {
        guard let race, let prediction else { return nil }
        return NutritionPlanner.plan(prediction: prediction, temperatureC: race.expectedTemperatureC, weightKg: store.profile.weightKg)
    }
}

struct RaceDetailView: View {
    @State var viewModel: RaceDetailViewModel
    @State private var showLive = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                if let race = viewModel.race, let p = viewModel.prediction {
                    predictionCard(race: race, p: p)
                    Button { showLive = true } label: {
                        Label("Wettkampfmodus starten", systemImage: "play.circle.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    taperCard
                    fuelingCard
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.race?.name ?? "Wettkampf")
        .fullScreenCover(isPresented: $showLive) {
            if let race = viewModel.race, let p = viewModel.prediction {
                LiveRaceView(race: race, prediction: p, fuelPlan: viewModel.fueling?.1 ?? [])
            }
        }
    }

    private func predictionCard(race: RaceGoal, p: RaceSplitPrediction) -> some View {
        Card(title: "Split-Prognose \(race.format.displayName)", symbol: "timer") {
            Text(Fmt.duration(p.total)).font(.system(size: 44, weight: .bold, design: .rounded))
            if let target = race.targetTime {
                Text("Ziel: \(Fmt.duration(target)) (\(p.total <= target ? "auf Kurs" : "+\(Fmt.duration(p.total - target))"))")
                    .font(.subheadline).foregroundStyle(p.total <= target ? .green : .orange)
            }
            TileGrid {
                MetricTile(title: "Schwimmen", value: Fmt.duration(p.swim), subtitle: "\(Fmt.paceValue(p.swimPace)) /100m",
                           symbol: Sport.swim.symbol, tint: Sport.swim.tint)
                MetricTile(title: "Wechsel", value: Fmt.duration(p.t1 + p.t2), subtitle: "T1 + T2", symbol: "arrow.triangle.swap", tint: .gray)
                MetricTile(title: "Rad", value: Fmt.duration(p.bike), subtitle: "\(Int(p.bikePower)) W · \(Fmt.speedKmh(p.bikeSpeed))",
                           symbol: Sport.bike.symbol, tint: Sport.bike.tint)
                MetricTile(title: "Laufen", value: Fmt.duration(p.run), subtitle: "\(Fmt.paceValue(p.runPace)) /km",
                           symbol: Sport.run.symbol, tint: Sport.run.tint)
            }
            Toggle("Neoprenanzug", isOn: $viewModel.wetsuit)
            VStack(alignment: .leading) {
                Text("CdA (Aeroposition): \(Fmt.number(viewModel.cda, digits: 2)) m²").font(.subheadline)
                Slider(value: $viewModel.cda, in: 0.20...0.40, step: 0.01)
            }
        }
    }

    @ViewBuilder
    private var taperCard: some View {
        if let taper = viewModel.taper {
            Card(title: "Tapering-Analyse", symbol: "chart.line.downtrend.xyaxis") {
                Text("Optimal: \(taper.plan.days) Tage Taper, Umfang −\(Int(taper.plan.reduction * 100)) %")
                    .font(.headline)
                Chart(taper.projection) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("Wert", p.ctl), series: .value("Kurve", "CTL"))
                        .foregroundStyle(Theme.fitness)
                    LineMark(x: .value("Datum", p.date), y: .value("Wert", p.tsb), series: .value("Kurve", "TSB"))
                        .foregroundStyle(Theme.form)
                }
                .frame(height: 180)
                HStack {
                    MetricTile(title: "Form am Renntag", value: "\(taper.raceDayTSB >= 0 ? "+" : "")\(Int(taper.raceDayTSB))",
                               subtitle: "Ziel +5 … +25", symbol: "sparkles", tint: Theme.form)
                    MetricTile(title: "Fitnessverlust", value: Fmt.number(taper.ctlLossPercent, digits: 1), unit: "%",
                               symbol: "arrow.down", tint: Theme.fitness)
                }
                Text(taper.verdict).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var fuelingCard: some View {
        if let fueling = viewModel.fueling {
            let target = fueling.0
            let steps = fueling.1
            Card(title: "Race-Day-Fueling", symbol: "fork.knife") {
                HStack {
                    MetricTile(title: "Kohlenhydrate", value: Fmt.number(target.carbsPerHour), unit: "g/h", symbol: "bolt.heart", tint: .orange)
                    MetricTile(title: "Flüssigkeit", value: Fmt.number(target.fluidMlPerHour), unit: "ml/h", symbol: "drop.fill", tint: .blue)
                    MetricTile(title: "Natrium", value: Fmt.number(target.sodiumMgPerHour), unit: "mg/h", symbol: "aqi.medium", tint: .gray)
                }
                ForEach(steps) { step in
                    HStack {
                        Text("min \(step.minute)").font(.subheadline.monospacedDigit()).frame(width: 70, alignment: .leading)
                        Image(systemName: step.segment.symbol).foregroundStyle(step.segment.tint)
                        Text(step.item.name)
                        Spacer()
                        Text("\(Int(step.item.carbsG)) g").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Text("Richtwerte – Verträglichkeit unbedingt in langen Trainingseinheiten testen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
