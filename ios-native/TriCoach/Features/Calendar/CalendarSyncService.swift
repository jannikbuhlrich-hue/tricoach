import Foundation
import EventKit

/// Spiegelt geplante Einheiten in einen eigenen Apple-Kalender „TriCoach“.
@MainActor
final class CalendarSyncService {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()
    private let calendarTitle = "TriCoach"

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await eventStore.requestFullAccessToEvents()) ?? false
    }

    private func trainingCalendar() throws -> EKCalendar {
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == calendarTitle }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = calendarTitle
        calendar.cgColor = CGColor(red: 0.95, green: 0.27, blue: 0.40, alpha: 1)
        // iCloud bevorzugen, damit der Kalender auf allen Geräten erscheint
        calendar.source = eventStore.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
            ?? eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first { $0.sourceType == .local }
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// Legt den Termin an oder aktualisiert ihn. Gibt die Event-ID zurück.
    func upsert(_ workout: PlannedWorkout) async throws -> String {
        guard await requestAccess() else { throw DataSourceError.notAuthorized }
        let event = workout.calendarEventIdentifier.flatMap { eventStore.event(withIdentifier: $0) }
            ?? EKEvent(eventStore: eventStore)
        event.calendar = try trainingCalendar()
        event.title = "\(emoji(workout.sport)) \(workout.title)"
        event.startDate = workout.date
        event.endDate = workout.date.addingTimeInterval(workout.plannedDuration)
        var notes = workout.notes
        if let tss = workout.plannedTSS { notes += "\nGeplanter TSS: \(Int(tss))" }
        if let d = workout.plannedDistance { notes += "\nDistanz: \(Fmt.km(d))" }
        event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.url = URL(string: "tricoach://workout/\(workout.id.uuidString)")
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? ""
    }

    func removeEvent(identifier: String) {
        guard isAuthorized, let event = eventStore.event(withIdentifier: identifier) else { return }
        try? eventStore.remove(event, span: .thisEvent, commit: true)
    }

    /// Alle geplanten Einheiten in den Kalender schreiben (z. B. nach Aktivieren der Synchronisation).
    func syncAll(store: TrainingStore) async {
        guard await requestAccess() else { return }
        // updatePlanned schreibt bei aktivierter Synchronisation automatisch in den Kalender
        for workout in store.planned where workout.date >= Calendar.training.startOfDay(for: Date()) {
            await store.updatePlanned(workout)
        }
    }

    private func emoji(_ sport: Sport) -> String {
        switch sport {
        case .swim: return "🏊"
        case .bike: return "🚴"
        case .run: return "🏃"
        case .strength: return "🏋️"
        case .other: return "⏱️"
        }
    }
}
