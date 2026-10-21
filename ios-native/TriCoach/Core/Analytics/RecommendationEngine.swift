import Foundation

struct Recommendation: Identifiable, Hashable {
    var id = UUID()
    let sport: Sport?
    let title: String
    let detail: String
    /// 1 = höchste Priorität
    let priority: Int
    var suggestedWorkout: PlannedWorkout?
}

struct CoachingContext {
    let activities: [Activity]
    let wellness: [DailyWellness]
    let profile: AthleteProfile
    let load: LoadPoint?
    let readiness: ReadinessResult
    let insights: [Insight]
    let nextRace: RaceGoal?
    let planned: [PlannedWorkout]
}

/// Austauschbare Coaching-Engine: regelbasiert (offline) oder LLM-gestützt.
protocol CoachingEngine {
    func recommendations(for context: CoachingContext) async -> [Recommendation]
}

/// Regelbasierte Empfehlungen – funktioniert ohne Netz, transparent nachvollziehbar.
struct RuleBasedCoach: CoachingEngine {
    func recommendations(for c: CoachingContext) async -> [Recommendation] {
        var recs: [Recommendation] = []
        let cal = Calendar.training
        let tomorrow = cal.date(bySettingHour: 18, minute: 0, second: 0,
                                of: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()

        // 1. Erholung zuerst
        if c.readiness.level == .low || (c.load?.tsb ?? 0) < -30 {
            recs.append(Recommendation(
                sport: nil, title: "Heute Regeneration",
                detail: "Bereitschaft \(c.readiness.score)/100, Form \(Int(c.load?.tsb ?? 0)). 30–40 min locker (Z1) oder Ruhetag.",
                priority: 1,
                suggestedWorkout: PlannedWorkout(date: tomorrow, sport: .swim, title: "Lockeres Ausschwimmen",
                                                 plannedDuration: 30 * 60, plannedTSS: 20,
                                                 notes: "Technikfokus, keine Intensität")))
        }

        // 2. Renn-Nähe → Taper
        if let race = c.nextRace {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: race.date)).day ?? 99
            if days <= 21 {
                let taper = TaperAnalyzer.optimize(activities: c.activities, current: c.load, raceDate: race.date)
                recs.append(Recommendation(
                    sport: nil, title: "Taper für \(race.name) (\(days) Tage)",
                    detail: taper.map { "Empfehlung: \($0.plan.days) Tage, −\(Int($0.plan.reduction * 100)) % Umfang. Intensität kurz halten, Volumen senken." }
                        ?? "Umfang schrittweise reduzieren, Intensität beibehalten.",
                    priority: 1))
            }
        }

        // 3. Schwächste Disziplin → Schlüsseleinheit
        if c.readiness.level != .low, let weakness = c.insights.first(where: { $0.kind == .weakness })?.sport {
            recs.append(keySession(for: weakness, profile: c.profile, date: tomorrow))
        }

        // 4. Lange Einheit fehlt
        let tenDays = Date().addingTimeInterval(-10 * 86_400)
        if !c.activities.contains(where: { $0.sport == .bike && $0.startDate >= tenDays && $0.duration >= 2.5 * 3600 }) {
            recs.append(Recommendation(
                sport: .bike, title: "Lange Radausfahrt fehlt",
                detail: "Seit 10 Tagen keine Ausfahrt > 2,5 h. Am Wochenende 3 h in Z2 (\(Int(Double(c.profile.ftp) * 0.6))–\(Int(Double(c.profile.ftp) * 0.75)) W).",
                priority: 3,
                suggestedWorkout: PlannedWorkout(date: nextWeekend(), sport: .bike, title: "Lange Grundlage",
                                                 plannedDuration: 3 * 3600, plannedTSS: 160)))
        }
        if !c.activities.contains(where: { $0.sport == .run && $0.startDate >= tenDays && $0.duration >= 75 * 60 }) {
            recs.append(Recommendation(
                sport: .run, title: "Langer Lauf fehlt",
                detail: "75–90 min locker bei \(Fmt.paceValue(c.profile.thresholdPace / 0.8))/km – stärkt die Ermüdungsresistenz für die Laufstrecke.",
                priority: 3,
                suggestedWorkout: PlannedWorkout(date: nextWeekend(offset: 1), sport: .run, title: "Langer Lauf",
                                                 plannedDuration: 80 * 60, plannedTSS: 85)))
        }

        // 5. Frische Form nutzen
        if let tsb = c.load?.tsb, tsb > 10, c.readiness.level == .high, recs.allSatisfy({ $0.priority > 1 }) {
            recs.append(Recommendation(sport: nil, title: "Du bist frisch",
                                       detail: "TSB +\(Int(tsb)) und hohe Bereitschaft – guter Tag für einen Test (FTP, CSS oder 5 km).",
                                       priority: 2))
        }

