import Foundation

/// Client für die Garmin-Daten über das eigene Backend.
///
/// Warum ein Backend? Die Garmin Connect Developer Program APIs (Health/Activity API)
/// sind Partner-APIs: Garmin pusht neue Daten per Webhook (Push/Ping) an einen Server,
/// Token-Tausch braucht das client_secret, und Abfragefenster sind auf 24 h Upload-Zeit begrenzt.
/// Das Backend speichert die Rohdaten und reicht sie hier im Garmin-Originalformat durch
/// (siehe DTOs unten), plus optional die FIT-Datei für Laufdynamik/SWOLF.
struct GarminAPIClient: TrainingDataSource {
    let kind: DataSourceKind = .garmin
    let baseURL: URL
    let sessionToken: String

    static func makeIfConfigured() -> GarminAPIClient? {
        guard let url = GarminConfig.backendURL,
              let token = KeychainStore.get(GarminConfig.sessionTokenKey) else { return nil }
        return GarminAPIClient(baseURL: url, sessionToken: token)
    }

    // MARK: TrainingDataSource

    func fetchActivities(from: Date, to: Date) async throws -> [Activity] {
        let dtos: [GarminActivityDTO] = try await get("v1/garmin/activities", from: from, to: to)
        var result: [Activity] = []
        for dto in dtos {
            guard var activity = dto.toActivity() else { continue }
            // FIT-Datei enthält Laufdynamik, Bahnen (SWOLF) und Laps in voller Auflösung
            if dto.hasFitFile == true, let fit = try? await fitActivity(id: dto.summaryId) {
                activity.samples = fit.samples.isEmpty ? activity.samples : fit.samples
                activity.laps = fit.laps.isEmpty ? activity.laps : fit.laps
                activity.run = fit.run ?? activity.run
                activity.bike = fit.bike ?? activity.bike
                activity.swim = fit.swim ?? activity.swim
            }
            result.append(activity)
        }
        return result
    }

    func fetchWellness(from: Date, to: Date) async throws -> [DailyWellness] {
        let bundles: [GarminDailyBundleDTO] = try await get("v1/garmin/wellness", from: from, to: to)
        return bundles.compactMap { $0.toWellness() }
    }

    // MARK: Netzwerk

    private func get<T: Decodable>(_ path: String, from: Date, to: Date) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "from", value: String(Int(from.timeIntervalSince1970))),
            URLQueryItem(name: "to", value: String(Int(to.timeIntervalSince1970)))
        ]
        let data = try await send(URLRequest(url: components.url!))
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw DataSourceError.decoding(error.localizedDescription) }
    }

    private func fitActivity(id: String) async throws -> Activity? {
        let data = try await send(URLRequest(url: baseURL.appendingPathComponent("v1/garmin/activities/\(id)/fit")))
        return FITActivityMapper.activity(from: try FITDecoder.decode(data), fileID: id)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DataSourceError.invalidResponse(-1) }
        if http.statusCode == 401 { throw DataSourceError.notAuthorized }
        guard (200..<300).contains(http.statusCode) else { throw DataSourceError.invalidResponse(http.statusCode) }
        return data
    }

    // MARK: Workout-Export an die Uhr (Garmin Training API)

    /// Schickt eine geplante Einheit an Garmin Connect → erscheint nach dem Sync auf der Forerunner.
    func pushWorkout(_ workout: PlannedWorkout) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/garmin/workouts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(workout)
        _ = try await send(request)
    }
}

// MARK: - DTOs im Garmin-Format (Activity API / Health API)
// Feldnamen gemäß Garmin-Partnerdoku; bei Abweichungen dort abgleichen.

struct GarminActivityDTO: Decodable {
    let summaryId: String
    let activityName: String?
    let activityType: String
    let startTimeInSeconds: Int
    let durationInSeconds: Int
    let distanceInMeters: Double?
    let averageHeartRateInBeatsPerMinute: Int?
    let maxHeartRateInBeatsPerMinute: Int?
    let activeKilocalories: Int?
    let totalElevationGainInMeters: Double?
    let averageRunCadenceInStepsPerMinute: Double?
    let averageBikeCadenceInRoundsPerMinute: Double?
    let averageSwimCadenceInStrokesPerMinute: Double?
    let averagePowerInWatts: Double?
    let numberOfActiveLengths: Int?
    let samples: [GarminSampleDTO]?
    let laps: [GarminLapDTO]?
    /// vom Backend gesetzt, wenn die FIT-Datei abrufbar ist
    let hasFitFile: Bool?

    var sport: Sport {
        let t = activityType.uppercased()
        if t.contains("SWIM") { return .swim }
        if t.contains("CYCLING") || t.contains("BIKING") || t.contains("VIRTUAL_RIDE") { return .bike }
        if t.contains("RUN") { return .run }
        if t.contains("STRENGTH") { return .strength }
        return .other
    }

