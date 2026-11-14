import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

@Test func livePowerUsesTimeWeightsZerosPartialWindowsAndFreshness() throws {
    let samples = [RideSample(time: 0, power: 300), RideSample(time: 1, power: 0), RideSample(time: 3, power: 100)]
    #expect(try #require(LivePower.average(samples: samples, at: 3, window: 3)) == 100)
    #expect(LivePower.average(samples: samples, at: 6, window: 3) == nil)
    #expect(LivePower.average(samples: samples, at: 3, window: 1) == nil)
    #expect(LivePower.average(samples: [RideSample(time: 0, power: 200), RideSample(time: 1, power: 300)], at: 1, window: 60) == 200)
    #expect(LivePower.average(samples: samples, at: 3, window: 3, pauses: [.init(stop: 1, resume: 3)]) == 300)
    for window in LivePower.windows {
        let constant = (0...70).map { RideSample(time: Double($0), power: 150) }
        #expect(LivePower.average(samples: constant, at: 70, window: window) == 150)
    }
}

@Test func dashboardGeometryAndSlotsRemainStable() {
    let full = DashboardMetrics.make(width: 1470, height: 920)
    #expect(full.hero == 220 && full.reading == 185 && full.caption == 30)
    for size in [(900.0, 600.0), (1470, 920), (1920, 1080)] {
        for compact in [false, true] {
            let m = DashboardMetrics.make(width: size.0, height: size.1, compact: compact)
            #expect(m.hero >= 96 && m.reading >= 64 && m.caption >= 15)
            #expect(m.headerHeight + m.heroHeight + m.readingHeight + m.stripHeight + 92 * m.scale <= size.1 + 0.001)
            #expect(5 * m.hero * 0.6 < (size.0 - 2 * m.padding - m.gap) / 2) // widest system-font clock, 00:00
        }
    }
    #expect(DashboardSlots.make(kind: .workout, phase: .riding).e == .next)
    #expect(DashboardSlots.make(kind: .freeRide, phase: .riding).b == .rideTime)
    #expect(DashboardSlots.make(kind: .ftpTest, phase: .warmup).e == .firstStep)
    #expect(DashboardSlots.make(kind: .ftpTest, phase: .ramp).focus)
    #expect(DashboardSlots.make(kind: .ftpTest, phase: .cooldown).e == .bestMinute)
}

@Test func cuesCrossEachThresholdOnceAndDoNotFireOnNewSteps() {
    #expect(StepCue.due(remaining: 2.9, previous: 3.1) == [3])
    #expect(StepCue.due(remaining: 2.8, previous: 2.9).isEmpty)
    #expect(StepCue.due(remaining: 0.9, previous: 3.1) == [3, 2, 1])
    #expect(StepCue.due(remaining: 300, previous: 1).isEmpty)
    #expect(StepCue.due(remaining: 2, previous: nil).isEmpty)
}

@Test func rampCadenceReadsTheExistingEngineTimer() throws {
    var engine = RideEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    for time in 0...14 {
        engine.receive(.init(time: Double(time), power: 200, cadence: time < 12 ? 80 : 40))
        engine.tick(at: Double(time))
    }
    #expect(engine.lowCadenceSince == 12)
    #expect(RampCadenceState.make(cadence: 40, at: 14, lowCadenceSince: engine.lowCadenceSince) == .ending(3))
    #expect(RampCadenceState.make(cadence: 55, at: 14, lowCadenceSince: nil) == .speedUp)
    #expect(RampCadenceState.make(cadence: nil, at: 14, lowCadenceSince: nil) == .noSignal)
    engine.receive(.init(time: 15, power: 200, cadence: 80)); engine.tick(at: 15)
    #expect(engine.lowCadenceSince == nil && engine.phase == .ramp)
}

