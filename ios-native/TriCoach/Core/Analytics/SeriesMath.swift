import Foundation

/// Mathematische Hilfen für Zeitreihen (Leistung, Geschwindigkeit).
enum SeriesMath {
    static let curveDurations: [Int] = [5, 15, 30, 60, 120, 300, 480, 600, 1200, 1800, 3600, 7200]

    /// Durchschnittlicher Abstand zwischen Samples
    static func sampleInterval(_ samples: [Sample]) -> TimeInterval {
        guard samples.count > 1, let first = samples.first, let last = samples.last else { return 1 }
        return max(1, (last.offset - first.offset) / Double(samples.count - 1))
    }

    /// Bester gleitender Mittelwert über `duration` Sekunden.
    static func meanMax(values: [Double], interval: TimeInterval, duration: TimeInterval) -> Double? {
        let n = Int((duration / interval).rounded())
        guard n > 0, values.count >= n else { return nil }
        var sum = values[0..<n].reduce(0, +)
        var best = sum
        if values.count > n {
            for i in n..<values.count {
                sum += values[i] - values[i - n]
                best = max(best, sum)
            }
        }
        return best / Double(n)
    }

    /// Normalized Power nach Coggan (30-s-Glättung, 4. Potenz).
    static func normalizedPower(values: [Double], interval: TimeInterval) -> Double? {
        let n = max(1, Int((30 / interval).rounded()))
        guard values.count >= n else { return nil }
        var sum = values[0..<n].reduce(0, +)
        var acc = pow(sum / Double(n), 4)
        var count = 1.0
        if values.count > n {
            for i in n..<values.count {
                sum += values[i] - values[i - n]
                acc += pow(sum / Double(n), 4)
                count += 1
            }
        }
        return pow(acc / count, 0.25)
    }

    static func powerCurve(samples: [Sample]) -> [Int: Int] {
        let values = samples.map { Double($0.power ?? 0) }
        guard values.contains(where: { $0 > 0 }) else { return [:] }
        let dt = sampleInterval(samples)
        var curve: [Int: Int] = [:]
        for d in curveDurations {
            if let p = meanMax(values: values, interval: dt, duration: TimeInterval(d)) {
                curve[d] = Int(p.rounded())
            }
        }
        return curve
    }

    /// Beste Durchschnittsgeschwindigkeit über eine Dauer (z. B. 20 min) – für Lauf-/Schwimmprognosen.
    static func bestSpeed(samples: [Sample], duration: TimeInterval) -> Double? {
        let values = samples.map { $0.speed ?? 0 }
        return meanMax(values: values, interval: sampleInterval(samples), duration: duration)
    }
}

/// Physikalisches Radmodell: Luftwiderstand + Rollwiderstand + Steigung.
enum AeroModel {
    static let airDensity = 1.225     // kg/m³ (15 °C, Meereshöhe)
    static let rollingResistance = 0.004
    static let gravity = 9.81
    static let drivetrainEfficiency = 0.977

    static func power(speed v: Double, cda: Double, mass: Double, grade: Double = 0) -> Double {
        let aero = 0.5 * airDensity * cda * v * v * v
        let rolling = rollingResistance * mass * gravity * v
        let climbing = mass * gravity * grade * v
        return (aero + rolling + climbing) / drivetrainEfficiency
    }

    /// Geschwindigkeit bei gegebener Leistung (Bisektion).
    static func speed(power: Double, cda: Double, mass: Double, grade: Double = 0) -> Double {
        var lo = 0.5, hi = 25.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if self.power(speed: mid, cda: cda, mass: mass, grade: grade) > power { hi = mid } else { lo = mid }
        }
        return (lo + hi) / 2
    }

    /// CdA-Schätzung aus einem stationären, flachen Abschnitt (ohne Windkorrektur → Trend, kein Absolutwert).
    static func estimateCdA(power: Double, speed: Double, mass: Double) -> Double? {
        guard speed > 6, power > 80 else { return nil }
        let cda = (power * drivetrainEfficiency - rollingResistance * mass * gravity * speed) / (0.5 * airDensity * pow(speed, 3))
        return (0.15...0.6).contains(cda) ? cda : nil
    }
}