    func toActivity() -> Activity? {
        let start = Date(timeIntervalSince1970: TimeInterval(startTimeInSeconds))
        let samples = (self.samples ?? []).map { $0.toSample(activityStart: startTimeInSeconds) }
        let laps: [Lap] = (self.laps ?? []).enumerated().map { index, lap in
            let next = index + 1 < (self.laps?.count ?? 0) ? self.laps![index + 1].startTimeInSeconds : startTimeInSeconds + durationInSeconds
            return Lap(index: index, startOffset: TimeInterval(lap.startTimeInSeconds - startTimeInSeconds),
                       duration: TimeInterval(next - lap.startTimeInSeconds), distance: 0, isInterval: false)
        }
        var activity = Activity(
            id: "garmin-\(summaryId)",
            sport: sport,
            name: activityName ?? sport.displayName,
            startDate: start,
            duration: TimeInterval(durationInSeconds),
            distance: distanceInMeters ?? 0,
            avgHeartRate: averageHeartRateInBeatsPerMinute,
            maxHeartRate: maxHeartRateInBeatsPerMinute,
            calories: activeKilocalories,
            elevationGain: totalElevationGainInMeters,
            source: .garmin,
            samples: samples,
            laps: laps
        )
        switch sport {
        case .run:
            activity.run = RunDynamics(avgCadence: averageRunCadenceInStepsPerMinute, avgPower: averagePowerInWatts)
        case .bike:
            let powers = samples.map { Double($0.power ?? 0) }
            activity.bike = BikeMetrics(
                avgPower: averagePowerInWatts.map { Int($0) },
                normalizedPower: SeriesMath.normalizedPower(values: powers, interval: SeriesMath.sampleInterval(samples)).map { Int($0) },
                avgCadence: averageBikeCadenceInRoundsPerMinute.map { Int($0) },
                elevationGain: totalElevationGainInMeters,
                powerCurve: SeriesMath.powerCurve(samples: samples)
            )
        case .swim:
            activity.swim = SwimMetrics(poolLength: nil, avgStrokeRate: averageSwimCadenceInStrokesPerMinute)
        default: break
        }
        return activity
    }
}

struct GarminSampleDTO: Decodable {
    let startTimeInSeconds: Int
    let latitudeInDegree: Double?
    let longitudeInDegree: Double?
    let elevationInMeters: Double?
    let heartRate: Int?
    let speedMetersPerSecond: Double?
    let stepsPerMinute: Double?
    let totalDistanceInMeters: Double?
    let powerInWatts: Double?
    let bikeCadenceInRPM: Double?
    let swimCadenceInStrokesPerMinute: Double?

    func toSample(activityStart: Int) -> Sample {
        let cadence = stepsPerMinute ?? bikeCadenceInRPM ?? swimCadenceInStrokesPerMinute
        var location: GeoPoint?
        if let lat = latitudeInDegree, let lon = longitudeInDegree { location = GeoPoint(latitude: lat, longitude: lon) }
        return Sample(offset: TimeInterval(startTimeInSeconds - activityStart),
                      heartRate: heartRate,
                      speed: speedMetersPerSecond,
                      power: powerInWatts.map { Int($0) },
                      cadence: cadence.map { Int($0) },
                      altitude: elevationInMeters,
                      distance: totalDistanceInMeters,
                      location: location)
    }
}

struct GarminLapDTO: Decodable {
    let startTimeInSeconds: Int
}

/// Vom Backend pro Kalendertag gebündelte Health-API-Summaries.
struct GarminDailyBundleDTO: Decodable {
    struct Daily: Decodable {
        let restingHeartRateInBeatsPerMinute: Int?
        let averageStressLevel: Int?
        let bodyBatteryChargedValue: Int?
        let bodyBatteryDrainedValue: Int?
        let steps: Int?
    }
    struct Sleep: Decodable {
        struct Score: Decodable { let value: Int? }
        let durationInSeconds: Int?
        let deepSleepDurationInSeconds: Int?
        let lightSleepDurationInSeconds: Int?
        let remSleepInSeconds: Int?
        let awakeDurationInSeconds: Int?
        let overallSleepScore: Score?
    }
    struct HRV: Decodable { let lastNightAvg: Double? }
    struct UserMetrics: Decodable { let vo2Max: Double?; let vo2MaxCycling: Double? }
    /// Nicht offiziell Teil jeder API-Stufe – Backend liefert es nur, wenn verfügbar.
    struct Readiness: Decodable { let score: Int?; let recoveryTimeInHours: Double? }

    let calendarDate: String          // "2026-10-21"
    let daily: Daily?
    let sleep: Sleep?
    let hrv: HRV?
    let userMetrics: UserMetrics?
    let readiness: Readiness?

    func toWellness() -> DailyWellness? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: calendarDate) else { return nil }
        var sleepSummary: SleepSummary?
        if let s = sleep, let total = s.durationInSeconds {
            sleepSummary = SleepSummary(total: TimeInterval(total),
                                        deep: TimeInterval(s.deepSleepDurationInSeconds ?? 0),
                                        light: TimeInterval(s.lightSleepDurationInSeconds ?? 0),
                                        rem: TimeInterval(s.remSleepInSeconds ?? 0),
                                        awake: TimeInterval(s.awakeDurationInSeconds ?? 0),
                                        score: s.overallSleepScore?.value)
        }
        let high = daily?.bodyBatteryChargedValue
        return DailyWellness(
            date: Calendar.training.startOfDay(for: date),
            restingHeartRate: daily?.restingHeartRateInBeatsPerMinute,
            hrvNightlyAvg: hrv?.lastNightAvg,
            sleep: sleepSummary,
            avgStress: daily?.averageStressLevel,
            bodyBatteryHigh: high,
            bodyBatteryLow: nil,
            trainingReadiness: readiness?.score,
            recoveryTimeHours: readiness?.recoveryTimeInHours,
            vo2maxRun: userMetrics?.vo2Max,
            vo2maxBike: userMetrics?.vo2MaxCycling,
            steps: daily?.steps,
            source: .garmin
        )
    }
}
