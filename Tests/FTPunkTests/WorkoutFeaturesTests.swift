import Foundation
import CoreData
import Testing
import FTPunkDomain
import FTPunkDevices
import FTPunkIntegrations
@testable import FTPunkStorage
@testable import FTPunkApp

private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("ftpunk_web/tests/fixtures/\(name).json"))
}
private func featureConfig() throws -> SessionConfiguration {
    try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID, powerSource: .trainer, cadenceSource: .trainer)
}
@Test func importsExpandRepeatsAndInterpolateRampsFromSharedFixtures() throws {
    let plan = try WorkoutImport.parse(fixture("workout-ramps"))
    #expect(plan.version == 2); #expect(plan.steps.count == 6); #expect(plan.duration == 40)
    #expect(plan.target(at: 0) == 100); #expect(plan.target(at: 5) == 150)
    #expect(plan.target(at: 10) == 180); #expect(plan.target(at: 35) == 75)
    #expect(plan.target(at: 40) == nil)
    let resolved = try WorkoutImport.parse(fixture("workout-intervals"), ftp: 300)
    #expect(resolved.steps.count == 5); #expect(resolved.steps[0].endWatts == 200)
    #expect(resolved.steps[1].watts == 180) // Already resolved; never scale twice.
}
@Test func importsRejectUnboundedRepeatsMalformedTargetsAndUnsupportedSteps() throws {
    for text in [
        #"{"format":"ftpunk-workout","version":1,"steps":[{"repeat":101,"steps":[{"seconds":1,"watts":100}]}]}"#,
        #"{"format":"ftpunk-workout","version":1,"steps":[{"repeat":100,"steps":[{"repeat":100,"steps":[{"seconds":1,"watts":100}]}]}]}"#,
        #"{"format":"ftpunk-workout","version":1,"steps":[{"seconds":1,"watts":true}]}"#,
        #"{"format":"ftpunk-workout","version":1,"ftpWatts":"200","steps":[{"seconds":1,"watts":100}]}"#,
        #"{"format":"ftpunk-workout","version":1,"steps":[{"seconds":1,"watts":100,"endWatts":null}]}"#,
        #"{"type":"Ride","category":"WORKOUT","workout_doc":{"steps":[{"duration":10,"freeride":true,"power":{"units":"w","value":100}}]}}"#,
        #"{"type":"Ride","category":"WORKOUT","workout_doc":{"steps":[{"duration":10,"power":{"units":"%hr","value":80}}]}}"#
    ] { #expect(throws: (any Error).self) { try WorkoutImport.parse(Data(text.utf8)) } }
}
@Test func intensityUsesOriginalTargetsAndPausedRampClock() throws {
    let plan = try WorkoutImport.parse(fixture("workout-ramps"))
    var engine = RideEngine(configuration: try featureConfig(), training: plan)
    for t in 0...5 { engine.receive(.init(time: Double(t), power: 100, cadence: 90)); engine.tick(at: Double(t)) }
    let changed1 = engine.setIntensity(105, at: 5); #expect(changed1); #expect(engine.targetPower == 158)
    let changed2 = engine.setIntensity(110, at: 5); #expect(changed2); #expect(engine.targetPower == 165)
    let changed3 = engine.pause(at: 5); #expect(changed3); let changed4 = engine.setIntensity(95, at: 5); #expect(changed4)
    #expect(engine.targetPower == nil); #expect(engine.resumeTarget == 143)
    let changed5 = !engine.setIntensity(150, at: 5, maximum: 250); #expect(changed5); #expect(engine.intensity == 95)
    let changed6 = !engine.setIntensity(45, at: 5); #expect(changed6); #expect(engine.session.training == plan)
    engine.receive(.init(time: 100, power: 100, cadence: 90)); engine.tick(at: 100)
    let changed7 = engine.resume(at: 100); #expect(changed7); #expect(engine.targetPower == 143)
    #expect(engine.trainingElapsed == 5)
}
@Test func resistanceRequiresExactFeatureAndRangeAndUsesSeparateOpcode() throws {
    let f = try FitnessMachineFeatures.decode(Data([0,0,0,0,4,0,0,0]))
    #expect(f.supportsResistance); #expect(!f.supportsTargetPower)
    let range = try SupportedResistanceRange.decode(Data([0,0,0xE8,3,10,0]))
    #expect(range.maximum == 1000); #expect(range.quantized(107) == 110)
    #expect(try TrainerCommand.targetResistance(105).encoded() == Data([4,105,0]))
    #expect(throws: (any Error).self) { try SupportedResistanceRange.decode(Data([0,100,1])) }
    #expect(throws: (any Error).self) { try SupportedResistanceRange.decode(Data([0,0,100,0,0,0])) }
    #expect(throws: (any Error).self) { try TrainerCommand.targetResistance(-1).encoded() }
    #expect(try SupportedResistanceRange(minimum: 0, maximum: 103, increment: 10).quantized(103) == 100)
}
@Test func resistanceEngineNeverProducesERGTargetsIncludingPauseAndResume() throws {
    var e = RideEngine(configuration: try featureConfig(), training: try .resistanceRide(level: 100))
    e.receive(.init(time: 0, power: 120, cadence: 90)); e.tick(at: 0)
    #expect(e.targetPower == nil); #expect(e.targetResistance == 100)
    e.adjustFreeRide(to: 200, at: 0); #expect(e.targetPower == nil)
    let changed8 = e.pause(at: 0); #expect(changed8); #expect(e.targetResistance == nil)
    e.adjustResistance(to: 110, at: 0); #expect(e.resumeResistance == 110)
    e.receive(.init(time: 20, power: 120, cadence: 90)); e.tick(at: 20)
    let changed9 = e.resume(at: 20); #expect(changed9); #expect(e.targetResistance == 110); #expect(e.targetPower == nil)
    e.endActivity(at: 20); #expect(e.targetResistance == nil); #expect(e.session.result == nil)
}
@Test func intervalsDownloadChecksPermissionAndParsesSupportedEventsOnly() throws {
    let denied = IntervalsConnection(athleteID: "123", athleteName: "Test", accessToken: "test-token")
    #expect(throws: (any Error).self) { try IntervalsClient.workoutRequest(connection: denied, oldest: "2026-10-31", newest: "2026-11-14") }
    let allowed = IntervalsConnection(athleteID: "123", athleteName: "Test", accessToken: "test-token", scopes: ["CALENDAR:READ"])
    let request = try IntervalsClient.workoutRequest(connection: allowed, oldest: "2026-10-31", newest: "2026-11-14")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    #expect(request.url?.absoluteString.contains("resolve=true") == true)
    let event = try JSONSerialization.jsonObject(with: fixture("workout-intervals"))
    let data = try JSONSerialization.data(withJSONObject: [event, ["id": 456, "name": "Unsupported", "type": "Run"]])
    let result = try IntervalsClient.decodeWorkouts(data, accountID: "123", riderID: RiderProfile.legacyID, ftp: 200)
    #expect(result.workouts.count == 1); #expect(result.skipped.isEmpty)
    #expect(result.workouts[0].id == "intervals:123:\(RiderProfile.legacyID.uuidString.lowercased()):123")
}
@Test @MainActor func libraryIsAtomicIdempotentPortableAndProtectsUnrelatedRiders() throws {
    let store = try LocalStore(inMemory: true), rider = RiderProfile(), other = RiderProfile(id: UUID(), name: "Other")
    try store.saveProfile(rider); try store.saveProfile(other)
    let plan = try WorkoutImport.parse(fixture("workout-ramps"))
    let workout = CachedWorkout(id: "download:123", riderID: rider.id, source: "Fixture", plan: plan)
    try store.saveWorkouts([workout]); try store.saveWorkouts([workout])
    #expect(try store.workouts().count == 1)
    let archive = try PortableArchive.decode(store.portableArchive().encoded())
    #expect(archive.version == 3); #expect(archive.workouts?[0].plan == plan)
    try store.restore(archive); #expect(try store.workouts().count == 1)
    let collision = CachedWorkout(id: workout.id, riderID: other.id, source: "Other", plan: plan)
    #expect(throws: (any Error).self) { try store.restore(PortableArchive(profiles: [other], sessions: [], workouts: [collision])) }
    #expect(throws: (any Error).self) { try store.saveWorkouts([CachedWorkout(riderID: rider.id, source: "new", plan: plan), collision]) }
    #expect(try store.workouts().count == 1); #expect(try store.workouts()[0].riderID == rider.id)
}
@Test @MainActor func originalSQLiteStoreMigratesWithoutLosingRidersAndCachesSurviveReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("store.sqlite"), rider = RiderProfile()
    let old = NSPersistentStoreCoordinator(managedObjectModel: LocalStore.model(includeWorkouts: false))
    let persistent = try old.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType); context.persistentStoreCoordinator = old
    let row = NSEntityDescription.insertNewObject(forEntityName: "Profile", into: context)
    row.setValue(rider.id.uuidString, forKey: "key"); row.setValue(try JSONEncoder().encode(rider), forKey: "payload")
    try context.save(); context.reset(); try old.remove(persistent)
    var store: LocalStore? = try LocalStore(url: url)
    #expect(try store?.profiles()[0].id == rider.id)
    try store?.saveWorkouts([CachedWorkout(riderID: rider.id, source: "Fixture", plan: WorkoutImport.parse(fixture("workout-ramps")))])
    store = nil; store = try LocalStore(url: url)
    #expect(try store?.workouts().count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains("pre-workouts") })
    store = nil
}

