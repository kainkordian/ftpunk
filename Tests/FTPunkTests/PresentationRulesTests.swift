import Foundation
import Testing
import FTPunkDomain

private func ready(_ kind: RideKindID = .ftpTest, _ change: (inout StartReadiness) -> Void = { _ in }) -> StartReadiness {
    var value = StartReadiness(kind: kind)
    value.trainerConnected = true; value.trainerControlReady = true; value.powerRangeKnown = true
    value.freshSelectedPower = true; value.supportsResistance = true
    change(&value)
    return value
}

@Test func startBlockersAreReportedInTheOrderARiderCanFixThem() {
    #expect(StartBlocker.blocker(for: ready()) == nil)
    #expect(StartBlocker.blocker(for: ready { $0.isFinishing = true; $0.trainerConnected = false }) == .finishing)
    #expect(StartBlocker.blocker(for: ready { $0.isBusy = true }) == .busy)
    #expect(StartBlocker.blocker(for: ready { $0.trainerConnected = false; $0.trainerControlReady = false }) == .trainerMissing)
    #expect(StartBlocker.blocker(for: ready { $0.trainerControlReady = false }) == .trainerControl)
    #expect(StartBlocker.blocker(for: ready { $0.powerRangeKnown = false }) == .powerRange)
    #expect(StartBlocker.blocker(for: ready { $0.matchingChoicePending = true; $0.trainerConnected = false }) == .matchingChoice)
    #expect(StartBlocker.blocker(for: ready { $0.freshSelectedPower = false }) == .noPower(.trainer))
    #expect(StartBlocker.blocker(for: ready { $0.freshSelectedPower = false; $0.powerSource = .externalPowerMeter }) == .noPower(.externalPowerMeter))
    #expect(StartBlocker.blocker(for: ready { $0.durationsValid = false }) == .invalidDurations)
    #expect(StartBlocker.blocker(for: ready(.workout) { $0.needsFTP = true }) == .needsFTP)
}

@Test func resistanceNeedsAdvertisedSupportButNotAPowerRange() {
    #expect(StartBlocker.blocker(for: ready(.resistance) { $0.supportsResistance = false }) == .resistanceUnsupported)
    #expect(StartBlocker.blocker(for: ready(.resistance) { $0.powerRangeKnown = false }) == nil)
    // Durations only matter for the FTP test.
    #expect(StartBlocker.blocker(for: ready(.freeERG) { $0.durationsValid = false }) == nil)
}

@Test func mockRidesSkipHardwareBlockersButStillExplainTheRest() {
    var mock = StartReadiness(kind: .ftpTest); mock.isMock = true
    #expect(StartBlocker.blocker(for: mock) == nil)
    mock.durationsValid = false
    #expect(StartBlocker.blocker(for: mock) == .invalidDurations)
}

@Test func everyBlockerHasAPlainReason() {
    let all: [StartBlocker] = [.finishing, .busy, .matchingChoice, .trainerMissing, .trainerControl, .powerRange, .targetsOutOfRange,
                               .resistanceUnsupported, .noPower(.trainer), .noPower(.externalPowerMeter), .invalidDurations, .needsFTP]
    #expect(all.allSatisfy { !$0.reason.isEmpty && $0.reason.hasSuffix(".") })
    #expect(StartBlocker.trainerMissing.reason == "Connect your trainer to start.")
}

@Test func protocolRecommendationFollowsTheReferenceWeightGuideline() {
    #expect(ProtocolRecommendation.recommend(weightKG: 75).preset == .standard)
    #expect(ProtocolRecommendation.recommend(weightKG: 75).reason == "75 kg → 25 W/min")
    #expect(ProtocolRecommendation.recommend(weightKG: 60).preset == .standard)
    #expect(ProtocolRecommendation.recommend(weightKG: 59.5).preset == .gentle)
    #expect(ProtocolRecommendation.recommend(weightKG: 59.5).reason == "59.5 kg → 15 W/min")
    #expect(ProtocolRecommendation.recommend(weightKG: nil).preset == .standard)
    #expect(ProtocolRecommendation.recommend(weightKG: -3).preset == .standard)
}

