import Foundation

extension Calendar {
    /// ISO-Woche, Montag als Wochenstart, deutsche Locale.
    static let training: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        cal.locale = Locale(identifier: "de_DE")
        cal.timeZone = .current
        return cal
    }()

    func weekInterval(containing date: Date) -> DateInterval {
        dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: startOfDay(for: date), duration: 7 * 86_400)
    }

    func monthInterval(containing date: Date) -> DateInterval {
        dateInterval(of: .month, for: date) ?? DateInterval(start: startOfDay(for: date), duration: 30 * 86_400)
    }

    func days(from start: Date, to end: Date) -> [Date] {
        var result: [Date] = []
        var day = startOfDay(for: start)
        let last = startOfDay(for: end)
        while day <= last {
            result.append(day)
            guard let next = date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

enum Fmt {
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func hoursMinutes(_ t: TimeInterval) -> String {
        let m = max(0, Int((t / 60).rounded()))
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m) min"
    }

    static func km(_ meters: Double, digits: Int = 1) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(digits))) + " km"
    }

    static func meters(_ meters: Double) -> String {
        meters.formatted(.number.precision(.fractionLength(0))) + " m"
    }

    static func number(_ v: Double, digits: Int = 0) -> String {
        v.formatted(.number.precision(.fractionLength(digits)))
    }

    /// Lauf-Pace aus m/s
    static func pace(speed: Double) -> String {
        guard speed > 0.3 else { return "–" }
        return paceValue(1000 / speed) + " /km"
    }

    /// Schwimm-Pace aus m/s
    static func swimPace(speed: Double) -> String {
        guard speed > 0.1 else { return "–" }
        return paceValue(100 / speed) + " /100m"
    }

    /// Sekunden → „m:ss“
    static func paceValue(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func speedKmh(_ speed: Double) -> String {
        (speed * 3.6).formatted(.number.precision(.fractionLength(1))) + " km/h"
    }

    static func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
    }
}

/// Deterministischer Zufallsgenerator (SplitMix64) – Mock-Daten bleiben bei jedem Start gleich.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func noise(_ amplitude: Double) -> Double {
        Double.random(in: -amplitude...amplitude, using: &self)
    }
}

extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }

    var median: Double? {
        guard !isEmpty else { return nil }
        let s = sorted()
        return s.count % 2 == 0 ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    var standardDeviation: Double? {
        guard count > 1, let m = mean else { return nil }
        return (map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(count - 1)).squareRoot()
    }

    /// Steigung der linearen Regression (pro Index)
    var trendSlope: Double? {
        guard count > 2 else { return nil }
        let n = Double(count)
        let xs = (0..<count).map(Double.init)
        let mx = xs.reduce(0, +) / n
        let my = reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, self) { num += (x - mx) * (y - my); den += (x - mx) * (x - mx) }
        return den == 0 ? nil : num / den
    }
}
