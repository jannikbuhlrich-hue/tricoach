import Foundation
import HealthKit
import CoreLocation

/// Apple Health als Datenquelle.
/// Garmin Connect (iOS) kann Workouts, HF, Schlaf usw. nach Apple Health schreiben
/// (Garmin Connect → Einstellungen → Verbundene Apps → Apple Health).
/// Nicht übertragen werden u. a. SWOLF, Body Battery und Trainingsbereitschaft – dafür FIT-Import oder Garmin-API nutzen.
final class HealthKitDataSource: TrainingDataSource, @unchecked Sendable {
    let kind: DataSourceKind = .healthKit
    let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var quantityTypes: [HKQuantityType] {
        [
            HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.vo2Max), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming), HKQuantityType(.swimmingStrokeCount), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.runningPower), HKQuantityType(.runningSpeed), HKQuantityType(.runningStrideLength),
            HKQuantityType(.runningGroundContactTime), HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.cyclingPower), HKQuantityType(.cyclingCadence), HKQuantityType(.cyclingSpeed),
            HKQuantityType(.stepCount)
        ]
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw DataSourceError.notConfigured("Apple Health") }
        var read = Set(quantityTypes.map { $0 as HKObjectType })
        read.insert(HKObjectType.workoutType())
        read.insert(HKSeriesType.workoutRoute())
        read.insert(HKCategoryType(.sleepAnalysis))
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
    }

    // MARK: Aktivitäten

    func fetchActivities(from: Date, to: Date) async throws -> [Activity] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let workouts = try await descriptor.result(for: store)
        var result: [Activity] = []
        for workout in workouts {
            guard let sport = Self.sport(for: workout.workoutActivityType) else { continue }
            result.append(try await makeActivity(from: workout, sport: sport))
        }
        return result
    }

    private func makeActivity(from workout: HKWorkout, sport: Sport) async throws -> Activity {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrStats = workout.statistics(for: HKQuantityType(.heartRate))
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0

        var samples = try await heartRateSamples(for: workout)
        let route = (try? await routeLocations(for: workout)) ?? []
        if !route.isEmpty { samples = merge(samples: samples, route: route, start: workout.startDate) }

        var activity = Activity(
            id: "hk-\(workout.uuid.uuidString)",
            sport: sport,
            name: workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String ?? sport.displayName,
            startDate: workout.startDate,
            duration: workout.duration,
            distance: distance,
            avgHeartRate: hrStats?.averageQuantity().map { Int($0.doubleValue(for: bpm)) },
            maxHeartRate: hrStats?.maximumQuantity().map { Int($0.doubleValue(for: bpm)) },
            calories: energy.map { Int($0) },
            elevationGain: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
            source: .healthKit,
            samples: samples
        )

        switch sport {
        case .run:
            activity.run = RunDynamics(
                avgCadence: nil,
                avgStrideLength: workout.statistics(for: HKQuantityType(.runningStrideLength))?.averageQuantity()?.doubleValue(for: .meter()),
                avgGroundContactTime: workout.statistics(for: HKQuantityType(.runningGroundContactTime))?.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)),
                avgVerticalOscillation: workout.statistics(for: HKQuantityType(.runningVerticalOscillation))?.averageQuantity()?.doubleValue(for: .meterUnit(with: .centi)),
                avgVerticalRatio: nil,
                avgPower: workout.statistics(for: HKQuantityType(.runningPower))?.averageQuantity()?.doubleValue(for: .watt())
            )
            activity.laps = MockFactory.distanceLaps(samples: samples.filter { $0.distance != nil }, every: 1_000)
        case .bike:
            let cadence = workout.statistics(for: HKQuantityType(.cyclingCadence))?.averageQuantity()?.doubleValue(for: bpm)
            let power = workout.statistics(for: HKQuantityType(.cyclingPower))?.averageQuantity()?.doubleValue(for: .watt())
            activity.bike = BikeMetrics(avgPower: power.map { Int($0) }, avgCadence: cadence.map { Int($0) },
                                        elevationGain: activity.elevationGain)
        case .swim:
            let strokes = workout.statistics(for: HKQuantityType(.swimmingStrokeCount))?.sumQuantity()?.doubleValue(for: .count())
            let pool = (workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity)?.doubleValue(for: .meter())
            activity.swim = SwimMetrics(poolLength: pool, totalStrokes: strokes.map { Int($0) })
        default:
            break
        }
        return activity
    }

    private func heartRateSamples(for workout: HKWorkout) async throws -> [Sample] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store).map {
            Sample(offset: $0.startDate.timeIntervalSince(workout.startDate),
                   heartRate: Int($0.quantity.doubleValue(for: bpm)))
        }
    }

    private func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: routePredicate)],
            sortDescriptors: []
        )
        guard let route = try await routeDescriptor.result(for: store).first as? HKWorkoutRoute else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            var locations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                if let error { continuation.resume(throwing: error); return }
                locations.append(contentsOf: batch ?? [])
                if done { continuation.resume(returning: locations) }
            }
            store.execute(query)
        }
    }

    /// Ordnet GPS-Punkte den Samples zu und ergänzt Geschwindigkeit/Distanz/Höhe.
    private func merge(samples: [Sample], route: [CLLocation], start: Date) -> [Sample] {
        var result: [Sample] = []
        var distance = 0.0
        var previous: CLLocation?
        var hrIndex = 0
        for location in route {
            if let previous { distance += location.distance(from: previous) }
            previous = location
            let offset = location.timestamp.timeIntervalSince(start)
            while hrIndex + 1 < samples.count && samples[hrIndex + 1].offset <= offset { hrIndex += 1 }
            result.append(Sample(
                offset: offset,
                heartRate: samples.isEmpty ? nil : samples[hrIndex].heartRate,
                speed: location.speed >= 0 ? location.speed : nil,
                altitude: location.altitude,
                distance: distance,
                location: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            ))
        }
        return result
    }

    // MARK: Wellness

    func fetchWellness(from: Date, to: Date) async throws -> [DailyWellness] {
        let cal = Calendar.training
        let predicate = HKQuery.predicateForSamples(withStart: cal.startOfDay(for: from), end: to)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        let rhr = try await dailyAverage(.restingHeartRate, unit: bpm, predicate: predicate)
        let hrv = try await dailyAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: predicate)
        let vo2 = try await dailyAverage(.vo2Max, unit: vo2Unit, predicate: predicate)
        let sleep = try await sleepByNight(predicate: predicate)

        let days = Set(rhr.keys).union(hrv.keys).union(vo2.keys).union(sleep.keys)
        return days.sorted().map { day in
            DailyWellness(date: day,
                          restingHeartRate: rhr[day].map { Int($0) },
                          hrvNightlyAvg: hrv[day],
                          sleep: sleep[day],
                          vo2maxRun: vo2[day],
                          source: .healthKit)
        }
    }

    private func dailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> [Date: Double] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        let grouped = Dictionary(grouping: samples) { Calendar.training.startOfDay(for: $0.startDate) }
        return grouped.compactMapValues { list in list.map { $0.quantity.doubleValue(for: unit) }.mean }
    }

    /// Schlaf wird dem Tag zugeordnet, an dem man aufwacht.
    private func sleepByNight(predicate: NSPredicate) async throws -> [Date: SleepSummary] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        var result: [Date: SleepSummary] = [:]
        for sample in samples {
            let day = Calendar.training.startOfDay(for: sample.endDate)
            var s = result[day] ?? SleepSummary(total: 0, deep: 0, light: 0, rem: 0, awake: 0)
            let d = sample.endDate.timeIntervalSince(sample.startDate)
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepDeep: s.deep += d; s.total += d
            case .asleepREM: s.rem += d; s.total += d
            case .asleepCore, .asleepUnspecified: s.light += d; s.total += d
            case .awake: s.awake += d
            default: break
            }
            result[day] = s
        }
        return result
    }

    // MARK: Mapping

    static func sport(for type: HKWorkoutActivityType) -> Sport? {
        switch type {
        case .running: return .run
        case .cycling: return .bike
        case .swimming: return .swim
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        case .swimBikeRun, .transition: return nil // Multisport-Container: Einzelteile kommen separat
        default: return .other
        }
    }
}