@Test @MainActor func nativeLibraryAndIntensityControlsWorkThroughAppModel() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    model.importWorkout(try fixture("workout-ramps"))
    let saved = try #require(model.workoutLibrary.first)
    await model.start(training: saved.plan); model.advanceMock(seconds: 5)
    model.adjustIntensity(by: 5); #expect(model.engine?.intensity == 105)
    model.pauseTraining(); #expect(model.engine?.phase == .paused)
    model.adjustIntensity(by: -10); #expect(model.engine?.resumeTarget != nil)
    #expect(model.engine?.targetPower == nil); #expect(model.engine?.intensity == 95)
    model.stop(); #expect(!model.isBusy)
    await model.start(training: try .resistanceRide(level: 100)); model.advanceMock(seconds: 1)
    #expect(model.engine?.targetResistance == 100); #expect(model.engine?.targetPower == nil)
    #expect(model.engine?.session.configuration.powerMatchingEnabled == false)
    model.adjustResistance(by: 1); #expect(model.engine?.targetResistance == 110)
    model.stop(); #expect(!model.isBusy)
    #expect(try store.sessions().allSatisfy { $0.result == nil })
}

@Test func sharedV3ArchivePreservesLibraryRampsResistanceAndLegacyStoryFields() throws {
    let archive = try PortableArchive.decode(fixture("portable-v3"))
    #expect(archive.version == 3)
    #expect(archive.activities[0].session.training?.resistance == 100)
    #expect(archive.activities[0].session.adventureStartMilliseconds == 0)
    #expect(archive.workouts?[0].plan.steps[0].endWatts == 200)
    #expect(try PortableArchive.decode(archive.encoded()).workouts?[0].plan == archive.workouts?[0].plan)
}