@Test func freeRideModeSwitchPreservesClockAndRecordedTargets() throws {
    var engine = RideEngine(configuration: try SessionConfiguration(), training: try .freeRide(watts: 180))
    for second in 0...10 { engine.receive(.init(time: Double(second), power: 180, cadence: 90)); engine.tick(at: Double(second)) }
    let changedToResistance = engine.switchFreeRide(resistance: 40, watts: 180, at: 10)
    #expect(changedToResistance)
    #expect(engine.targetResistance == 40 && engine.targetPower == nil && engine.trainingElapsed == 10)
    #expect(TargetSeries.value(engine.session, at: 9) == 180)
    #expect(TargetSeries.value(engine.session, at: 10) == nil)
    let didPause = engine.pause(at: 10)
    #expect(didPause)
    let changedToERG = engine.switchFreeRide(resistance: nil, watts: 205, at: 11)
    #expect(changedToERG)
    #expect(engine.targetPower == nil && engine.resumeTarget == 205)
    engine.receive(.init(time: 11, power: 200, cadence: 90))
    let didResume = engine.resume(at: 11)
    #expect(didResume)
    #expect(engine.targetPower == 205 && engine.trainingElapsed == 10)
    #expect(TargetSeries.value(engine.session, at: 11) == 205)
    var workout = RideEngine(configuration: try SessionConfiguration(), training: try TrainingPlan(kind: .workout, name: "Set", steps: [.init("Work", seconds: 60, watts: 200)]))
    let rejectedWorkout = !workout.switchFreeRide(resistance: 40, watts: 180, at: 0)
    #expect(rejectedWorkout)
}

@Test func finishedStepHeartRatesExcludePausesAndHandleSkipsAndMissingData() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Set", steps: [.init("A", seconds: 10, watts: 100), .init("B", seconds: 10, watts: 100), .init("C", seconds: 10, watts: 100)])
    var engine = RideEngine(configuration: try SessionConfiguration(), training: plan)
    for second in 0...25 {
        engine.receive(.init(time: Double(second), power: 100, cadence: 80, heartRate: second < 10 ? 120 : second < 15 ? 200 : nil))
        engine.tick(at: Double(second))
        if second == 10 { _ = engine.pause(at: 10) }
        if second == 15 { _ = engine.resume(at: 15) }
    }
    #expect(StepHeartRate.averages(session: engine.session) == [120, nil, nil])
}

@Test @MainActor func previewFreeRideModeChangeUsesTheEngine() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    await model.start(training: try .freeRide(watts: 180))
    model.advanceMock(seconds: 5)
    let time = model.engine?.trainingElapsed
    model.resistanceLevel = 40
    model.switchFreeRideMode(resistance: true)
    #expect(model.engine?.resumeResistance == 40 && model.engine?.trainingElapsed == time)
    model.switchFreeRideMode(resistance: false)
    #expect(model.engine?.resumeResistance == nil && model.engine?.freeRideERGTarget == 180)
    model.switchFreeRideMode(resistance: true)
    #expect(model.engine?.resumeResistance == 40)
    model.stop()
}

@Test func rideTileTextContrast() {
    let ground = ActionRGB(red: 13/255, green: 12/255, blue: 21/255)
    let tile = ActionRGB(red: 25/255, green: 24/255, blue: 39/255)
    let raised = ActionRGB(red: 35/255, green: 34/255, blue: 53/255)
    let texts = [ActionRGB(red: 243/255, green: 244/255, blue: 248/255), ActionRGB(red: 169/255, green: 169/255, blue: 191/255), ActionRGB(red: 197/255, green: 247/255, blue: 77/255), ActionRGB(red: 1, green: 92/255, blue: 92/255), ActionRGB(red: 95/255, green: 217/255, blue: 232/255)]
    for background in [ground, tile, raised] { for text in texts { #expect(text.contrast(with: background) >= 4.5) } }
    #expect(ground.contrast(with: ActionRGB(red: 252/255, green: 184/255, blue: 82/255)) >= 4.5)
}

#if os(macOS)
import AppKit
import CoreText
@Test @MainActor func dashboardFontsFitTheAvailableTiles() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Fonts/Tektur.ttf")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: "Tektur-Regular", kCTFontVariationAttribute: [2003072104: 85, 2003265652: 900]] as CFDictionary)
    for dimensions in [(1470.0, 920.0), (900.0, 600.0)] {
        let m = DashboardMetrics.make(width: dimensions.0, height: dimensions.1)
        let tektur = CTFontCreateWithFontDescriptor(descriptor, m.hero, nil)
        #expect((CTFontCopyFamilyName(tektur) as String) == "Tektur")
        #expect(abs(CTFontGetCapHeight(tektur) - m.hero * 0.7) < 0.1)
        for size in [76.0, 185, 220, 300] {
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            #expect(abs(CTFontGetCapHeight(font) - size * 0.7) < 0.1)
        }
        let system = NSFont.systemFont(ofSize: m.hero, weight: .black)
        let rounded = NSFont(descriptor: system.fontDescriptor.withDesign(.rounded)!, size: m.hero)!
        for font in [tektur, system as CTFont, rounded as CTFont] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "88:88", attributes: [.font: font]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let available = (dimensions.0 - 2 * m.padding - m.gap) / 2 - 64 * m.scale
            #expect(width * 0.55 <= available)
        }
    }
}
#endif