@Test func retestPromptStartsAtEightWeeks() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86400) }
    #expect(RetestAdvice.evaluate(lastTest: nil, now: now, calendar: calendar) == .never)
    #expect(RetestAdvice.evaluate(lastTest: ago(0), now: now, calendar: calendar) == .recent(weeks: 0))
    #expect(RetestAdvice.evaluate(lastTest: ago(55), now: now, calendar: calendar) == .recent(weeks: 7))
    #expect(RetestAdvice.evaluate(lastTest: ago(56), now: now, calendar: calendar) == .due(weeks: 8))
    #expect(RetestAdvice.evaluate(lastTest: ago(63), now: now, calendar: calendar).message() == "Last test 9 weeks ago, time to retest?")
    #expect(RetestAdvice.evaluate(lastTest: ago(14), now: now, calendar: calendar).message() == "Last test 2 weeks ago")
    #expect(RetestAdvice.evaluate(lastTest: ago(7), now: now, calendar: calendar).message(verb: "FTP set") == "FTP set 1 week ago")
    #expect(RetestAdvice.evaluate(lastTest: now.addingTimeInterval(86400), now: now, calendar: calendar) == .recent(weeks: 0))
    #expect(RetestAdvice.never.message() == nil)
    #expect(RetestAdvice.due(weeks: 8).isDue && !RetestAdvice.recent(weeks: 7).isDue)
}

@Test func resultDeltaNamesTheChangeFromTheCurrentFTP() {
    #expect(ResultDelta(newFTP: 209.3, currentFTP: 250).text == "−41 W vs 250 W")
    #expect(ResultDelta(newFTP: 209.3, currentFTP: 250).watts == -41)
    #expect(ResultDelta(newFTP: 262, currentFTP: 250).text == "+12 W vs 250 W")
    #expect(ResultDelta(newFTP: 250.2, currentFTP: 250).text == "Same as your current 250 W")
    #expect(ResultDelta(newFTP: 210, currentFTP: nil).text == "First FTP for this rider")
    #expect(ResultDelta(newFTP: 210, currentFTP: .nan).watts == 0)
}

@Test func cadenceGuardWarnsOnlyDuringTheRampAndNeverChangesTheFinishRule() {
    #expect(CadenceGuard.state(cadence: 59.9, phase: .ramp) == .low)
    #expect(CadenceGuard.state(cadence: 60, phase: .ramp) == .ok)
    #expect(CadenceGuard.state(cadence: nil, phase: .ramp) == .unknown)
    #expect(CadenceGuard.state(cadence: 40, phase: .warmup) == .ok)
    #expect(CadenceGuard.state(cadence: 40, phase: .ramp, cadenceAvailable: false) == .ok)
    #expect(CadenceGuard.finishBelow == 45 && CadenceGuard.message == "Ramp ends below 45 rpm")
}

@Test func holdToFinishNeedsOneAndAHalfSeconds() {
    #expect(HoldProgress.fraction(held: 0) == 0)
    #expect(HoldProgress.fraction(held: 0.75) == 0.5)
    #expect(!HoldProgress.isComplete(held: 1.49))
    #expect(HoldProgress.isComplete(held: 1.5))
    #expect(HoldProgress.fraction(held: -2) == 0 && HoldProgress.fraction(held: .nan) == 0 && HoldProgress.fraction(held: 99) == 1)
}

