import Foundation
import CoreLocation

// MARK: - Sportarten

enum Sport: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case swim, bike, run, strength, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .swim: return "Schwimmen"
        case .bike: return "Rad"
        case .run: return "Laufen"
        case .strength: return "Kraft"
        case .other: return "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .swim: return "figure.pool.swim"
        case .bike: return "figure.outdoor.cycle"
        case .run: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    static let triathlon: [Sport] = [.swim, .bike, .run]
}

// MARK: - Datenquellen

enum DataSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case garmin, fitFile, healthKit, mock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .garmin: return "Garmin Connect"
        case .fitFile: return "FIT-Import"
        case .healthKit: return "Apple Health"
        case .mock: return "Demo-Daten"
        }
    }

    /// Höhere Priorität gewinnt, wenn dieselbe Einheit aus mehreren Quellen kommt.
    var priority: Int {
        switch self {
        case .garmin: return 3
        case .fitFile: return 2
        case .healthKit: return 1
        case .mock: return 0
        }
    }
}

// MARK: - Zeitreihen

struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Ein Messpunkt einer Aktivität (typisch 1–5 s Auflösung).
struct Sample: Codable, Hashable, Sendable {
    /// Sekunden seit Start der Aktivität
    var offset: TimeInterval
    var heartRate: Int?
    /// m/s
    var speed: Double?
    /// Watt (Rad- oder Laufleistung)
    var power: Int?
    /// Rad: U/min, Laufen: Schritte/min, Schwimmen: Züge/min
    var cadence: Int?
    var altitude: Double?
    /// zurückgelegte Distanz in m seit Start
    var distance: Double?
    var location: GeoPoint?
    // Laufdynamik (Forerunner 265 liefert sie mit HRM-Pro oder am Handgelenk)
    var groundContactTime: Double?   // ms
    var verticalOscillation: Double? // cm
    var strideLength: Double?        // m
}

struct Lap: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var index: Int
    var startOffset: TimeInterval
    var duration: TimeInterval
    var distance: Double
    var avgHeartRate: Int?
    var avgSpeed: Double?
    var avgPower: Int?
    /// true = Belastungsintervall, false = Pause/Warmup/Cooldown
    var isInterval: Bool
}

// MARK: - Sportartspezifische Metriken

struct RunDynamics: Codable, Hashable, Sendable {
    var avgCadence: Double?              // Schritte/min
    var avgStrideLength: Double?         // m
    var avgGroundContactTime: Double?    // ms
    var avgVerticalOscillation: Double?  // cm
    var avgVerticalRatio: Double?        // %
    var avgPower: Double?                // W
}

struct BikeMetrics: Codable, Hashable, Sendable {
    var avgPower: Int?
    var normalizedPower: Int?
    var maxPower: Int?
    var avgCadence: Int?
    var elevationGain: Double?
    /// Mean-Max-Leistung: Dauer in s → Watt
    var powerCurve: [Int: Int] = [:]
}

enum StrokeType: String, Codable, CaseIterable, Sendable {
    case freestyle, backstroke, breaststroke, butterfly, drill, mixed

    var displayName: String {
        switch self {
        case .freestyle: return "Kraul"
        case .backstroke: return "Rücken"
        case .breaststroke: return "Brust"
        case .butterfly: return "Delfin"
        case .drill: return "Technik"
        case .mixed: return "Lagen"
        }
    }
}

struct SwimLength: Codable, Hashable, Identifiable, Sendable {
    var id: Int { index }
    var index: Int
    var duration: TimeInterval
    var strokes: Int
    var strokeType: StrokeType

    /// SWOLF = Sekunden + Züge pro Bahn
    var swolf: Int { Int(duration.rounded()) + strokes }
    /// Züge pro Minute
    var strokeRate: Double { duration > 0 ? Double(strokes) / duration * 60 : 0 }
}

struct SwimMetrics: Codable, Hashable, Sendable {
    var poolLength: Double?          // nil = Freiwasser
    var totalStrokes: Int?
    var avgSwolf: Double?
    var avgStrokeRate: Double?       // Züge/min
    var lengths: [SwimLength] = []

    var isOpenWater: Bool { poolLength == nil }

    /// Distance per Stroke (m/Zug)
    var distancePerStroke: Double? {
        guard let pool = poolLength else { return nil }
        let active = lengths.filter { $0.strokes > 0 }
        guard !active.isEmpty else { return nil }
        let strokes = active.reduce(0) { $0 + $1.strokes }
        return pool * Double(active.count) / Double(strokes)
    }
}

// MARK: - Aktivität

struct Activity: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var sport: Sport
    var name: String
    var startDate: Date
    var duration: TimeInterval
    var distance: Double                 // m
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var calories: Int?
    var elevationGain: Double?
    var aerobicTrainingEffect: Double?
    var anaerobicTrainingEffect: Double?
    var source: DataSourceKind
    var samples: [Sample] = []
    var laps: [Lap] = []
    var run: RunDynamics?
    var bike: BikeMetrics?
    var swim: SwimMetrics?
    /// Training Stress Score, wird nach dem Import berechnet
    var tss: Double?

    var avgSpeed: Double { duration > 0 ? distance / duration : 0 }
    var endDate: Date { startDate.addingTimeInterval(duration) }
    var hasGPS: Bool { samples.contains { $0.location != nil } }
    var track: [CLLocationCoordinate2D] { samples.compactMap { $0.location?.coordinate } }
}