@Test func rampSegmentsFillElapsedAndResetAtTheStepBoundary() {
    #expect(StepSegments.filled(remaining: 12, stepSeconds: 12) == 0)
    #expect(StepSegments.filled(remaining: 8, stepSeconds: 12) == 4)
    #expect(StepSegments.filled(remaining: 1, stepSeconds: 12) == 11)
    #expect(StepSegments.filled(remaining: 0, stepSeconds: 12) == 12)
    #expect(StepSegments.filled(remaining: 12, stepSeconds: 12) == 0)
    #expect(StepSegments.filled(remaining: 8, stepSeconds: 0) == 0)
}

@Test func recoveryTextIsNeutralAndReadableOnItsTintedTile() {
    let text = ZonePalette.dashboardText(for: .recovery)
    #expect(text.red == 180.0/255 && text.green == 184.0/255 && text.blue == 200.0/255)
    for zone in [IntensityZone.recovery, .endurance, .tempo, .sweetSpot, .threshold, .vo2max] {
        let tint = ZonePalette.pair(for: zone).dark
        let background = ActionRGB(red: 25.0/255 * 0.86 + tint.red * 0.14,
                                   green: 24.0/255 * 0.86 + tint.green * 0.14,
                                   blue: 39.0/255 * 0.86 + tint.blue * 0.14)
        #expect(ZonePalette.dashboardText(for: zone).contrast(with: background) >= 4.5)
    }
}

@Test @MainActor func reviewedDashboardFixturesKeepTheirSampleReadings() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.dashFtpWarmup, to: model)
    #expect(model.engine?.lastCadence?.rpm == 88)
    for scenario in [PreviewScenario.dashFtpRamp, .dashFtpLowCadence, .dashFtpEnding, .dashFtpCooldown] {
        try await PreviewScenarios.apply(scenario, to: model)
        #expect(model.previewDashboardReadings["bestMinute"] == "272")
    }
    try await PreviewScenarios.apply(.dashFreeRide, to: model)
    let cadence = try #require(model.engine.map { RideSummary.make($0.session).averageCadence } ?? nil)
    #expect(Int(cadence.rounded()) == 89)
    #expect(model.previewDashboardReadings["Distance"] == "12.4")
    try await PreviewScenarios.apply(.dashWorkoutRecoveryNext, to: model)
    let engine = try #require(model.engine)
    let current = try #require(engine.currentStep)
    let plan = try #require(engine.session.training)
    #expect(current.step.name == "Recovery 2 of 3" && current.remaining == 190)
    #expect(engine.targetPower == 125 && engine.lastPower?.watts == 127)
    #expect(engine.lastCadence?.rpm == 86 && model.freshHeartRate == 128)
    #expect(model.elapsed == 2750 && model.mockPaused && engine.canSkipStep)
    #expect(plan.steps[current.index + 1].watts == 225 && plan.steps[current.index + 1].seconds == 720)
    #expect(StepHeartRate.averages(session: engine.session).prefix(4).map { $0.map { Int($0.rounded()) } } == [121, 141, 133, 143])
    model.stop()
}