@Test func phaseTimelineSegmentsAndProgress() {
    let warm = PhaseTimeline.make(phase: .warmup, warmup: 600, cooldown: 180, elapsedInPhase: 300)
    #expect(warm.segments.map(\.phase) == [.warmup, .ramp, .cooldown])
    #expect(warm.segments.first?.start == 0 && abs((warm.segments.last?.end ?? 0) - 1) < 1e-9)
    #expect(warm.progress > 0 && warm.progress < warm.segments[0].end)
    let ramp = PhaseTimeline.make(phase: .ramp, warmup: 600, cooldown: 180, elapsedInPhase: 120)
    #expect(ramp.progress > warm.segments[0].end && ramp.progress < ramp.segments[1].end)
    let skipped = PhaseTimeline.make(phase: .ramp, warmup: 0, cooldown: 0, elapsedInPhase: 10)
    #expect(skipped.segments.map(\.phase) == [.ramp])
    #expect(PhaseTimeline.make(phase: .completed, warmup: 600, cooldown: 180, elapsedInPhase: 0).progress == 1)
    #expect(PhaseTimeline.make(phase: .waiting, warmup: 600, cooldown: 180, elapsedInPhase: 0).progress == 0)
    // A long ramp extends the open-ended segment rather than overflowing the bar.
    #expect(PhaseTimeline.make(phase: .ramp, warmup: 60, cooldown: 60, elapsedInPhase: 1500, rampElapsed: 1500).progress <= 1)
}

@Test func deviceSummaryDistinguishesReadyAttentionAndOff() {
    let off = DeviceSummary.make(mock: false, trainerConnected: false, trainerReady: false, powerSource: .trainer, externalMeterConnected: false, heartRateConnected: false)
    #expect(off.trainer == .off && off.power == .off && off.heartRate == .off)
    let attention = DeviceSummary.make(mock: false, trainerConnected: true, trainerReady: false, powerSource: .trainer, externalMeterConnected: false, heartRateConnected: true)
    #expect(attention.trainer == .attention && attention.power == .attention && attention.heartRate == .ready)
    let meter = DeviceSummary.make(mock: false, trainerConnected: true, trainerReady: true, powerSource: .externalPowerMeter, externalMeterConnected: false, heartRateConnected: false)
    #expect(meter.trainer == .ready && meter.power == .attention && meter.heartRate == .off)
    #expect(meter.description.contains("external meter"))
    let mock = DeviceSummary.make(mock: true, trainerConnected: false, trainerReady: false, powerSource: .trainer, externalMeterConnected: false, heartRateConnected: false)
    #expect(mock.trainer == .ready && mock.description.hasPrefix("Mock sensors"))
}

@Test func riderInitialsUseUpToTwoWords() {
    #expect(RiderInitials.make("Alex") == "A")
    #expect(RiderInitials.make("alex rider") == "AR")
    #expect(RiderInitials.make("Alex Van Rider") == "AV")
    #expect(RiderInitials.make("  ") == "?")
}

@Test func workoutProfileScalesOriginalTargetsAndKnowsItsPeak() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Test", ftpWatts: 200, steps: [
        .init("Ramp", seconds: 60, watts: 100, endWatts: 140), .init("Hold", seconds: 120, watts: 180)])
    let segments = WorkoutProfile.segments(for: plan)
    #expect(segments.map(\.start) == [0, 60] && segments.map(\.end) == [60, 180])
    #expect(segments[0].averageWatts == 120)
    #expect(WorkoutProfile.peakWatts(for: plan) == 180)
    #expect(abs(WorkoutProfile.segments(for: plan, intensity: 110)[1].startWatts - 198) < 1e-9)
    #expect(abs(WorkoutProfile.averageWatts(for: plan) - (120 * 60 + 180 * 120) / 180) < 1e-9)
    #expect(WorkoutProfile.averageFraction(for: plan) != nil)
}

@Test func resultChartBandsFollowTheScoredPhases() throws {
    var session = TestSession(configuration: try SessionConfiguration())
    session.rampStart = 600; session.rampEnd = 1000; session.cooldownStart = 1000; session.endedAtOffset = 1180
    session.result = FTPResult(bestMinutePower: 290, windowStart: 900, windowEnd: 960)
    let bands = ResultChartModel.bands(for: session)
    #expect(bands.map(\.title) == ["Warm-up", "Ramp", "Cool-down"])
    #expect(bands[1].start == 600 && bands[1].end == 1000)
    let best = try #require(ResultChartModel.bestMinute(for: session))
    #expect(best.title == "Best minute 290 W" && best.start == 900 && best.end == 960)
    session.training = try .freeRide(watts: 100)
    #expect(ResultChartModel.bands(for: session).isEmpty)
}