@Test func skippingAStepMovesTheTrainingClockAndTheRecordedTargetFollows() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Skips", steps: [.init("Warm", seconds: 20, watts: 100), .init("Work", seconds: 20, watts: 200), .init("Cool", seconds: 20, watts: 120)])
    var engine = RideEngine(configuration: try featureConfig(), training: plan)
    for t in 0...5 { engine.receive(.init(time: Double(t), power: 100, cadence: 90, heartRate: 120 + t)); engine.tick(at: Double(t)) }
    #expect(engine.currentStep?.index == 0); #expect(engine.canSkipStep)
    let skipped = engine.skipStep(at: 5); #expect(skipped)
    #expect(engine.currentStep?.index == 1); #expect(engine.targetPower == 200); #expect(engine.trainingElapsed == 20)
    // Paused, a skip still moves on, and resuming carries on from the new step.
    let paused = engine.pause(at: 6); #expect(paused)
    let skippedPaused = engine.skipStep(at: 6); #expect(skippedPaused); #expect(engine.currentStep?.index == 2)
    // The last step is never skipped: that would end the ride without Stop & save.
    #expect(!engine.canSkipStep); let last = engine.skipStep(at: 6); #expect(!last)
    for t in 6...9 { engine.receive(.init(time: Double(t), power: 120, cadence: 90, heartRate: 130)) }
    let resumed = engine.resume(at: 9); #expect(resumed); engine.tick(at: 9); #expect(engine.targetPower == 120)

    let clock = try #require(WorkoutClock(engine.session))
    #expect(clock.trainingTime(at: 4) == 4); #expect(clock.trainingTime(at: 5) == 20)
    #expect(clock.trainingTime(at: 7) == nil); #expect(clock.trainingTime(at: 9) == 40)
    let targets = TargetSeries.make(engine.session)
    #expect(targets.contains { $0.time == 5 && $0.watts == 200 })
    let heart = WorkoutClock.heartRate(engine.session)
    #expect(heart.first?.time == 0); #expect(heart.contains { $0.time == 20 && $0.bpm == 125 })
    #expect(!heart.contains { $0.time > 20 && $0.time < 40 })
}
