import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

private func pauseConfig() throws -> SessionConfiguration {
    try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .trainer, cadenceSource: .trainer)
}
private func pausePlan() throws -> TrainingPlan {
    try TrainingPlan(kind: .workout, name: "Pause boundaries", steps: [.init("Easy", seconds: 3, watts: 100), .init("Effort", seconds: 3, watts: 150)])
}
@Test func pauseFreezesStepTimeAndResumeKeepsTheRemainingStep() throws {
    var e = RideEngine(configuration: try pauseConfig(), training: try pausePlan())
    for t in 0...2 { e.receive(RideSample(time: Double(t), power: 100, cadence: 90)); e.tick(at: Double(t)) }
    let transition1 = e.pause(at: 2); #expect(transition1); #expect(e.phase == .paused); #expect(e.targetPower == nil)
    e.tick(at: 100) // A released trainer may remain paused without live measurements.
    #expect(e.phase == .paused); #expect(e.trainingElapsed == 2); #expect(e.currentStep?.remaining == 1)
    let transition2 = e.resume(at: 100); #expect(!transition2)
    e.receive(RideSample(time: 100, power: 100, cadence: 90))
    let transition3 = e.resume(at: 100); #expect(transition3); #expect(e.targetPower == 100)
    for t in 101...104 {
        e.receive(RideSample(time: Double(t), power: 100, cadence: 90)); e.tick(at: Double(t))
        if t == 101 { #expect(e.targetPower == 150) }
    }
    #expect(e.phase == .completed); #expect(e.trainingElapsed == 6)
    #expect(e.session.endedAtOffset == 104)
    #expect(e.session.result == nil)
}
@Test func resumingKeepsTheRecordingAndPausedReadingsStayInIt() throws {
    var e = RideEngine(configuration: try pauseConfig(), training: try .freeRide(watts: 100))
    e.receive(RideSample(time: 0, power: 100, cadence: 90)); e.tick(at: 0)
    let transition4 = e.pause(at: 0.5); #expect(transition4)
    e.receive(RideSample(time: 1, power: 100, cadence: 90))
    let transition5 = e.resume(at: 1.5); #expect(transition5)
    e.receive(RideSample(time: 2, power: 100, cadence: 90)); e.tick(at: 2)
    #expect(e.session.samples.count == 3 && e.session.eligibleMilliseconds == nil)
    let transition6 = e.pause(at: 2); #expect(transition6); e.receive(RideSample(time: 3, power: 0, cadence: 0))
    let transition7 = e.resume(at: 3); #expect(!transition7); #expect(e.targetPower == nil)
}
@Test func pausedFreeERGAdjustsOnlyTheResumeTargetAndStopCannotBeResumed() throws {
    var e = RideEngine(configuration: try pauseConfig(), training: try .freeRide(watts: 100))
    e.receive(RideSample(time: 0, power: 100, cadence: 90)); e.tick(at: 0)
    let transition8 = e.pause(at: 1); #expect(transition8); e.adjustFreeRide(to: 180, at: 1)
    #expect(e.targetPower == nil); #expect(e.resumeTarget == 180)
    e.endActivity(at: 2); let transition9 = e.resume(at: 2); #expect(!transition9); #expect(!e.phase.isActive)
    var ramp = RideEngine(configuration: try pauseConfig())
    ramp.receive(RideSample(time: 0, power: 100, cadence: 90)); ramp.tick(at: 0)
    let transition10 = ramp.pause(at: 1); #expect(!transition10); #expect(ramp.phase == .ramp)
}
@Test func pauseBeforePedalingAndRepeatedPausesDoNotConsumeWorkoutTime() throws {
    var e = RideEngine(configuration: try pauseConfig(), training: try pausePlan())
    let transition11 = e.pause(at: 10); #expect(transition11); e.tick(at: 20)
    e.receive(RideSample(time: 20, power: 100, cadence: 90)); let transition12 = e.resume(at: 20); #expect(transition12)
    #expect(e.phase == .waiting); #expect(e.trainingElapsed == 0)
    e.tick(at: 20)
    for t in 21...22 { e.receive(RideSample(time: Double(t), power: 100, cadence: 90)); e.tick(at: Double(t)) }
    let transition13 = e.pause(at: 22); #expect(transition13); e.receive(RideSample(time: 24, power: 100, cadence: 90)); let transition14 = e.resume(at: 24); #expect(transition14)
    let transition15 = e.pause(at: 24.5); #expect(transition15); e.receive(RideSample(time: 30, power: 100, cadence: 90)); let transition16 = e.resume(at: 30); #expect(transition16)
    #expect(e.trainingElapsed == 2.5); #expect(e.currentStep?.remaining == 0.5)
    e.receive(RideSample(time: 30.5, power: 100, cadence: 90)); e.tick(at: 30.5)
    #expect(e.targetPower == 150)
}
@Test @MainActor func nativePauseWorkflowAndCrashRecoveryDoNotAutoResume() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    await model.start(training: try pausePlan()); model.advanceMock(seconds: 2)
    model.pauseTraining(); #expect(model.engine?.phase == .paused)
    let time = model.engine?.trainingElapsed
    model.advanceMock(seconds: 60); #expect(model.engine?.trainingElapsed == time)
    #expect(model.isBusy); #expect(model.engine?.session.eligibleMilliseconds == nil)
    model.resumeTraining(); #expect(model.engine?.phase == .riding)
    model.advanceMock(seconds: 5); #expect(!model.isBusy)

    var e = RideEngine(configuration: try pauseConfig(), training: try pausePlan())
    for t in 0...2 { e.receive(RideSample(time: Double(t), power: 100, cadence: 90)); e.tick(at: Double(t)) }
    e.pause(at: 2); try store.save(e.session)
    try store.recoverInterruptedSessions(); try store.recoverInterruptedSessions()
    let recovered = try #require(store.sessions().first { $0.id == e.session.id })
    #expect(recovered.outcome == .interrupted); #expect(recovered.endedAtOffset != nil)
    #expect(try store.profiles().first?.cycleProgress == nil)
}
