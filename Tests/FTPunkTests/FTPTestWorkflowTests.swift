import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

@Test @MainActor func newTestsAlwaysUseTheConservativeFactor() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.mockScenario = .steadyRider; model.warmupMinutes = 0; model.cooldownMinutes = 0
    await model.start(); model.mockPaused = true
    model.advanceMock(seconds: 0.5); model.advanceMock(seconds: 70)
    model.finishRamp()
    let session = try #require(model.engine?.session)
    #expect(session.configuration.ftpFactor == 0.72)
    #expect(session.result?.factor == 0.72)
    #expect(AppModel.ftpFactor == 0.72)
}

@Test func legacyRecordingsWithTheOlderFactorStillLoadAndKeepTheirNumbers() throws {
    var configuration = try SessionConfiguration(ftpFactor: 0.75)
    #expect(configuration.ftpFactor == 0.75)
    var session = TestSession(configuration: configuration, isDemo: false)
    session.outcome = .exhaustion; session.endedAtOffset = 900; session.rampStart = 100; session.rampEnd = 800
    session.samples = [RideSample(time: 0, power: 100, cadence: 90)]
    session.result = FTPResult(bestMinutePower: 300, windowStart: 700, windowEnd: 760, factor: 0.75)
    #expect(session.result?.estimatedFTP == 225)
    let archive = PortableArchive(profiles: [RiderProfile()], sessions: [session])
    let restored = try PortableArchive.decode(archive.encoded())
    #expect(restored.activities[0].session.configuration.ftpFactor == 0.75)
    #expect(restored.activities[0].session.result?.factor == 0.75)
    #expect(restored.activities[0].session.result?.estimatedFTP == 225)
    // The reported range is unchanged by the factor.
    #expect(session.result?.lowerFTP == 216 && session.result?.upperFTP == 231)
    // Other factors stay invalid.
    #expect(throws: (any Error).self) { configuration = try SessionConfiguration(ftpFactor: 0.8) }
}

@Test func theAutomaticFinishRuleIsUntouchedByTheCadenceWarning() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    // 52 rpm triggers the amber warning at 60 rpm but must not finish the ramp.
    for second in 0...60 {
        engine.receive(RideSample(time: Double(second), power: 200, cadence: second < 20 ? 90 : 52)); engine.tick(at: Double(second))
        if second >= 25 { #expect(CadenceGuard.state(cadence: 52, phase: engine.phase) == .low) }
    }
    #expect(engine.phase == .ramp)
    // Below 45 rpm for five seconds still ends the ramp as exhaustion.
    for second in 61...70 { engine.receive(RideSample(time: Double(second), power: 200, cadence: 40)); engine.tick(at: Double(second)) }
    #expect(engine.session.outcome == .exhaustion)
}

@Test @MainActor func holdingIsOnlyAUIGestureAndFinishRampStillWorksOnce() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.mockScenario = .steadyRider; model.warmupMinutes = 0; model.cooldownMinutes = 3; model.quickDebugTest = false
    await model.start(); model.mockPaused = true
    model.advanceMock(seconds: 0.5); model.advanceMock(seconds: 70)
    #expect(model.engine?.phase == .ramp)
    model.finishRamp()
    #expect(model.engine?.phase == .cooldown && model.engine?.session.outcome == .finishedEarly)
    model.finishRamp() // a repeated confirmation after the ramp is a no-op
    #expect(model.engine?.phase == .cooldown)
    model.stop() // Stop is immediate, with no confirmation step.
    #expect(!model.isActive && model.history.count == 1)
}

@Test @MainActor func recommendedProtocolFollowsWeightUntilTheRiderChoosesOne() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.weight = "55"; model.applyRecommendedProtocol()
    #expect(model.preset == .gentle && model.recommendedProtocol.reason == "55 kg → 15 W/min")
    model.weight = "80"; model.applyRecommendedProtocol()
    #expect(model.preset == .standard)
    model.choosePreset(.zwift); model.weight = "55"; model.applyRecommendedProtocol()
    #expect(model.preset == .zwift && model.presetChosen)
    #expect(model.addRider(name: "Guest")) // a new rider starts from the recommendation again
    #expect(!model.presetChosen)
}

@Test @MainActor func adoptingAResultRetargetsTheLibraryAndIsDetectable() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    let alex = PreviewFixtures.rider()
    try await PreviewScenarios.apply(.resultNewFTP, to: model)
    let session = try #require(model.engine?.session)
    let result = try #require(session.result)
    #expect(result.factor == 0.72)
    let estimate = result.estimatedFTP
    #expect(estimate < 250) // the preview rider tests lower than their current FTP
    #expect(ResultDelta(newFTP: estimate, currentFTP: model.profile.currentFTP?.watts).watts < 0)
    #expect(!FTPAdoption.isAdopted(rider: model.profile, result: result, sessionStart: session.startedAt))
    let before = try WorkoutLibrary.classics(ftp: try #require(model.libraryFTP))
    model.adopt(session)
    #expect(FTPAdoption.isAdopted(rider: model.riders.first { $0.id == alex.id }, result: result, sessionStart: session.startedAt))
    #expect(model.libraryFTP == estimate)
    let after = try WorkoutLibrary.classics(ftp: try #require(model.libraryFTP))
    #expect(before[0].plan.steps[1].watts > after[0].plan.steps[1].watts)
    #expect(RetargetExample.make(oldFTP: 250, newFTP: estimate)?.oldWatts == 225)
}

@Test @MainActor func debugResultsCannotBeAdopted() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.rideRamp, to: model)
    model.advanceMock(seconds: 1000)
    let session = try #require(model.engine?.session)
    #expect(session.isDemo && session.result != nil)
    let before = model.profile.ftpHistory.count
    model.adopt(session)
    #expect(model.profile.ftpHistory.count == before)
}
