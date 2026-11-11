import Foundation
import Testing
@testable import FTPunkDomain

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

private func loadSession(ftp: Double? = 200, seconds: Int, watts: Double = 200) throws -> TestSession {
    let configuration = try SessionConfiguration(priorFTP: ftp.map { FTPEntry(watts: $0) }, warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .trainer, cadenceSource: .trainer)
    var session = TestSession(configuration: configuration)
    session.samples = (0..<seconds).map { RideSample(time: Double($0), power: watts) }
    session.endedAtOffset = Double(seconds)
    return session
}

@Test func trainingLoadOfAnHourAtFTPIsOneHundred() throws {
    let load = TrainingLoad.make(try loadSession(seconds: 3600))
    #expect(abs((load.normalizedPower ?? 0) - 200) < 0.000001)
    #expect(abs((load.intensityFactor ?? 0) - 1) < 0.000001)
    #expect(abs((load.trainingStressScore ?? 0) - 100) < 0.0001)
}

@Test func trainingLoadWithoutFTPHasNoIntensityOrStress() throws {
    let load = TrainingLoad.make(try loadSession(ftp: nil, seconds: 600))
    #expect(load.normalizedPower != nil); #expect(load.intensityFactor == nil); #expect(load.trainingStressScore == nil)
}

@Test func trainingLoadNeedsThirtySeconds() throws {
    let short = TrainingLoad.make(try loadSession(seconds: 29))
    #expect(short.normalizedPower == nil); #expect(short.intensityFactor == nil); #expect(short.trainingStressScore == nil)
    #expect(TrainingLoad.make(try loadSession(seconds: 30)).normalizedPower != nil)
}

@Test func pausedSamplesCountNeitherInTheLoadNorOnTheCard() throws {
    var paused = try loadSession(seconds: 300)
    // A hard minute inside a pause, which keeps delivering samples.
    paused.samples = paused.samples.map { $0.time >= 100 && $0.time < 160 ? RideSample(time: $0.time, power: 900) : $0 }
    paused.events = [SessionEvent(time: 100, message: "Training paused; trainer release requested"), SessionEvent(time: 160, message: "Training resumed")]
    let load = TrainingLoad.make(paused)
    #expect(abs((load.normalizedPower ?? 0) - 200) < 0.000001)
    #expect(RideSummary.make(paused).normalizedPower == load.normalizedPower)
    // 240 ridden seconds at FTP.
    let expected: Double = 100.0 * 240 / 3600
    #expect(abs((load.trainingStressScore ?? 0) - expected) < 0.000001)
}

@Test func aShortPauseIsNotFilledWithTheLastPower() {
    // Seconds 40 and 41 are paused: a one-second hole would otherwise be held over.
    let samples = (0..<80).filter { $0 != 40 }.map { RideSample(time: Double($0), power: 200) }
    let pauses = [RidePause(stop: 40, resume: 41)]
    #expect(RideSummary.oneHertzPower(samples, pauses: pauses).count == 79)
    #expect(RideSummary.oneHertzPower(samples, pauses: []).count == 80)
}

@Test func pausedSamplesCountInNoneOfTheRideFigures() throws {
    var session = TestSession(configuration: try config())
    session.samples = (0...300).map { t in
        (100..<160).contains(t) ? RideSample(time: Double(t), power: 900, cadence: 120, heartRate: 190)
                                : RideSample(time: Double(t), power: 200, cadence: 90, heartRate: 140)
    }
    session.events = [SessionEvent(time: 100, message: "Training paused; trainer release requested"), SessionEvent(time: 160, message: "Training resumed")]
    session.endedAtOffset = 300
    let summary = RideSummary.make(session)
    #expect(abs((summary.averagePower ?? 0) - 200) < 0.001 && summary.maximumPower == 200)
    #expect(abs((summary.averageHeartRate ?? 0) - 140) < 0.001 && summary.maximumHeartRate == 140)
    #expect(abs((summary.averageCadence ?? 0) - 90) < 0.001)
    #expect(summary.duration == 300)
}

@Test func trainerPowerIsSummarisedOnlyWhileAMeterIsTheSource() throws {
    let meter = try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .externalPowerMeter, cadenceSource: .externalPowerMeter)
    var session = TestSession(configuration: meter)
    // Each notification is its own sample: the meter's at whole seconds, the trainer's 0.4 s later.
    for t in 0...120 {
        session.samples.append(RideSample(time: Double(t), power: 200, cadence: 90))
        session.samples.append(RideSample(time: Double(t) + 0.4, trainerPower: 210))
    }
    session.endedAtOffset = 120.4
    let summary = RideSummary.make(session)
    #expect(abs((summary.averagePower ?? 0) - 200) < 0.001)
    #expect(abs((summary.trainerAveragePower ?? 0) - 210) < 0.001)
    #expect(abs((summary.trainerNormalizedPower ?? 0) - 210) < 0.001)
    var trainerOnly = TestSession(configuration: try config())
    trainerOnly.samples = (0...120).map { RideSample(time: Double($0), power: 200, trainerPower: 200) }
    #expect(RideSummary.make(trainerOnly).trainerAveragePower == nil)
}

@Test func aMomentOfTheRecordingHasEveryFreshReading() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Hover", steps: [.init("Warm", seconds: 20, watts: 100), .init("Work", seconds: 40, watts: 200)])
    var engine = RideEngine(configuration: try config(), training: plan)
    for t in 0...30 { engine.receive(.init(time: Double(t), power: 205, cadence: 90, heartRate: 140)); engine.tick(at: Double(t)) }
    let moment = RideMoment.at(engine.session, time: 25.5)
    #expect(moment.power == 205 && moment.heartRate == 140 && moment.cadence == 90)
    #expect(moment.target == TargetSeries.value(engine.session, at: 25.5))
    #expect(moment.trainerPower == nil)
    let stale = RideMoment.at(engine.session, time: 40)
    #expect(stale.power == nil && stale.heartRate == nil)

    let meter = try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .externalPowerMeter, cadenceSource: .externalPowerMeter)
    var paired = TestSession(configuration: meter)
    for t in 0...10 {
        paired.samples.append(RideSample(time: Double(t), power: 200, cadence: 90))
        paired.samples.append(RideSample(time: Double(t) + 0.4, trainerPower: 190))
    }
    let both = RideMoment.at(paired, time: 5.5)
    #expect(both.power == 200 && both.trainerPower == 190)
}
