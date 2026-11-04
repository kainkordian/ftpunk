import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

/// Chaindance follows real ramp boundaries (the exhaustion, the cool-down, the end); it never predicts them.
private func visual(_ engine: RampEngine, at time: Double, cooldown: Double) -> RideVisualState {
    let phaseSeconds = max(0, time - engine.phaseStartedAt)
    let rampSeconds: Double
    if engine.phase == .ramp { rampSeconds = phaseSeconds }
    else if let start = engine.session.rampStart, let end = engine.session.rampEnd { rampSeconds = max(0, end - start) }
    else { rampSeconds = 0 }
    return .make(.init(mode: .ftpTest, phase: engine.phase, power: 250, cadence: 90, ftp: 250,
                       ramp: .init(phaseSeconds: phaseSeconds, warmupSeconds: 0, cooldownSeconds: cooldown, stepSeconds: 12,
                                   rampSeconds: rampSeconds, bestMinuteWatts: engine.session.result?.bestMinutePower)))
}

@Test func exhaustionReachesTheRooftopThenGlidesDownWithNoErgTarget() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0, cooldownSeconds: 10))
    for second in 0...75 {
        engine.receive(RideSample(time: Double(second), power: 300, cadence: second < 70 ? 90 : 30))
        engine.tick(at: Double(second))
        if engine.phase == .ramp { #expect(visual(engine, at: Double(second), cooldown: 10).world == .skyway) }
    }
    #expect(engine.session.outcome == .exhaustion)
    #expect(engine.isFreewheelCooldown)
    #expect(engine.targetPower == nil)
    #expect(engine.session.cooldownStart == 75)
    let summit = visual(engine, at: 75, cooldown: 10)
    #expect(summit.world == .rooftop && summit.sign?.kind == .finish && summit.sign?.text.hasPrefix("LVL ") == true)
    let scoredResult = engine.session.result
    for second in 76...85 {
        engine.receive(RideSample(time: Double(second), power: 0, cadence: 60))
        engine.tick(at: Double(second))
        if (78...84).contains(second) { #expect(visual(engine, at: Double(second), cooldown: 10).world == .descent) }
    }
    #expect(engine.phase == .completed)
    #expect(visual(engine, at: 85, cooldown: 10).world == .rooftop) // the ride ended after a scored ramp
    #expect(engine.session.result == scoredResult)
}

@Test func aSkippedCooldownEndsOnTheRooftopAndAnInterruptedRampDoesNot() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0, cooldownSeconds: 0))
    engine.receive(RideSample(time: 0, power: 200, cadence: 90)); engine.tick(at: 0)
    engine.finishRamp(at: 1)
    #expect(engine.phase == .completed)
    #expect(visual(engine, at: 30, cooldown: 0).world == .rooftop)
    var interrupted = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    interrupted.receive(RideSample(time: 0, power: 200, cadence: 90)); interrupted.tick(at: 0)
    interrupted.interrupt(at: 1, reason: "Lost power")
    let stopped = visual(interrupted, at: 1, cooldown: 180)
    #expect(stopped.world == .boulevard && stopped.sign == nil)
}

@Test @MainActor func mockExhaustionKeepsSelectedCooldownAndSavesAfterRecovery() async throws {
    let store = try LocalStore(inMemory: true)
    let model = try AppModel(store: store, preview: true)
    model.quickDebugTest = false; model.warmupMinutes = 0; model.cooldownMinutes = 1
    await model.start(); model.mockPaused = true
    while model.engine?.phase != .cooldown && model.isActive { model.advanceMock(seconds: 0.5) }
    let engine = try #require(model.engine)
    #expect(engine.isFreewheelCooldown)
    #expect(engine.targetPower == nil)
    #expect(model.history.isEmpty)
    // Chaindance reads this live ride without touching it: the rooftop at the start of the cool-down.
    let state = RideVisualState.make(RideVisualInput(model: model, engine: engine))
    #expect(state.world == .rooftop && state.sign?.kind == .finish)
    model.advanceMock(seconds: 60)
    #expect(model.engine?.phase == .completed)
    #expect(model.history.count == 1)
    #expect(try store.sessions().first?.result == engine.session.result)
}

@Test @MainActor func readingARideForThePixelRideNeverChangesIt() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    await model.start(); model.mockPaused = true
    model.skipMockWarmup(); model.advanceMock(seconds: 40)
    let before = try #require(model.engine)
    var motion = RideVisualMotion()
    for _ in 0..<120 {
        let state = RideVisualState.make(RideVisualInput(model: model, engine: try #require(model.engine)))
        motion.advance(by: 0.1, state: state)
        _ = RideVisualRaster.image(RideVisualScene(state: state, motion: motion))
    }
    let after = try #require(model.engine)
    #expect(after.targetPower == before.targetPower && after.phase == before.phase && after.session.samples.count == before.session.samples.count)
    model.stop()
}