@Test func cadenceRowIsAProblemOnlyOnceDevicesAreConnected() {
    #expect(CadenceStatus.make(source: .trainer, devicesConnected: true) == CadenceStatus(text: "From trainer", isProblem: false))
    #expect(CadenceStatus.make(source: .externalPowerMeter, devicesConnected: true).text == "From power meter")
    #expect(!CadenceStatus.make(source: .unavailable, devicesConnected: false).isProblem)
    #expect(CadenceStatus.make(source: .unavailable, devicesConnected: false).text == "No cadence yet: connect and pedal")
    #expect(CadenceStatus.make(source: .unavailable, devicesConnected: true).isProblem)
}

@Test func durationFormattingForCardsAndClocks() {
    #expect(DurationFormat.compact(3300) == "55 min")
    #expect(DurationFormat.compact(3900) == "1 h 05 min")
    #expect(DurationFormat.compact(500) == "8 min 20 s")
    #expect(DurationFormat.compact(45) == "45 s")
    #expect(DurationFormat.compact(.nan) == "—")
    #expect(DurationFormat.clock(440) == "7:20" && DurationFormat.clock(-1) == "0:00")
}

@Test func adoptionIsDetectedFromTheRidersHistory() throws {
    let result = FTPResult(bestMinutePower: 290, windowStart: 0, windowEnd: 60)
    let start = Date(timeIntervalSince1970: 1_000_000)
    var rider = RiderProfile(name: "Alex")
    #expect(!FTPAdoption.isAdopted(rider: rider, result: result, sessionStart: start))
    #expect(!FTPAdoption.isAdopted(rider: nil, result: result, sessionStart: start))
    rider.ftpHistory = [FTPEntry(watts: result.estimatedFTP, date: start.addingTimeInterval(-60), source: "Ramp test")]
    #expect(!FTPAdoption.isAdopted(rider: rider, result: result, sessionStart: start)) // an older identical value is not this test
    rider.ftpHistory.append(FTPEntry(watts: result.estimatedFTP, date: start.addingTimeInterval(600), source: "Ramp test"))
    #expect(FTPAdoption.isAdopted(rider: rider, result: result, sessionStart: start))
    rider.ftpHistory = [FTPEntry(watts: result.estimatedFTP, date: start.addingTimeInterval(600), source: "Manual")]
    #expect(!FTPAdoption.isAdopted(rider: rider, result: result, sessionStart: start))
}

@Test func resultShowsTheTrainingResultBeforeWhatItChangesAndSharing() {
    let all = ResultLayout.sections(isFTPResult: true, adopted: true, canUpload: true)
    #expect(all == [.headline, .chart, .decision, .trainingHandoff, .upload])
    #expect(ResultLayout.sections(isFTPResult: true, adopted: false, canUpload: false) == [.headline, .chart])
    #expect(ResultLayout.sections(isFTPResult: false, adopted: true, canUpload: false) == [.headline, .chart])
    #expect(ResultLayout.sections(isFTPResult: false, adopted: false, canUpload: true) == [.headline, .chart, .upload])
}

