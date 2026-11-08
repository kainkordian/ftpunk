import Foundation
import Testing
import FTPunkDomain

private func config() throws -> SessionConfiguration {
    try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .trainer, cadenceSource: .trainer)
}

@Test func steadyRideHasEqualAverageAndNormalizedPower() throws {
    var session = TestSession(configuration: try config())
    session.samples = (0...120).map { RideSample(time: Double($0), power: 200, cadence: 90, heartRate: 140) }
    session.endedAtOffset = 120
    let summary = RideSummary.make(session)
    #expect(abs((summary.averagePower ?? 0) - 200) < 0.001)
    #expect(abs((summary.normalizedPower ?? 0) - 200) < 0.001)
    #expect(summary.averageHeartRate == 140 && summary.maximumHeartRate == 140)
    #expect(summary.averageCadence == 90 && summary.maximumPower == 200)
}

@Test func normalizedPowerIsHigherForVariableEffort() throws {
    var samples: [RideSample] = []
    for t in 0..<240 { samples.append(RideSample(time: Double(t), power: (t / 60) % 2 == 0 ? 300 : 100)) }
    let np = try #require(RideSummary.normalizedPower(samples))
    let average = try #require(RideStats.averagePower(samples))
    #expect(abs(average - 200) < 1)
    #expect(np > average + 10)
}

@Test func normalizedPowerNeedsThirtySecondsAndIgnoresPausedGaps() {
    #expect(RideSummary.normalizedPower((0..<20).map { RideSample(time: Double($0), power: 200) }) == nil)
    let ride = (0..<40).map { RideSample(time: Double($0), power: 200) } + (400..<440).map { RideSample(time: Double($0), power: 200) }
    // A long pause leaves no zeros behind: the result stays 200 W.
    #expect(abs((RideSummary.normalizedPower(ride) ?? 0) - 200) < 0.001)
}

@Test func averageCadenceAndHeartRateSkipStops() {
    var session = TestSession(configuration: try! config())
    session.samples = [RideSample(time: 0, cadence: 90), RideSample(time: 1, cadence: 90), RideSample(time: 2, cadence: 0),
                       RideSample(time: 3, cadence: 0), RideSample(time: 4, cadence: 90)]
    #expect(RideSummary.make(session).averageCadence == 90)
    #expect(RideSummary.make(TestSession(configuration: try! config())).averagePower == nil)
}

@Test func workoutTargetSeriesFollowsStepsPausesAndIntensity() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Two", steps: [.init("A", seconds: 10, watts: 100), .init("B", seconds: 10, watts: 200)])
    var session = TestSession(configuration: try config())
    session.training = plan
    session.events = [SessionEvent(time: 0, message: "Training"),
                      SessionEvent(time: 5, message: "Training paused; trainer release requested"),
                      SessionEvent(time: 8, message: "Training resumed"),
                      SessionEvent(time: 14, message: "Workout intensity changed to 110%")]
    session.endedAtOffset = 23
    let points = TargetSeries.make(session)
    func value(at time: Double) -> Double? { points.last { $0.time <= time && $0.time >= 0 }?.watts }
    #expect(value(at: 2) == 100)
    #expect(!points.contains { $0.time > 5 && $0.time < 8 })
    #expect(points.map(\.segment).max() == 1)
    // Step B starts at 10 s of riding = 13 s of the clock (3 s paused).
    #expect(value(at: 13) == 200)
    #expect(value(at: 15) == 220)
    #expect(TargetSeries.make(TestSession(configuration: try config())).isEmpty)
}

@Test func rampTargetSeriesCoversWarmupRampAndCooldown() throws {
    let configuration = try SessionConfiguration(warmupSeconds: 60, riderID: RiderProfile.legacyID, powerSource: .trainer, cadenceSource: .trainer)
    var session = TestSession(configuration: configuration)
    session.events = [SessionEvent(time: 0, message: "Warm-up")]
    session.rampStart = 60; session.rampEnd = 200; session.cooldownStart = 200; session.endedAtOffset = 260
    session.outcome = .finishedEarly
    let points = TargetSeries.make(session)
    #expect(points.first?.watts == Double(configuration.warmupPower))
    #expect(points.contains { $0.time >= 60 && $0.time <= 200 && $0.watts == Double(configuration.rampPower(at: 139)) })
    #expect(points.last?.watts == Double(configuration.preset.cooldownPower))
}

@Test func autoPausePausesAfterThreeStoppedSecondsAndResumesAfterTwoPedalledOnes() {
    var rule = AutoPause()
    #expect(rule.update(time: 0, phase: .riding, power: 0, canResume: false) == nil)
    #expect(rule.update(time: 2.9, phase: .riding, power: 0, canResume: false) == nil)
    #expect(rule.update(time: 3, phase: .riding, power: 0, canResume: false) == .pause)
    #expect(rule.update(time: 10, phase: .paused, power: 0, canResume: false) == nil)
    #expect(rule.update(time: 11, phase: .paused, power: 150, canResume: true) == nil)
    #expect(rule.update(time: 12.9, phase: .paused, power: 150, canResume: true) == nil)
    #expect(rule.update(time: 13, phase: .paused, power: 150, canResume: true) == .resume)
}

@Test func autoPauseIgnoresBriefStopsStaleReadingsAndManualPauses() {
    var rule = AutoPause()
    _ = rule.update(time: 0, phase: .riding, power: 0, canResume: false)
    _ = rule.update(time: 2, phase: .riding, power: 120, canResume: true) // pedalling again: the count restarts
    #expect(rule.update(time: 4, phase: .riding, power: 0, canResume: false) == nil)
    #expect(rule.update(time: 6, phase: .riding, power: nil, canResume: false) == nil) // stale reading is not a stop
    // A pause the rider made is never resumed on its own.
    var manual = AutoPause()
    #expect(manual.update(time: 0, phase: .paused, power: 200, canResume: true) == nil)
    #expect(manual.update(time: 30, phase: .paused, power: 200, canResume: true) == nil)
    #expect(manual.update(time: 0, phase: .waiting, power: 0, canResume: false) == nil)
}

@Test func targetSeriesCanStartPartWayThrough() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Two", steps: [.init("A", seconds: 10, watts: 100), .init("B", seconds: 10, watts: 200)])
    var session = TestSession(configuration: try config())
    session.training = plan
    session.events = [SessionEvent(time: 0, message: "Training")]
    session.endedAtOffset = 20
    let tail = TargetSeries.make(session, from: 12)
    #expect(tail.first?.time == 12 && tail.first?.watts == 200 && tail.last?.time == 20)
    #expect(!tail.contains { $0.watts == 100 })
}
