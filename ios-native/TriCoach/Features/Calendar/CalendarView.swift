import SwiftUI

@MainActor
@Observable
final class CalendarViewModel {
    let store: TrainingStore
    var month: Date = Date()
    var selectedDay: Date = Calendar.training.startOfDay(for: Date())
    var editing: PlannedWorkout? = nil

    init(store: TrainingStore) { self.store = store }

    private var cal: Calendar { Calendar.training }

    var monthTitle: String {
        month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE")))
    }

    /// Tage im Raster (inkl. Füllern vom Vor-/Folgemonat, Wochenstart Montag)
    var gridDays: [Date] {
        let interval = cal.monthInterval(containing: month)
        let firstWeekStart = cal.weekInterval(containing: interval.start).start
        let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let lastWeekEnd = cal.weekInterval(containing: lastDay).end
        return cal.days(from: firstWeekStart, to: lastWeekEnd.addingTimeInterval(-1))
    }

    func isInMonth(_ day: Date) -> Bool { cal.isDate(day, equalTo: month, toGranularity: .month) }

    func sports(on day: Date) -> (done: [Sport], planned: [Sport]) {
        let done = store.activities.filter { cal.isDate($0.startDate, inSameDayAs: day) }.map(\.sport)
        let planned = store.planned(on: day).filter { !$0.isCompleted }.map(\.sport)
        return (done, planned)
    }

    func shiftMonth(_ value: Int) {
        month = cal.date(byAdding: .month, value: value, to: month) ?? month
    }

    var dayActivities: [Activity] { store.activities.filter { cal.isDate($0.startDate, inSameDayAs: selectedDay) } }
    var dayPlanned: [PlannedWorkout] { store.planned(on: selectedDay) }

    func newWorkout() -> PlannedWorkout {
        let date = cal.date(bySettingHour: 18, minute: 0, second: 0, of: selectedDay) ?? selectedDay
        return PlannedWorkout(date: date, sport: .run, title: "Lauf", plannedDuration: 3600)
    }

    func save(_ workout: PlannedWorkout) async {
        if store.planned.contains(where: { $0.id == workout.id }) { await store.updatePlanned(workout) }
        else { await store.addPlanned(workout) }
    }
}

struct CalendarView: View {
    @State var viewModel: CalendarViewModel
    private let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                monthGrid
                dayDetail
            }
            .padding()
        }
        .navigationTitle("Kalender")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { viewModel.editing = viewModel.newWorkout() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Einheit planen")
            }
        }
        .sheet(item: $viewModel.editing) { workout in
            PlannedWorkoutEditor(workout: workout) { saved in
                Task { await viewModel.save(saved) }
            } onDelete: { deleted in
                viewModel.store.deletePlanned(deleted)
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 12) {
            HStack {
                Button { viewModel.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(viewModel.monthTitle).font(.title3.weight(.semibold))
                Spacer()
                Button { viewModel.shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                ForEach(viewModel.gridDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private func dayCell(_ day: Date) -> some View {
        let sports = viewModel.sports(on: day)
        let selected = Calendar.training.isDate(day, inSameDayAs: viewModel.selectedDay)
        let today = Calendar.training.isDateInToday(day)
        return Button {
            viewModel.selectedDay = day
        } label: {
            VStack(spacing: 4) {
                Text("\(Calendar.training.component(.day, from: day))")
                    .font(.subheadline.weight(today ? .bold : .regular))
                    .foregroundStyle(viewModel.isInMonth(day) ? Color.primary : Color.secondary.opacity(0.5))
                HStack(spacing: 2) {
                    ForEach(Array(sports.done.prefix(3).enumerated()), id: \.offset) { _, s in
                        Circle().fill(s.tint).frame(width: 6, height: 6)
                    }
                    ForEach(Array(sports.planned.prefix(3).enumerated()), id: \.offset) { _, s in
                        Circle().stroke(s.tint, lineWidth: 1.5).frame(width: 6, height: 6)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? Theme.accent.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(today ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var dayDetail: some View {
        Card(title: Fmt.dayTitle(viewModel.selectedDay), symbol: "calendar") {
            if viewModel.dayPlanned.isEmpty && viewModel.dayActivities.isEmpty {
                Text("Keine Einheiten").foregroundStyle(.secondary)
            }
            ForEach(viewModel.dayPlanned) { w in
                Button { viewModel.editing = w } label: {
                    HStack {
                        Image(systemName: w.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(w.isCompleted ? .green : w.sport.tint)
                        VStack(alignment: .leading) {
                            Text(w.title).font(.subheadline.weight(.semibold))
                            Text("\(Fmt.time(w.date)) · \(Fmt.hoursMinutes(w.plannedDuration))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if w.calendarEventIdentifier != nil {
                            Image(systemName: "calendar.badge.checkmark").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(viewModel.dayActivities) { a in
                NavigationLink(value: Route.activity(a.id)) { ActivityRow(activity: a) }.buttonStyle(.plain)
            }
            Button {
                viewModel.editing = viewModel.newWorkout()
            } label: {
                Label("Einheit planen", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

struct PlannedWorkoutEditor: View {
    @State var workout: PlannedWorkout
    let onSave: (PlannedWorkout) -> Void
    let onDelete: (PlannedWorkout) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double = 60

    init(workout: PlannedWorkout, onSave: @escaping (PlannedWorkout) -> Void, onDelete: @escaping (PlannedWorkout) -> Void) {
        _workout = State(initialValue: workout)
        _minutes = State(initialValue: workout.plannedDuration / 60)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Sportart", selection: $workout.sport) {
                    ForEach(Sport.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
                }
                TextField("Titel", text: $workout.title)
                DatePicker("Datum", selection: $workout.date)
                Stepper("Dauer: \(Int(minutes)) min", value: $minutes, in: 10...480, step: 5)
                TextField("Notizen", text: $workout.notes, axis: .vertical).lineLimit(3...6)
                if workout.isCompleted {
                    Label("Erledigt", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
                Section {
                    Button("Löschen", role: .destructive) { onDelete(workout); dismiss() }
                }
            }
            .navigationTitle("Einheit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        workout.plannedDuration = minutes * 60
                        onSave(workout)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
