import Foundation

struct PlannedWorkout: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var sport: Sport
    var title: String
    var plannedDuration: TimeInterval
    var plannedDistance: Double?
    var plannedTSS: Double?
    var notes: String = ""
    var calendarEventIdentifier: String?
    var completedActivityID: String?

    var isCompleted: Bool { completedActivityID != nil }
}

enum RaceFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case sprint, olympic, middle, full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sprint: return "Sprint"
        case .olympic: return "Olympisch"
        case .middle: return "Mitteldistanz (70.3)"
        case .full: return "Langdistanz"
        }
    }

    var swimDistance: Double {
        switch self { case .sprint: return 750; case .olympic: return 1500; case .middle: return 1900; case .full: return 3800 }
    }
    var bikeDistance: Double {
        switch self { case .sprint: return 20_000; case .olympic: return 40_000; case .middle: return 90_000; case .full: return 180_000 }
    }
    var runDistance: Double {
        switch self { case .sprint: return 5_000; case .olympic: return 10_000; case .middle: return 21_097.5; case .full: return 42_195 }
    }
    /// Typischer Intensity Factor auf dem Rad (NP/FTP)
    var bikeIntensity: Double {
        switch self { case .sprint: return 0.92; case .olympic: return 0.88; case .middle: return 0.78; case .full: return 0.70 }
    }
    /// Lauftempo relativ zum Schwellentempo nach dem Radfahren
    var runPaceFactor: Double {
        switch self { case .sprint: return 1.04; case .olympic: return 1.07; case .middle: return 1.13; case .full: return 1.25 }
    }
    /// Aufschlag auf CSS in s/100 m
    var swimPaceOffset: Double {
        switch self { case .sprint: return 0; case .olympic: return 2; case .middle: return 4; case .full: return 7 }
    }
    /// Ziel-CTL (Fitness) am Renntag als grobe Orientierung
    var targetCTL: Double {
        switch self { case .sprint: return 50; case .olympic: return 65; case .middle: return 80; case .full: return 100 }
    }
    var transitionTime: TimeInterval {
        switch self { case .sprint: return 150; case .olympic: return 180; case .middle: return 300; case .full: return 480 }
    }
}

struct RaceGoal: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var date: Date
    var format: RaceFormat
    var targetTime: TimeInterval?
    var expectedTemperatureC: Double = 20
    /// Erwartete Radstrecke flach = 0, hügelig bis 1
    var bikeHilliness: Double = 0
}

// MARK: - Ernährung

struct FuelItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var carbsG: Double
    var fluidMl: Double = 0
    var sodiumMg: Double = 0
    var caffeineMg: Double = 0

    static let defaults: [FuelItem] = [
        FuelItem(name: "Gel", carbsG: 25, sodiumMg: 50),
        FuelItem(name: "Koffein-Gel", carbsG: 25, sodiumMg: 50, caffeineMg: 75),
        FuelItem(name: "Iso-Flasche 750 ml", carbsG: 60, fluidMl: 750, sodiumMg: 500),
        FuelItem(name: "Riegel", carbsG: 40, sodiumMg: 100),
        FuelItem(name: "Wasser 500 ml", carbsG: 0, fluidMl: 500),
        FuelItem(name: "Salztablette", carbsG: 0, sodiumMg: 250)
    ]
}

struct FuelLogEntry: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var time: Date
    var item: FuelItem
}