        return recs.sorted { $0.priority < $1.priority }
    }

    private func keySession(for sport: Sport, profile: AthleteProfile, date: Date) -> Recommendation {
        switch sport {
        case .swim:
            return Recommendation(
                sport: .swim, title: "Schlüsseleinheit Schwimmen",
                detail: "10×100 m @ CSS (\(Fmt.paceValue(profile.css))/100m), 15 s Pause. Vorher 4×50 m Technik (Catch-up, Abschlag).",
                priority: 2,
                suggestedWorkout: PlannedWorkout(date: date, sport: .swim, title: "CSS 10×100", plannedDuration: 55 * 60,
                                                 plannedDistance: 2_800, plannedTSS: 60))
        case .bike:
            let lo = Int(Double(profile.ftp) * 0.88), hi = Int(Double(profile.ftp) * 0.93)
            return Recommendation(
                sport: .bike, title: "Schlüsseleinheit Rad",
                detail: "3×15 min Sweet Spot @ \(lo)–\(hi) W, 5 min Pause. Aeroposition halten.",
                priority: 2,
                suggestedWorkout: PlannedWorkout(date: date, sport: .bike, title: "Sweet Spot 3×15", plannedDuration: 80 * 60,
                                                 plannedTSS: 95))
        default:
            return Recommendation(
                sport: .run, title: "Schlüsseleinheit Laufen",
                detail: "5×1 km @ Schwelle (\(Fmt.paceValue(profile.thresholdPace))/km), 90 s Trabpause.",
                priority: 2,
                suggestedWorkout: PlannedWorkout(date: date, sport: .run, title: "Schwelle 5×1 km", plannedDuration: 60 * 60,
                                                 plannedTSS: 75))
        }
    }

    private func nextWeekend(offset: Int = 0) -> Date {
        let cal = Calendar.training
        var comps = DateComponents()
        comps.weekday = 7 // Samstag
        let saturday = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? Date()
        let day = cal.date(byAdding: .day, value: offset, to: saturday) ?? saturday
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}

/// KI-Coach: schickt eine kompakte, anonymisierte Trainingszusammenfassung an dein Backend,
/// das ein LLM (z. B. Claude API) aufruft. API-Keys bleiben auf dem Server.
/// Fällt bei Fehlern automatisch auf die Regel-Engine zurück.
struct LLMCoach: CoachingEngine {
    let endpoint: URL
    let fallback = RuleBasedCoach()

    struct Summary: Encodable {
        let ctl: Double, atl: Double, tsb: Double
        let readiness: Int
        let weeklyHours: [String: Double]
        let insights: [String]
        let daysToRace: Int?
        let raceFormat: String?
        let ftp: Int, thresholdPace: Double, css: Double
    }

    struct Response: Decodable {
        struct Item: Decodable {
            let sport: String?
            let title: String
            let detail: String
            let priority: Int
            let durationMinutes: Double?
        }
        let recommendations: [Item]
    }

    func recommendations(for c: CoachingContext) async -> [Recommendation] {
        let week = Calendar.training.weekInterval(containing: Date())
        var hours: [String: Double] = [:]
        for s in Sport.triathlon {
            hours[s.rawValue] = c.activities.filter { $0.sport == s && week.contains($0.startDate) }
                .reduce(0) { $0 + $1.duration } / 3600
        }
        let days = c.nextRace.flatMap { Calendar.training.dateComponents([.day], from: Date(), to: $0.date).day }
        let summary = Summary(ctl: c.load?.ctl ?? 0, atl: c.load?.atl ?? 0, tsb: c.load?.tsb ?? 0,
                              readiness: c.readiness.score, weeklyHours: hours,
                              insights: c.insights.map { "\($0.title): \($0.detail)" },
                              daysToRace: days, raceFormat: c.nextRace?.format.rawValue,
                              ftp: c.profile.ftp, thresholdPace: c.profile.thresholdPace, css: c.profile.css)
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = KeychainStore.get(GarminConfig.sessionTokenKey) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(summary)
            request.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(Response.self, from: data)
            let tomorrow = Calendar.training.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return response.recommendations.map { item in
                let sport = item.sport.flatMap(Sport.init(rawValue:))
                let workout = (sport != nil && item.durationMinutes != nil)
                    ? PlannedWorkout(date: tomorrow, sport: sport!, title: item.title, plannedDuration: item.durationMinutes! * 60)
                    : nil
                return Recommendation(sport: sport, title: item.title, detail: item.detail, priority: item.priority,
                                      suggestedWorkout: workout)
            }
        } catch {
            return await fallback.recommendations(for: c)
        }
    }
}
