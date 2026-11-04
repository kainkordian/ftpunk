import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

private func trainingConfig() throws -> SessionConfiguration {
    try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .trainer, cadenceSource: .trainer)
}
private func shortPlan() throws -> TrainingPlan {
    try TrainingPlan(kind: .workout, name: "Boundary check", ftpWatts: 200, steps: [.init("Warm-up", seconds: 3, watts: 100), .init("Effort", seconds: 2, watts: 150), .init("Cooldown", seconds: 1, watts: 50)])
}
@Test func trainingStartsOnMovementFollowsExactBoundariesAndNeverEstimatesFTP() throws {
    var e = RideEngine(configuration: try trainingConfig(), training: try shortPlan())
    e.tick(at: 10); #expect(e.phase == .waiting)
    for t in 10...16 {
        e.receive(RideSample(time: Double(t), power: 100, cadence: 90)); e.tick(at: Double(t))
        if t < 13 { #expect(e.targetPower == 100) }
        else if t < 15 { #expect(e.targetPower == 150) }
        else if t == 15 { #expect(e.targetPower == 50) }
    }
    #expect(e.phase == .completed); #expect(e.targetPower == nil)
    #expect(e.session.outcome == .completed); #expect(e.session.result == nil)
    #expect(e.session.adventureEnabled == nil && e.session.eligibleMilliseconds == nil) // the removed story never accrues
}
@Test func freeERGAdjustmentsAreRecordedAndStopEndsControl() throws {
    var e = RideEngine(configuration: try trainingConfig(), training: try .freeRide(watts: 100))
    e.adjustFreeRide(to: 110, at: 0)
    e.receive(RideSample(time: 0, power: 100, cadence: 90)); e.tick(at: 0)
    #expect(e.targetPower == 110)
    e.adjustFreeRide(to: 120, at: 0.5); #expect(e.targetPower == 120)
    e.adjustFreeRide(to: -10, at: 0.5); #expect(e.targetPower == 120)
    e.endActivity(at: 1); e.adjustFreeRide(to: 400, at: 2)
    #expect(e.targetPower == nil); #expect(e.session.result == nil)
    #expect(e.session.events.contains { $0.message == "ERG target changed to 120 W" })
}
@Test func workoutLossAndClockJumpsInterruptWithoutAdvancingIntoAnotherTarget() throws {
    for late in [2.01, 10.0] {
        var e = RideEngine(configuration: try trainingConfig(), training: try shortPlan())
        e.receive(RideSample(time: 0, power: 100, cadence: 90)); e.tick(at: 0); e.tick(at: late)
        #expect(e.phase == .interrupted); #expect(e.targetPower == nil)
    }
}
@Test func starterWorkoutsResolveFTPOnceAndValidateInvalidPlans() throws {
    let plans = try TrainingPlan.starters(ftp: 200)
    #expect(plans.map(\.duration) == [1200, 1800, 1800])
    #expect(plans[1].steps[1].watts == 130)
    #expect(throws: (any Error).self) { try TrainingPlan.freeRide(watts: 0) }
    #expect(throws: (any Error).self) { try TrainingPlan.starters(ftp: .infinity) }
    #expect(throws: (any Error).self) { try TrainingPlan(kind: .workout, name: "Invalid", steps: [.init("Bad", seconds: -1, watts: 100)]) }
}
@Test @MainActor func nativeWorkoutWorkflowSavesWithoutChangingFTP() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    await model.start(training: try shortPlan())
    #expect(model.isActive); #expect(model.cockpitPresented)
    model.advanceMock(seconds: 8)
    #expect(!model.isBusy)
    let saved = try #require(store.sessions().first)
    #expect(saved.training?.kind == .workout); #expect(saved.result == nil)
    #expect(saved.outcome == .completed); #expect(saved.eligibleMilliseconds == nil)
    #expect(try store.profiles().first?.cycleProgress == nil)
}
