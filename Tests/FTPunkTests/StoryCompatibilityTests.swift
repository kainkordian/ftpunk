import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

// The Lowline story is gone from the native app. Its data is not: backups from the web app (which keeps the story
// until its own port) must import, validate, export and re-import without losing a single credited millisecond.

private func webFixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("ftpunk_web/tests/fixtures/\(name).json"))
}
private func object(_ data: Data) throws -> [String: Any] { try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
private let aliceLedger: [String: Int] = ["cccccccc-cccc-cccc-cccc-cccccccccccc": 6000, "dddddddd-dddd-dddd-dddd-dddddddddddd": 1_200_000]

@Test func aWebV2BackupKeepsItsStoryLedgerAndSessionFields() throws {
    let archive = try PortableArchive.decode(webFixture("portable-v2"))
    let progress = try #require(archive.profiles[0].cycleProgress)
    #expect(progress.credits == aliceLedger && progress.milliseconds == 1_206_000)
    let session = try #require(archive.activities.first?.session)
    #expect(session.adventureEnabled == true && session.eligibleMilliseconds == 6000 && session.adventureStartMilliseconds == nil)
    // Exporting writes the same ledger and fields back out, byte for byte at the JSON level.
    let exported = try object(archive.encoded())
    let profile = try #require((exported["profiles"] as? [[String: Any]])?.first)
    #expect((profile["cycleProgress"] as? [String: Any])?["credits"] as? [String: Int] == aliceLedger)
    let written = try #require(((exported["activities"] as? [[String: Any]])?.first?["session"]) as? [String: Any])
    #expect(written["adventureEnabled"] as? Bool == true && written["eligibleMilliseconds"] as? Int == 6000)
    #expect(exported["version"] as? Int == 2)
}

@Test func aWebV3BackupKeepsTheAdventureStartingPoint() throws {
    let archive = try PortableArchive.decode(webFixture("portable-v3"))
    let session = try #require(archive.activities.first?.session)
    #expect(session.adventureEnabled == true && session.adventureStartMilliseconds == 0 && session.eligibleMilliseconds == 0)
    let again = try PortableArchive.decode(archive.encoded())
    #expect(again.version == 3 && again.activities[0].session.adventureStartMilliseconds == 0)
    #expect(again.activities[0].session.adventureEnabled == true && again.activities[0].session.eligibleMilliseconds == 0)
}

@Test @MainActor func restoringAndExportingFromTheStoreRoundTripsStoryDataUnchanged() throws {
    let source = try PortableArchive.decode(webFixture("portable-v2"))
    let store = try LocalStore(inMemory: true)
    try store.restore(source); try store.restore(source) // idempotent
    #expect(try store.profiles()[0].cycleProgress == source.profiles[0].cycleProgress)
    let exported = try store.portableArchive()
    #expect(exported.profiles[0].cycleProgress == source.profiles[0].cycleProgress)
    #expect(exported.activities[0].session.adventureEnabled == true && exported.activities[0].session.eligibleMilliseconds == 6000)
    // Re-importing the export into a fresh store gives the same ledger and the same recording fields.
    let second = try LocalStore(inMemory: true)
    try second.restore(PortableArchive.decode(exported.encoded()))
    #expect(try second.profiles()[0].cycleProgress?.credits == aliceLedger)
    let session = try #require(second.sessions().first)
    #expect(session.adventureEnabled == true && session.eligibleMilliseconds == 6000)
    // Deleting the recording keeps the rider's ledger, as it always did.
    try second.deleteSession(id: session.id)
    #expect(try second.profiles()[0].cycleProgress?.credits == aliceLedger)
}

@Test func invalidStoryDataIsStillRejectedOnImport() throws {
    var archive = try PortableArchive.decode(webFixture("portable-v2"))
    var negative = archive; negative.profiles[0].cycleProgress?.credits["cccccccc-cccc-cccc-cccc-cccccccccccc"] = -1
    #expect(throws: (any Error).self) { try negative.validate() }
    var badKey = archive; badKey.profiles[0].cycleProgress?.credits["not-an-activity"] = 1000
    #expect(throws: (any Error).self) { try badKey.validate() }
    var tooLong = archive; tooLong.activities[0].session.eligibleMilliseconds = 90_000_000
    #expect(throws: (any Error).self) { try tooLong.validate() }
    var impossible = archive; impossible.activities[0].session.eligibleMilliseconds = 6000; impossible.activities[0].session.endedAtOffset = 1
    #expect(throws: (any Error).self) { try impossible.validate() }
    #expect(throws: (any Error).self) { try badKey.encoded() }
    archive.profiles[0].cycleProgress?.version = 2
    #expect(throws: (any Error).self) { try archive.validate() }
}

@Test func legacyRecordingsDecodeWithTheirStoryFields() throws {
    let json = #"""
    {"id":"11111111-1111-1111-1111-111111111111","startedAt":0,"isDemo":false,"devices":[],"samples":[],"events":[],
     "adventureEnabled":true,"adventureStartMilliseconds":290000,"eligibleMilliseconds":30000,
     "configuration":\#(String(decoding: try JSONEncoder().encode(try SessionConfiguration()), as: UTF8.self))}
    """#
    let session = try JSONDecoder().decode(TestSession.self, from: Data(json.utf8))
    #expect(session.adventureEnabled == true && session.adventureStartMilliseconds == 290_000 && session.eligibleMilliseconds == 30_000)
    let again = try JSONDecoder().decode(TestSession.self, from: JSONEncoder().encode(session))
    #expect(again.adventureStartMilliseconds == 290_000 && again.eligibleMilliseconds == 30_000)
}

@Test @MainActor func legacyRecordingsStillCreditTheLedgerOnceAndDeletionKeepsIt() throws {
    let store = try LocalStore(inMemory: true)
    try store.saveProfile(RiderProfile())
    var legacy = TestSession(configuration: try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID))
    legacy.training = try .freeRide(watts: 100)
    legacy.adventureEnabled = true; legacy.adventureStartMilliseconds = 0; legacy.eligibleMilliseconds = 6000
    legacy.outcome = .completed; legacy.endedAtOffset = 30
    try store.save(legacy); try store.save(legacy)
    #expect(try store.profiles()[0].cycleProgress?.milliseconds == 6000)
    try store.deleteSession(id: legacy.id)
    #expect(try store.profiles()[0].cycleProgress?.milliseconds == 6000)
    // A stale copy of the rider cannot erase the ledger either.
    try store.saveProfile(RiderProfile())
    #expect(try store.profiles()[0].cycleProgress?.milliseconds == 6000)
}

@Test @MainActor func nativeRidesNeverEnableOrAccrueStoryProgressAndLeaveAnImportedLedgerAlone() async throws {
    let store = try LocalStore(inMemory: true)
    let archive = try PortableArchive.decode(webFixture("portable-v2"))
    try store.restore(archive)
    let model = try AppModel(store: store, preview: true)
    model.selectRider(archive.profiles[0].id)
    let ledger = try store.profiles()[0].cycleProgress
    await model.start(training: try .freeRide(watts: 120))
    model.advanceMock(seconds: 90)
    model.stop(); model.closeCockpit()
    let ride = try #require(store.sessions().first { $0.training != nil && $0.id != archive.activities[0].session.id })
    #expect(ride.adventureEnabled == nil && ride.adventureStartMilliseconds == nil && ride.eligibleMilliseconds == nil)
    #expect(try store.profiles()[0].cycleProgress == ledger)
    // Real riding by the engine, too: the removed story's counters stay out of the recording.
    var engine = RideEngine(configuration: try SessionConfiguration(warmupSeconds: 0, riderID: archive.profiles[0].id), training: try .freeRide(watts: 100))
    for second in 0...60 { engine.receive(RideSample(time: Double(second), power: 150, cadence: 90)); engine.tick(at: Double(second)) }
    #expect(engine.session.adventureEnabled == nil && engine.session.eligibleMilliseconds == nil)
    try store.save(engine.session)
    #expect(try store.profiles()[0].cycleProgress == ledger)
    // And exporting after native rides still carries the imported ledger.
    #expect(try store.portableArchive().profiles[0].cycleProgress == ledger)
}

@Test func theRemovedStorySwitchIsNotPartOfTheNativeApp() {
    #expect(AppDestination.allCases.map(\.rawValue) == ["home", "progress", "settings"])
    #expect(HomeSection.library.rawValue == "library")
}
