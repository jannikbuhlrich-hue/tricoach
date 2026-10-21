import AppIntents
import SwiftUI

// Hinweis: Apple verlangt den App-Namen in jeder Siri-Phrase der App Shortcuts.
// „Hey Siri, zeige mein heutiges Training in TriCoach“ – eigene Phrasen ohne App-Namen
// kann der Nutzer in der Kurzbefehle-App anlegen.

enum SportAppEnum: String, AppEnum {
    case swim, bike, run

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sportart"
    static let caseDisplayRepresentations: [SportAppEnum: DisplayRepresentation] = [
        .swim: "Schwimmeinheit",
        .bike: "Radeinheit",
        .run: "Laufeinheit"
    ]

    var sport: Sport { Sport(rawValue: rawValue) ?? .run }
}

// MARK: - „Zeige mein heutiges Training“

struct ShowTodayWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Heutiges Training anzeigen"
    static let description = IntentDescription("Zeigt die heute geplanten und erledigten Einheiten.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = TrainingStore.shared
        let cal = Calendar.training
        let today = DateInterval(start: cal.startOfDay(for: Date()), duration: 86_400)
        let planned = store.planned(on: Date())
        let done = store.activities(in: today)

        let text: String
        if planned.isEmpty && done.isEmpty {
            text = "Heute ist nichts geplant – Ruhetag."
        } else {
            var parts = planned.filter { !$0.isCompleted }.map { "\($0.title), \(Fmt.hoursMinutes($0.plannedDuration)) um \(Fmt.time($0.date))" }
            if !done.isEmpty { parts.append("\(done.count) Einheit\(done.count == 1 ? "" : "en") bereits erledigt") }
            text = "Heute: " + parts.joined(separator: ". ")
        }
        return .result(dialog: "\(text)", view: TodaySnippetView(planned: planned, done: done))
    }
}

struct TodaySnippetView: View {
    let planned: [PlannedWorkout]
    let done: [Activity]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(planned) { w in
                Label("\(w.title) · \(Fmt.hoursMinutes(w.plannedDuration))", systemImage: w.isCompleted ? "checkmark.circle.fill" : w.sport.symbol)
                    .foregroundStyle(w.sport.tint)
            }
            ForEach(done) { a in
                Label("\(a.name) · \(Fmt.km(a.distance))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if planned.isEmpty && done.isEmpty { Text("Ruhetag 😴") }
        }
        .padding()
    }
}

// MARK: - „Plane eine Radeinheit für morgen“

struct PlanWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Einheit planen"
    static let description = IntentDescription("Trägt eine Trainingseinheit in den TriCoach-Kalender ein.")

    @Parameter(title: "Sportart")
    var sport: SportAppEnum

    @Parameter(title: "Datum", description: "Standard: morgen 18 Uhr")
    var date: Date?

    @Parameter(title: "Dauer (Minuten)", default: 60, inclusiveRange: (10, 480))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Plane \(\.$sport) am \(\.$date) für \(\.$minutes) Minuten")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cal = Calendar.training
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let day = date ?? cal.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let titles: [SportAppEnum: String] = [.swim: "Schwimmen", .bike: "Radeinheit", .run: "Lauf"]
        let workout = PlannedWorkout(date: day, sport: sport.sport, title: titles[sport] ?? "Training",
                                     plannedDuration: TimeInterval(minutes * 60))
        await TrainingStore.shared.addPlanned(workout)
        return .result(dialog: "\(titles[sport] ?? "Einheit") für \(Fmt.dayTitle(day)) um \(Fmt.time(day)) eingetragen, \(minutes) Minuten.")
    }
}

// MARK: - „Wie viele Kilometer bin ich diese Woche gelaufen?“

struct WeeklyDistanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Wochenkilometer abfragen"
    static let description = IntentDescription("Sagt dir, wie viele Kilometer du diese Woche absolviert hast.")

    @Parameter(title: "Sportart", default: .run)
    var sport: SportAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let store = TrainingStore.shared
        let week = Calendar.training.weekInterval(containing: Date())
        let totals = store.totals(sport: sport.sport, in: week)
        let km = totals.distance / 1000
        let verb: String
        switch sport {
        case .run: verb = "gelaufen"
        case .bike: verb = "Rad gefahren"
        case .swim: verb = "geschwommen"
        }
        let value = sport == .swim ? Fmt.number(km, digits: 2) : Fmt.number(km, digits: 1)
        return .result(value: km,
                       dialog: "Du bist diese Woche \(value) Kilometer \(verb), in \(totals.count) Einheiten und \(Fmt.hoursMinutes(totals.duration)).")
    }
}

// MARK: - App Shortcuts (sofort für Siri verfügbar, ohne Einrichtung)

struct TriCoachShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowTodayWorkoutIntent(),
            phrases: [
                "Zeige mein heutiges Training in \(.applicationName)",
                "Was steht heute in \(.applicationName) an",
                "\(.applicationName) heutiges Training"
            ],
            shortTitle: "Heutiges Training",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: PlanWorkoutIntent(),
            phrases: [
                "Plane eine \(\.$sport) für morgen in \(.applicationName)",
                "Plane in \(.applicationName) eine \(\.$sport)",
                "\(.applicationName) plane \(\.$sport)"
            ],
            shortTitle: "Einheit planen",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: WeeklyDistanceIntent(),
            phrases: [
                "Wie viele Kilometer bin ich diese Woche in \(.applicationName) gelaufen",
                "\(.applicationName) Wochenkilometer",
                "Wie weit bin ich diese Woche gelaufen \(.applicationName)"
            ],
            shortTitle: "Wochenkilometer",
            systemImageName: "chart.bar.fill"
        )
    }
}
