import Foundation

/// Laufprognosen nach Jack Daniels (VDOT) und Riegel.
enum RunPredictor {
    static let standardDistances: [(name: String, meters: Double)] = [
        ("5 km", 5_000), ("10 km", 10_000), ("Halbmarathon", 21_097.5), ("Marathon", 42_195)
    ]

    static func riegel(time t1: TimeInterval, distance d1: Double, to d2: Double, exponent: Double = 1.06) -> TimeInterval {
        t1 * pow(d2 / d1, exponent)
    }

    static func vdot(distance: Double, time: TimeInterval) -> Double {
        let t = time / 60
        let v = distance / t // m/min
        let vo2 = -4.60 + 0.182258 * v + 0.000104 * v * v
        let fraction = 0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
        return vo2 / fraction
    }

    /// Zeit, bei der `vdot(distance, time) == target` (VDOT fällt monoton mit der Zeit).
    static func predictTime(vdot target: Double, distance: Double) -> TimeInterval {
        var lo = distance / 8.0, hi = distance / 1.0
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if vdot(distance: distance, time: mid) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Bestes VDOT aus den härtesten zusammenhängenden Abschnitten (12–40 min) der letzten Wochen.
    static func estimateVDOT(from activities: [Activity], days: Int = 60) -> Double? {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var best: Double?
        for a in activities where a.sport == .run && a.startDate >= cutoff {
            for duration in [720.0, 1_200, 2_400] where a.duration >= duration {
                guard let speed = SeriesMath.bestSpeed(samples: a.samples, duration: duration), speed > 0 else { continue }
                // Nur echte Belastungen berücksichtigen (Daniels-Formel geht von maximalem Effort aus)
                let effortFactor = duration < 1_000 ? 0.97 : 1.0
                let v = vdot(distance: speed * duration, time: duration) * effortFactor
                best = max(best ?? 0, v)
            }
        }
        return best
    }
}

/// Split-Prognose für Triathlon-Wettkämpfe.
struct RaceSplitPrediction: Hashable {
    var swim: TimeInterval
    var t1: TimeInterval
    var bike: TimeInterval
    var t2: TimeInterval
    var run: TimeInterval
    var bikePower: Double
    var bikeSpeed: Double
    var runPace: TimeInterval
    var swimPace: TimeInterval

    var total: TimeInterval { swim + t1 + bike + t2 + run }
}

enum RaceSplitPredictor {
    static func predict(format: RaceFormat, profile: AthleteProfile, cda: Double = 0.30, hilliness: Double = 0,
                        wetsuit: Bool = true, temperatureC: Double = 20) -> RaceSplitPrediction {
        // Schwimmen: CSS + Distanzaufschlag, Neo ≈ −3 s/100 m
        let swimPace = profile.css + format.swimPaceOffset - (wetsuit ? 3 : 0)
        let swim = format.swimDistance / 100 * swimPace

        // Rad: Leistung = IF × FTP, Geschwindigkeit aus Aero-Modell, Hügel kosten ~ bis 8 %
        let power = Double(profile.ftp) * format.bikeIntensity
        let flatSpeed = AeroModel.speed(power: power, cda: cda, mass: profile.systemMass)
        let speed = flatSpeed * (1 - 0.08 * hilliness)
        let bike = format.bikeDistance / speed

        // Laufen: Schwellentempo × Ermüdungsfaktor, Hitze kostet ~1 % pro °C über 18 °C
        let heat = 1 + max(0, temperatureC - 18) * 0.01
        let runPace = profile.thresholdPace * format.runPaceFactor * heat
        let run = format.runDistance / 1000 * runPace

        return RaceSplitPrediction(swim: swim, t1: format.transitionTime * 0.55, bike: bike,
                                   t2: format.transitionTime * 0.45, run: run, bikePower: power,
                                   bikeSpeed: speed, runPace: runPace, swimPace: swimPace)
    }

    /// Live-Projektion: tatsächliche Splits ersetzen die Prognose, sobald sie vorliegen.
    /// Für das laufende Segment wird die bisher verstrichene Zeit genutzt (mindestens die Prognose).
    static func liveProjection(prediction: RaceSplitPrediction, completed: [TimeInterval], currentElapsed: TimeInterval) -> TimeInterval {
        let planned = [prediction.swim, prediction.t1, prediction.bike, prediction.t2, prediction.run]
        var total = completed.reduce(0, +)
        let currentIndex = completed.count
        guard currentIndex < planned.count else { return total }
        // Abweichung bisher (Verhältnis Ist/Plan) auf verbleibende Segmente übertragen – gedämpft
        let plannedSoFar = planned.prefix(currentIndex).reduce(0, +)
        let ratio = plannedSoFar > 0 ? total / plannedSoFar : 1
        let damped = 1 + (ratio - 1) * 0.5
        total += max(currentElapsed, planned[currentIndex] * damped)
        for i in (currentIndex + 1)..<planned.count { total += planned[i] * damped }
        return total
    }
}