@Test func interruptionExplainsWhatWasSavedAndWhetherAResultExists() throws {
    var session = TestSession(configuration: try SessionConfiguration())
    session.endedAtOffset = 500; session.outcome = .interrupted; session.endReason = "Power from the selected source is no longer fresh."
    let lost = InterruptionSummary.make(session)
    #expect(lost.headline == "Test interrupted" && !lost.hasResult)
    #expect(lost.saved.contains("8 min 20 s") && lost.saved.contains("No FTP estimate"))
    #expect(lost.reason == "Power from the selected source is no longer fresh.")
    session.result = FTPResult(bestMinutePower: 300, windowStart: 0, windowEnd: 60)
    let kept = InterruptionSummary.make(session)
    #expect(kept.hasResult && kept.headline == "Cool-down interrupted" && kept.saved.contains("result was kept"))
    session.result = nil; session.training = try .freeRide(watts: 100); session.endReason = nil
    #expect(InterruptionSummary.make(session).headline == "Ride interrupted")
    #expect(InterruptionSummary.make(session).reason == "The ride stopped unexpectedly.")
}

@Test func averagePowerIgnoresGapsAndIsTimeWeighted() {
    let samples = [RideSample(time: 0, power: 100), RideSample(time: 1, power: 200), RideSample(time: 3, power: 300), RideSample(time: 20, power: 50)]
    // 0–1 s at 100 W, 1–3 s at 200 W, 3–20 s capped at 2 s of 300 W.
    #expect(abs((RideStats.averagePower(samples) ?? 0) - (100 * 1 + 200 * 2 + 300 * 2) / 5) < 1e-9)
    #expect(RideStats.averagePower([]) == nil)
    #expect(RideStats.averagePower([RideSample(time: 0, power: nil), RideSample(time: 1, power: nil)]) == nil)
}

@Test func intensityLabelsDescribeTheHardestConstantStep() throws {
    func plan(_ watts: Int, ftp: Double? = 200) throws -> TrainingPlan {
        try TrainingPlan(kind: .workout, name: "T", ftpWatts: ftp, steps: [.init("Ramp", seconds: 60, watts: 100, endWatts: 190), .init("Main", seconds: 600, watts: watts)])
    }
    #expect(IntensityLabel.label(for: try plan(100)) == "Easy · active recovery")
    #expect(IntensityLabel.label(for: try plan(130)) == "Endurance")
    #expect(IntensityLabel.label(for: try plan(170)) == "Tempo")
    #expect(IntensityLabel.label(for: try plan(200)) == "Threshold")
    #expect(IntensityLabel.label(for: try plan(240)) == "VO2max and above")
    #expect(IntensityLabel.label(for: try plan(240, ftp: nil)) == "Custom power targets")
    #expect(IntensityLabel.mainSetWatts(for: try plan(170)) == 170) // the ramp's end is not a main set
}

@Test func targetsOutsideTheTrainerRangeBlockStartAfterDevicesAreReady() {
    var readiness = StartReadiness(kind: .workout)
    readiness.trainerConnected = true; readiness.trainerControlReady = true; readiness.powerRangeKnown = true; readiness.freshSelectedPower = true
    #expect(StartBlocker.blocker(for: readiness) == nil)
    readiness.targetsInRange = false
    #expect(StartBlocker.blocker(for: readiness) == .targetsOutOfRange)
    readiness.freshSelectedPower = false
    #expect(StartBlocker.blocker(for: readiness) == .targetsOutOfRange) // fix the plan before asking the rider to pedal
    #expect(StartBlocker.targetsOutOfRange.reason.contains("intensity"))
}

@Test func aRideEndingWhileMinimisedBringsBackItsResult() {
    #expect(ResultPresentation.shouldPresent(previous: .ramp, current: .completed, cockpitPresented: false))
    #expect(ResultPresentation.shouldPresent(previous: .riding, current: .interrupted, cockpitPresented: false))
    #expect(!ResultPresentation.shouldPresent(previous: .ramp, current: .completed, cockpitPresented: true))
    #expect(!ResultPresentation.shouldPresent(previous: .ramp, current: .cooldown, cockpitPresented: false))
    #expect(!ResultPresentation.shouldPresent(previous: nil, current: .completed, cockpitPresented: false))
    #expect(!ResultPresentation.shouldPresent(previous: .completed, current: nil, cockpitPresented: false))
}

// MARK: Chaindance Large view and coaching

