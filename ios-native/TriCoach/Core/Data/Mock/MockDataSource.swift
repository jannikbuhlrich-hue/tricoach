import Foundation

/// Liefert realistische, deterministische Demo-Daten (≈ 5 Monate Triathlon-Training),
/// solange keine Garmin-/Health-Verbindung besteht.
struct MockDataSource: TrainingDataSource {
    let kind: DataSourceKind = .mock
    var profile: AthleteProfile
    var daysBack: Int = 150

    func fetchActivities(from: Date, to: Date) async throws -> [Activity] {
        MockFactory(profile: profile)
            .activities(daysBack: daysBack)
            .filter { $0.startDate >= from && $0.startDate <= to }
    }

    func fetchWellness(from: Date, to: Date) async throws -> [DailyWellness] {
        let start = Calendar.training.startOfDay(for: from)
        return MockFactory(profile: profile)
            .wellness(daysBack: daysBack)
            .filter { $0.date >= start && $0.date <= to }
    }
}

struct MockFactory {
    let profile: AthleteProfile
    private let center = GeoPoint(latitude: 53.0793, longitude: 8.8017)
    private let cal = Calendar.training

    init(profile: AthleteProfile) { self.profile = profile }

    // MARK: Aktivitäten

    func activities(daysBack: Int) -> [Activity] {
        let now = Date()
        let today = cal.startOfDay(for: now)
        var result: [Activity] = []

        for back in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let dayNumber = Int(day.timeIntervalSince1970 / 86_400)
            var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: dayNumber) &* 7_919)
            let progress = 1 - Double(back) / Double(max(daysBack, 1))   // 0 = alt, 1 = heute
            let fitness = 0.94 + 0.06 * progress
            let recoveryWeek = (dayNumber / 7) % 4 == 3
            let testWeek = (dayNumber / 7) % 6 == 0   // alle 6 Wochen Leistungstests
            let volume = recoveryWeek ? 0.65 : 1.0

            if !testWeek && Double.random(in: 0...1, using: &rng) < 0.08 { continue } // ausgefallener Tag

            switch cal.component(.weekday, from: day) {
            case 2: // Mo
                result.append(swim(day: day, hour: 7, kind: .endurance, meters: 2_400 * volume, fitness: fitness, progress: progress, rng: &rng))
            case 3: // Di
                result.append(run(day: day, hour: 18, kind: testWeek ? .test : .intervals, minutes: 62, fitness: fitness, rng: &rng))
            case 4: // Mi
                result.append(bike(day: day, hour: 18, kind: testWeek ? .ftpTest : .sweetSpot, minutes: 80 * volume, fitness: fitness, progress: progress, rng: &rng))
            case 5: // Do
                result.append(swim(day: day, hour: 7, kind: .css, meters: 2_800 * volume, fitness: fitness, progress: progress, rng: &rng))
                result.append(run(day: day, hour: 18, kind: .easy, minutes: 45 * volume, fitness: fitness, rng: &rng))
            case 6: // Fr
                result.append(swim(day: day, hour: 7, kind: .technique, meters: 2_000, fitness: fitness, progress: progress, rng: &rng))
            case 7: // Sa
                let minutes = (150 + Double(rng.next() % 60)) * volume
                result.append(bike(day: day, hour: 9, kind: .endurance, minutes: minutes, fitness: fitness, progress: progress, rng: &rng))
            default: // So
                let minutes = (75 + Double(rng.next() % 30)) * volume
                result.append(run(day: day, hour: 9, kind: .long, minutes: minutes, fitness: fitness, rng: &rng))
            }
        }
        return result.filter { $0.endDate <= now }.sorted { $0.startDate > $1.startDate }
    }

    // MARK: Laufen

    enum RunKind { case easy, long, intervals, test }

    private func run(day: Date, hour: Int, kind: RunKind, minutes: Double, fitness: Double,
                     rng: inout SeededGenerator) -> Activity {
        let start = cal.date(byAdding: .minute, value: hour * 60 + Int(rng.next() % 30), to: day) ?? day
        let threshold = profile.thresholdRunSpeed * fitness
        var segments: [(duration: TimeInterval, intensity: Double, interval: Bool)] = []
        let name: String
        switch kind {
        case .easy:
            segments = [(minutes * 60, 0.78, false)]
            name = "Lockerer Lauf"
        case .long:
            segments = [(minutes * 60, 0.80, false)]
            name = "Langer Lauf"
        case .intervals:
            segments.append((15 * 60, 0.75, false))
            for _ in 0..<6 {
                segments.append((240, 1.03, true))
                segments.append((120, 0.60, false))
            }
            segments.append((max(5, minutes - 51) * 60, 0.72, false))
            name = "Intervalle 6×4 min"
        case .test:
            segments = [(15 * 60, 0.75, false), (5_000 / (threshold * 1.06), 1.06, true), (10 * 60, 0.65, false)]
            name = "5-km-Test"
        }

        let dt: TimeInterval = 5
        let radius = 1_600.0
        var samples: [Sample] = []
        var laps: [Lap] = []
        var t: TimeInterval = 0, dist = 0.0
        var hr = Double(profile.restingHeartRate + 35)

        for (index, segment) in segments.enumerated() {
            let segStart = t, segDist = dist
            var hrSum = 0.0, n = 0.0
            for _ in 0..<Int(segment.duration / dt) {
                let speed = threshold * segment.intensity * (1 + rng.noise(0.03))
                dist += speed * dt
                t += dt
                let intensity = speed / threshold
                let targetHR = Double(profile.restingHeartRate)
                    + Double(profile.lactateThresholdHR - profile.restingHeartRate) * pow(intensity, 1.8)
                    + t / 3600 * 4 // kardiale Drift
                hr += (targetHR - hr) * 0.08
                let cadence = 162 + 18 * intensity + rng.noise(2)
                let angle = dist / radius
                samples.append(Sample(
                    offset: t,
                    heartRate: Int(hr + rng.noise(1.5)),
                    speed: speed,
                    power: Int(1.04 * profile.weightKg * speed + rng.noise(8)),
                    cadence: Int(cadence),
                    altitude: 5 + 3 * sin(angle * 3),
                    distance: dist,
                    location: loopPoint(distance: dist, radius: radius),
                    groundContactTime: 330 - 30 * speed + rng.noise(4),
                    verticalOscillation: 8.6 + rng.noise(0.3),
                    strideLength: speed * 60 / cadence
                ))
                hrSum += hr; n += 1
            }
            if kind == .intervals || kind == .test {
                laps.append(Lap(index: index, startOffset: segStart, duration: t - segStart, distance: dist - segDist,
                                avgHeartRate: Int(hrSum / max(n, 1)), avgSpeed: (dist - segDist) / max(t - segStart, 1),
                                avgPower: nil, isInterval: segment.interval))
            }
        }
        if kind == .easy || kind == .long { laps = Self.distanceLaps(samples: samples, every: 1_000) }

        let cadences = samples.compactMap { $0.cadence.map(Double.init) }
        let strides = samples.compactMap(\.strideLength)
        let gct = samples.compactMap(\.groundContactTime)
        let vo = samples.compactMap(\.verticalOscillation)
        let avgStride = strides.mean ?? 1
        let dynamics = RunDynamics(
            avgCadence: cadences.mean,
            avgStrideLength: strides.mean,
            avgGroundContactTime: gct.mean,
            avgVerticalOscillation: vo.mean,
            avgVerticalRatio: (vo.mean ?? 0) / (avgStride * 100) * 100,
            avgPower: samples.compactMap { $0.power.map(Double.init) }.mean
        )
        let hrs = samples.compactMap { $0.heartRate.map(Double.init) }
        return Activity(
            id: "mock-run-\(Int(start.timeIntervalSince1970))",
            sport: .run, name: name, startDate: start, duration: t, distance: dist,
            avgHeartRate: hrs.mean.map { Int($0) }, maxHeartRate: hrs.max().map { Int($0) },
            calories: Int(t / 60 * 12), elevationGain: 18,
            aerobicTrainingEffect: kind == .intervals ? 3.4 : (kind == .long ? 3.1 : 2.4),
            anaerobicTrainingEffect: kind == .intervals ? 2.6 : 0.4,
            source: .mock, samples: samples, laps: laps, run: dynamics
        )
    }

    // MARK: Rad

    enum BikeKind { case endurance, sweetSpot, ftpTest }

    private func bike(day: Date, hour: Int, kind: BikeKind, minutes: Double, fitness: Double, progress: Double,
                      rng: inout SeededGenerator) -> Activity {
        let start = cal.date(byAdding: .minute, value: hour * 60 + Int(rng.next() % 30), to: day) ?? day
        let ftp = Double(profile.ftp) * fitness
        // Aero-Position verbessert sich über die Saison → sichtbarer CdA-Trend
        let cda = 0.335 - 0.03 * progress
        var segments: [(duration: TimeInterval, intensity: Double, interval: Bool)] = []
        let name: String
        switch kind {
        case .endurance:
            segments = [(minutes * 60, 0.66, false)]
            name = "Grundlage Rad"
        case .sweetSpot:
            segments = [(15 * 60, 0.60, false)]
            for i in 0..<3 {
                segments.append((15 * 60, 0.90, true))
                if i < 2 { segments.append((5 * 60, 0.55, false)) }
            }
            segments.append((max(5, minutes - 70) * 60, 0.60, false))
            name = "Sweet Spot 3×15 min"
        case .ftpTest:
            segments = [(20 * 60, 0.60, false), (20 * 60, 1.05, true), (15 * 60, 0.55, false)]
            name = "FTP-Test 20 min"
        }

        let dt: TimeInterval = 5
        let radius = 6_000.0
        var samples: [Sample] = []
        var laps: [Lap] = []
        var t: TimeInterval = 0, dist = 0.0
        var hr = Double(profile.restingHeartRate + 30)
        let bikeLTHR = Double(profile.lactateThresholdHR - 5)

        for (index, segment) in segments.enumerated() {
            let segStart = t, segDist = dist
            var hrSum = 0.0, pSum = 0.0, n = 0.0
            for _ in 0..<Int(segment.duration / dt) {
                let power = max(0, ftp * segment.intensity * (1 + rng.noise(0.07)))
                let grade = 0.005 * sin(dist / 3_000)
                let speed = AeroModel.speed(power: power, cda: cda * (1 + rng.noise(0.02)), mass: profile.systemMass, grade: grade)
                dist += speed * dt
                t += dt
                let targetHR = Double(profile.restingHeartRate)
                    + (bikeLTHR - Double(profile.restingHeartRate)) * pow(power / ftp, 1.5)
                    + t / 3600 * 3
                hr += (targetHR - hr) * 0.06
                samples.append(Sample(
                    offset: t,
                    heartRate: Int(hr + rng.noise(1.5)),
                    speed: speed,
                    power: Int(power),
                    cadence: Int((segment.interval ? 92 : 87) + rng.noise(3)),
                    altitude: 8 + 10 * sin(dist / 3_000),
                    distance: dist,
                    location: loopPoint(distance: dist, radius: radius)
                ))
                hrSum += hr; pSum += power; n += 1
            }
            laps.append(Lap(index: index, startOffset: segStart, duration: t - segStart, distance: dist - segDist,
                            avgHeartRate: Int(hrSum / max(n, 1)), avgSpeed: (dist - segDist) / max(t - segStart, 1),
                            avgPower: Int(pSum / max(n, 1)), isInterval: segment.interval))
        }

        let powers = samples.map { Double($0.power ?? 0) }
        var gain = 0.0
        for i in 1..<samples.count {
            let d = (samples[i].altitude ?? 0) - (samples[i - 1].altitude ?? 0)
            if d > 0 { gain += d }
        }
        let metrics = BikeMetrics(
            avgPower: powers.mean.map { Int($0) },
            normalizedPower: SeriesMath.normalizedPower(values: powers, interval: dt).map { Int($0) },
            maxPower: powers.max().map { Int($0) },
            avgCadence: samples.compactMap { $0.cadence.map(Double.init) }.mean.map { Int($0) },
            elevationGain: gain,
            powerCurve: SeriesMath.powerCurve(samples: samples)
        )
        let hrs = samples.compactMap { $0.heartRate.map(Double.init) }
        return Activity(
            id: "mock-bike-\(Int(start.timeIntervalSince1970))",
            sport: .bike, name: name, startDate: start, duration: t, distance: dist,
            avgHeartRate: hrs.mean.map { Int($0) }, maxHeartRate: hrs.max().map { Int($0) },
            calories: Int((powers.mean ?? 0) * t / 1000 * 1.1), elevationGain: gain,
            aerobicTrainingEffect: kind == .sweetSpot ? 3.6 : 3.0, anaerobicTrainingEffect: kind == .sweetSpot ? 1.2 : 0.3,
            source: .mock, samples: samples, laps: laps, bike: metrics
        )
    }

    // MARK: Schwimmen

    enum SwimKind { case endurance, css, technique }

    private func swim(day: Date, hour: Int, kind: SwimKind, meters: Double, fitness: Double, progress: Double,
                      rng: inout SeededGenerator) -> Activity {
        let start = cal.date(byAdding: .minute, value: hour * 60 + Int(rng.next() % 20), to: day) ?? day
        let pool = 25.0
        let count = max(8, Int(meters / pool))
        let css = profile.cssSpeed * fitness
        // Technik verbessert sich: weniger Züge pro Bahn
        let baseStrokes = 17.5 - 2.0 * progress
        let name: String
        switch kind {
        case .endurance: name = "Ausdauer 4×600"
        case .css: name = "CSS-Serie 10×100"
        case .technique: name = "Technik + Drills"
        }

        var lengths: [SwimLength] = []
        var samples: [Sample] = []
        var laps: [Lap] = []
        var t: TimeInterval = 0
        var hr = Double(profile.restingHeartRate + 30)
        var lapStart: TimeInterval = 0

        for i in 0..<count {
            var factor: Double
            var stroke: StrokeType = .freestyle
            switch kind {
            case .endurance: factor = 0.90
            case .css: factor = i < 16 ? 0.86 : 0.985
            case .technique:
                factor = 0.82
                if i % 4 == 3 { stroke = .drill; factor = 0.70 }
            }
            if i > count * 3 / 4 { factor *= 0.98 } // Ermüdung
            let speed = css * factor * (1 + rng.noise(0.03))
            let duration = pool / speed
            let strokes = stroke == .drill ? 0 : Int((baseStrokes + rng.noise(1) + (factor - 0.9) * 12).rounded())
            lengths.append(SwimLength(index: i, duration: duration, strokes: strokes, strokeType: stroke))

            // HR-Samples alle 10 s (optische HF am Handgelenk unter Wasser)
            var local: TimeInterval = 0
            while local < duration {
                let step = min(10, duration - local)
                local += step
                hr += (Double(profile.restingHeartRate) + 95 * factor - hr) * 0.1
                samples.append(Sample(offset: t + local, heartRate: Int(hr + rng.noise(3)), speed: speed,
                                      cadence: Int(Double(strokes) / duration * 60), distance: Double(i) * pool + speed * local))
            }
            t += duration

            if (i + 1) % 4 == 0 {
                let lapLengths = lengths.suffix(4)
                let lapDuration = lapLengths.reduce(0) { $0 + $1.duration }
                laps.append(Lap(index: laps.count, startOffset: lapStart, duration: lapDuration, distance: 100,
                                avgHeartRate: Int(hr), avgSpeed: 100 / lapDuration, avgPower: nil,
                                isInterval: kind == .css && i >= 16))
                t += kind == .css ? 15 : 10 // Pause am Beckenrand
                lapStart = t
            }
        }

        let active = lengths.filter { $0.strokeType != .drill }
        let metrics = SwimMetrics(
            poolLength: pool,
            totalStrokes: lengths.reduce(0) { $0 + $1.strokes },
            avgSwolf: active.map { Double($0.swolf) }.mean,
            avgStrokeRate: active.map(\.strokeRate).mean,
            lengths: lengths
        )
        let hrs = samples.compactMap { $0.heartRate.map(Double.init) }
        return Activity(
            id: "mock-swim-\(Int(start.timeIntervalSince1970))",
            sport: .swim, name: name, startDate: start, duration: t, distance: Double(count) * pool,
            avgHeartRate: hrs.mean.map { Int($0) }, maxHeartRate: hrs.max().map { Int($0) },
            calories: Int(t / 60 * 10), elevationGain: nil,
            aerobicTrainingEffect: kind == .css ? 3.3 : 2.6, anaerobicTrainingEffect: kind == .css ? 1.5 : 0.5,
            source: .mock, samples: samples, laps: laps, swim: metrics
        )
    }

    // MARK: Wellness

    func wellness(daysBack: Int) -> [DailyWellness] {
        let today = cal.startOfDay(for: Date())
        var result: [DailyWellness] = []
        for back in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let dayNumber = Int(day.timeIntervalSince1970 / 86_400)
            var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: dayNumber) &* 104_729)
            let progress = 1 - Double(back) / Double(max(daysBack, 1))
            let hrv = 62 + 8 * progress + rng.noise(8)
            let total = (7.2 + rng.noise(0.7)) * 3600
            let sleep = SleepSummary(total: total, deep: total * 0.18, light: total * 0.55, rem: total * 0.22,
                                     awake: total * 0.05, score: Int(75 + rng.noise(13)))
            let readiness = Int(min(100, max(5, 45 + (hrv - 60) * 2 + rng.noise(12))))
            result.append(DailyWellness(
                date: day,
                restingHeartRate: profile.restingHeartRate + 2 - Int(progress * 2) + Int(rng.noise(2)),
                hrvNightlyAvg: hrv,
                sleep: sleep,
                avgStress: Int(30 + rng.noise(9)),
                bodyBatteryHigh: Int(85 + rng.noise(14)),
                bodyBatteryLow: Int(25 + rng.noise(10)),
                trainingReadiness: readiness,
                recoveryTimeHours: max(0, 24 + rng.noise(20)),
                vo2maxRun: ((55 + 3 * progress) * 10).rounded() / 10,
                vo2maxBike: ((54 + 2.5 * progress) * 10).rounded() / 10,
                steps: Int(11_000 + rng.noise(3_000)),
                source: .mock
            ))
        }
        return result.sorted { $0.date < $1.date }
    }

    // MARK: Hilfen

    private func loopPoint(distance: Double, radius: Double) -> GeoPoint {
        let angle = distance / radius
        let lat = center.latitude + radius * (cos(angle) - 1) / 111_320
        let lon = center.longitude + radius * sin(angle) / (111_320 * cos(center.latitude * .pi / 180))
        return GeoPoint(latitude: lat, longitude: lon)
    }

    /// Teilt eine kontinuierliche Einheit in Runden à `every` Meter.
    static func distanceLaps(samples: [Sample], every: Double) -> [Lap] {
        var laps: [Lap] = []
        var startIndex = 0
        var nextMark = every
        for (i, s) in samples.enumerated() {
            guard let d = s.distance, d >= nextMark || i == samples.count - 1 else { continue }
            let slice = samples[startIndex...i]
            let startOffset = startIndex > 0 ? samples[startIndex - 1].offset : 0
            let startDist = startIndex > 0 ? (samples[startIndex - 1].distance ?? 0) : 0
            let duration = s.offset - startOffset
            let distance = d - startDist
            let hrs = slice.compactMap { $0.heartRate.map(Double.init) }
            let powers = slice.compactMap { $0.power.map(Double.init) }
            laps.append(Lap(index: laps.count, startOffset: startOffset, duration: duration, distance: distance,
                            avgHeartRate: hrs.mean.map { Int($0) }, avgSpeed: duration > 0 ? distance / duration : nil,
                            avgPower: powers.mean.map { Int($0) }, isInterval: false))
            startIndex = i + 1
            nextMark += every
            if startIndex >= samples.count { break }
        }
        return laps
    }
}
