import SwiftUI
import UIKit

/// Wettkampfmodus: Stoppuhr mit Segment-Splits, Live-Zielzeitprognose und Fueling-Erinnerungen.
/// (Die Garmin-API liefert keine Live-Daten während der Aktivität – Splits werden hier per Tap gesetzt,
///  z. B. vom Betreuer am Streckenrand oder per Apple Watch/iPhone am Wechselplatz.)
struct LiveRaceView: View {
    let race: RaceGoal
    let prediction: RaceSplitPrediction
    let fuelPlan: [FuelingStep]

    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date? = nil
    @State private var segmentStart: Date? = nil
    @State private var splits: [TimeInterval] = []
    @State private var fuelTaken: [FuelLogEntry] = []

    private let segmentNames = ["Schwimmen", "T1", "Rad", "T2", "Laufen"]
    private var planned: [TimeInterval] { [prediction.swim, prediction.t1, prediction.bike, prediction.t2, prediction.run] }
    private var finished: Bool { splits.count == segmentNames.count }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = context.date
                let elapsed = startDate.map { now.timeIntervalSince($0) } ?? 0
                let current = segmentStart.map { now.timeIntervalSince($0) } ?? 0
                let projected = finished
                    ? splits.reduce(0, +)
                    : RaceSplitPredictor.liveProjection(prediction: prediction, completed: splits, currentElapsed: current)
                let delta = projected - prediction.total

                ScrollView {
                    VStack(spacing: 20) {
                        Text(Fmt.duration(finished ? splits.reduce(0, +) : elapsed))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        VStack(spacing: 4) {
                            Text(finished ? "Zielzeit" : "Prognose Ziel").font(.subheadline).foregroundStyle(.secondary)
                            Text(Fmt.duration(projected)).font(.title.weight(.semibold)).monospacedDigit()
                            Text("\(delta <= 0 ? "−" : "+")\(Fmt.duration(abs(delta))) vs. Plan")
                                .font(.headline)
                                .foregroundStyle(delta <= 0 ? .green : .orange)
                        }

                        segmentList(current: current)

                        if !finished {
                            Button(action: advance) {
                                Text(buttonTitle)
                                    .font(.title2.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(startDate == nil ? .green : Theme.accent)
                        }

                        if startDate != nil && !finished { fuelSection(elapsed: elapsed) }
                    }
                    .padding()
                }
            }
            .navigationTitle(race.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Fertig" : "Schließen") {
                        store.fuelLog.append(contentsOf: fuelTaken)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var buttonTitle: String {
        guard startDate != nil else { return "Start" }
        return "\(segmentNames[splits.count]) beendet"
    }

    private func advance() {
        let now = Date()
        if startDate == nil {
            startDate = now
            segmentStart = now
            return
        }
        if let s = segmentStart { splits.append(now.timeIntervalSince(s)) }
        segmentStart = finished ? nil : now
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    private func segmentList(current: TimeInterval) -> some View {
        VStack(spacing: 8) {
            ForEach(segmentNames.indices, id: \.self) { i in
                HStack {
                    Text(segmentNames[i]).font(.headline)
                        .foregroundStyle(i == splits.count && startDate != nil ? Theme.accent : .primary)
                    Spacer()
                    Text("Plan \(Fmt.duration(planned[i]))").font(.caption).foregroundStyle(.secondary)
                    if i < splits.count {
                        let diff = splits[i] - planned[i]
                        Text(Fmt.duration(splits[i])).monospacedDigit()
                        Text("\(diff <= 0 ? "−" : "+")\(Fmt.duration(abs(diff)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(diff <= 0 ? .green : .orange)
                    } else if i == splits.count && startDate != nil {
                        Text(Fmt.duration(current)).monospacedDigit().foregroundStyle(Theme.accent)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private func fuelSection(elapsed: TimeInterval) -> some View {
        let minute = Int(elapsed / 60)
        let next = fuelPlan.first { $0.minute >= minute }
        let totals = NutritionPlanner.totals(fuelTaken)
        let hours = max(elapsed / 3600, 0.1)
        return Card(title: "Fueling", symbol: "fork.knife") {
            if let next {
                Label("In \(next.minute - minute) min: \(next.item.name)", systemImage: "bell.fill")
                    .font(.headline)
                    .foregroundStyle(next.minute - minute <= 2 ? Color.orange : Color.primary)
            }
            Text("Bisher \(Int(totals.carbs)) g KH (\(Int(totals.carbs / hours)) g/h) · \(Int(totals.fluid)) ml")
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(FuelItem.defaults) { item in
                    Button {
                        fuelTaken.append(FuelLogEntry(time: Date(), item: item))
                    } label: {
                        Text(item.name).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