@Test func theWideLargeLayoutPutsTheSceneWithWhatIsComingOnTheLeftAndTilesOnTheRight() {
    func layout(_ kind: CockpitKind, width: Double = 1200, visual: RideVisualPlacement = .hero, regular: Bool = true, accessibility: Bool = false) -> CockpitLayout {
        .make(phase: .riding, accessibilitySize: accessibility, rideVisual: visual, containerWidth: width, regularWidthClass: regular, kind: kind)
    }
    #expect(layout(.ftpTest).leftColumn == [.scene, .progress] && layout(.ftpTest).rightColumn == [.tiles, .notes])
    #expect(layout(.workout).leftColumn == [.scene, .progress] && layout(.workout).rightColumn == [.tiles, .controls, .notes])
    // A ride with nothing coming up keeps its adjustments under the scene, so the left column is not empty.
    #expect(layout(.freeRide).leftColumn == [.scene, .controls] && layout(.freeRide).rightColumn == [.tiles, .notes])
    // Every block appears exactly once.
    for kind in [CockpitKind.ftpTest, .workout, .freeRide] {
        let blocks = layout(kind).leftColumn + layout(kind).rightColumn
        #expect(Set(blocks).count == blocks.count && blocks.contains(.scene) && blocks.contains(.tiles) && blocks.contains(.notes))
    }
    // Narrow windows, the strip, accessibility sizes and compact width classes stay in one column.
    for single in [layout(.workout, width: 899), layout(.workout, visual: .strip), layout(.workout, regular: false), layout(.workout, accessibility: true)] {
        #expect(!single.sideBySide && single.leftColumn.isEmpty && single.rightColumn.isEmpty)
    }
}

@Test func theLargeSceneIsNotCappedAtASingleColumnWidth() {
    #expect(CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .hero, containerWidth: 430, regularWidthClass: false).maximumContentWidth == 1400)
    #expect(CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .strip, containerWidth: 430).maximumContentWidth == 760)
    #expect(CockpitLayout.make(phase: .riding, accessibilitySize: true, rideVisual: .hero, containerWidth: 430).maximumContentWidth == 760) // falls back to the strip
}

@Test func onlyTheFTPTestSaysStaySeatedAndTheAvatarAndTheTextAgreeOnSprints() {
    // FTP-test ramp at 700 W: the rider never stands in a test, and the line stays "Stay seated".
    let ramp = RideVisualState.make(.init(mode: .ftpTest, phase: .ramp, power: 700, cadence: 90, ftp: 250,
                                          ramp: .init(phaseSeconds: 300, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 300, bestMinuteWatts: nil)))
    #expect(ramp.posture != .standing)
    #expect(CoachingText.line(for: ramp, phase: .ramp) == "Stay seated. Keep a steady, comfortable cadence.")
    #expect(CoachingText.line(for: ramp, phase: .cooldown) == "Ramp scored. Spin gently to cool down.")
    // A workout at a steady effort: no "seated".
    let steady = RideVisualState.make(.init(mode: .workout, phase: .riding, power: 200, cadence: 90, ftp: 250,
                                            step: .init(index: 0, count: 3, startWatts: 200, endWatts: 200, seconds: 300, remaining: 100)))
    #expect(steady.posture != .standing && CoachingText.line(for: steady, phase: .riding) == "Keep a steady, comfortable cadence.")
    // The same workout in a sprint: the avatar stands and the text says so.
    let sprint = RideVisualState.make(.init(mode: .freeERG, phase: .riding, power: 700, cadence: 110, ftp: 250, target: 200,
                                            sprintPower: 700, sprintPeak: 700))
    #expect(sprint.posture == .standing && CoachingText.line(for: sprint, phase: .riding) == "Sprint — out of the saddle is fine.")
}

@Test func chaindanceNamesTheVisualEverywhere() {
    #expect(RideVisualBranding.name == "Chaindance")
    #expect(RideVisualPlacement.allCases.map(\.title) == ["Off", "Strip", "Large"])
}
