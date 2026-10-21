import XCTest
@testable import TriCoach

final class AnalyticsTests: XCTestCase {
    private let profile = AthleteProfile()

    func testBikeTSSAtFTPForOneHourIs100() {
        var a = Activity(id: "t", sport: .bike, name: "t", startDate: Date(), duration: 3600, distance: 36_000, source: .mock)
        a.bike = BikeMetrics(normalizedPower: profile.ftp)
        XCTAssertEqual(TrainingLoad.tss(for: a, profile: profile), 100, accuracy: 0.5)
    }

    func testRunTSSAtThresholdPaceIs100() {
        let a = Activity(id: "r", sport: .run, name: "r", startDate: Date(), duration: 3600,
                         distance: 3600 * profile.thresholdRunSpeed, source: .mock)
        XCTAssertEqual(TrainingLoad.tss(for: a, profile: profile), 100, accuracy: 0.5)
    }

    func testVDOTMatchesDanielsTable() {
        // Daniels: 5 km in 20:00 ≈ VDOT 49,8
        XCTAssertEqual(RunPredictor.vdot(distance: 5_000, time: 20 * 60), 49.8, accuracy: 0.3)
        let tenK = RunPredictor.predictTime(vdot: 49.8, distance: 10_000)
        XCTAssertEqual(tenK, 41 * 60 + 35, accuracy: 30)
    }

    func testNormalizedPowerOfConstantPowerEqualsPower() {
        let values = Array(repeating: 250.0, count: 720)
        XCTAssertEqual(SeriesMath.normalizedPower(values: values, interval: 5) ?? 0, 250, accuracy: 0.01)
    }

    func testAeroModelRoundTrip() {
        let v = AeroModel.speed(power: 250, cda: 0.30, mass: 76)
        XCTAssertEqual(AeroModel.power(speed: v, cda: 0.30, mass: 76), 250, accuracy: 0.5)
        XCTAssertEqual(AeroModel.estimateCdA(power: 250, speed: v, mass: 76) ?? 0, 0.30, accuracy: 0.001)
    }

    func testMergerPrefersGarminOverHealthKit() {
        let start = Date()
        let hk = Activity(id: "hk", sport: .run, name: "hk", startDate: start, duration: 1800, distance: 5000, source: .healthKit)
        let garmin = Activity(id: "g", sport: .run, name: "g", startDate: start.addingTimeInterval(30), duration: 1800, distance: 5000, source: .garmin)
        let merged = ActivityMerger.merge([[hk], [garmin]])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "g")
    }

    func testPMCConvergesToConstantLoad() {
        let cal = Calendar.training
        let activities = (0..<200).map { back -> Activity in
            var a = Activity(id: "\(back)", sport: .run, name: "", startDate: cal.date(byAdding: .day, value: -back, to: Date())!,
                             duration: 3600, distance: 10_000, source: .mock)
            a.tss = 60
            return a
        }
        let series = TrainingLoad.performanceSeries(activities: activities, from: Date().addingTimeInterval(-86_400 * 7), to: Date())
        XCTAssertEqual(series.last?.ctl ?? 0, 60, accuracy: 2)
        XCTAssertEqual(series.last?.atl ?? 0, 60, accuracy: 1)
    }

    func testSwolf() {
        let length = SwimLength(index: 0, duration: 22.4, strokes: 16, strokeType: .freestyle)
        XCTAssertEqual(length.swolf, 38)
    }

    func testMockDataIsDeterministicAndComplete() {
        let a1 = MockFactory(profile: profile).activities(daysBack: 30)
        let a2 = MockFactory(profile: profile).activities(daysBack: 30)
        XCTAssertEqual(a1.map(\.id), a2.map(\.id))
        XCTAssertTrue(a1.contains { $0.sport == .swim && !($0.swim?.lengths.isEmpty ?? true) })
        XCTAssertTrue(a1.contains { $0.sport == .bike && !($0.bike?.powerCurve.isEmpty ?? true) })
        XCTAssertTrue(a1.contains { $0.sport == .run && $0.run?.avgGroundContactTime != nil })
    }

    func testFITDecoderRejectsGarbage() {
        XCTAssertThrowsError(try FITDecoder.decode(Data([0, 1, 2, 3])))
    }

    func testRaceSplitPredictionIsPlausible() {
        let p = RaceSplitPredictor.predict(format: .olympic, profile: profile)
        // Olympische Distanz für dieses Profil: grob 2:00–2:30 h
        XCTAssertGreaterThan(p.total, 2 * 3600)
        XCTAssertLessThan(p.total, 2.5 * 3600)
    }
}
