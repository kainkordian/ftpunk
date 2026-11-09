import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage

private func archiveFixture() throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("ftpunk_web/tests/fixtures/portable-v1.json"))
}

@Test func portableArchiveReadsTheBrowserFixtureAndRetainsTheScoredSnapshot() throws {
    let archive = try PortableArchive.decode(archiveFixture())
    let session = try #require(archive.activities.first?.session)
    #expect(session.configuration.priorFTP?.watts == 250)
    #expect(session.configuration.usesPowerMatching)
    #expect(session.configuration.resolvedCadenceSource == .trainer)
    #expect(session.result?.estimatedFTP == 225)
    #expect(session.result?.wattsPerKG == 3)
    #expect(session.samples.count == 71)
    #expect(session.samples[0].trainerPower == 280)
    let restored = try PortableArchive.decode(archive.encoded())
    #expect(restored.activities[0].session.configuration == session.configuration)
    #expect(restored.activities[0].session.samples == session.samples)
    #expect(restored.profiles[0].currentFTP?.watts == 250)
}

@Test func portableArchiveRejectsFutureVersionsMissingRidersAndLiveActivities() throws {
    let archive = try PortableArchive.decode(archiveFixture())
    var missing = archive; missing.profiles = []
    #expect(throws: (any Error).self) { try missing.validate() }
    var live = archive; live.activities[0].session.endedAtOffset = nil
    #expect(throws: (any Error).self) { try live.encoded() }
    var duplicate = archive; duplicate.activities.append(duplicate.activities[0])
    #expect(throws: (any Error).self) { try duplicate.validate() }
    var invalid = archive; invalid.activities[0].session.samples[0].time = .infinity
    #expect(throws: (any Error).self) { try invalid.validate() }
    var invalidBalance = archive; invalidBalance.activities[0].session.samples[0].leftBalance = 100.5
    #expect(throws: (any Error).self) { try invalidBalance.validate() }
    invalidBalance.activities[0].session.samples[0].leftBalance = -1
    #expect(throws: (any Error).self) { try invalidBalance.validate() }
    invalidBalance.activities[0].session.samples[0].leftBalance = 47.5
    try invalidBalance.validate()
    var invalidRR = archive; invalidRR.activities[0].session.samples[0].rrIntervals = [-1]
    #expect(throws: (any Error).self) { try invalidRR.validate() }
    var withRR = archive; withRR.activities[0].session.samples[0].rrIntervals = [0.5, 0.75]
    #expect(try PortableArchive.decode(withRR.encoded()).activities[0].session.samples[0].rrIntervals == [0.5, 0.75])
    var object = try #require(JSONSerialization.jsonObject(with: archiveFixture()) as? [String: Any])
    object["version"] = 4
    #expect(throws: (any Error).self) { try PortableArchive.decode(JSONSerialization.data(withJSONObject: object)) }
}

@Test @MainActor func restoringPortableDataIsIdempotentAndPreservesUnrelatedRiders() throws {
    let store = try LocalStore(inMemory: true), archive = try PortableArchive.decode(archiveFixture())
    let other = RiderProfile(id: UUID(), name: "Other rider")
    try store.saveProfile(other)
    var otherSession = TestSession(configuration: try SessionConfiguration(riderID: other.id, riderName: other.name))
    otherSession.endedAtOffset = 0; otherSession.outcome = .aborted
    try store.save(otherSession)
    try store.restore(archive)
    try store.restore(archive)
    #expect(try store.profiles().count == 2)
    #expect(try store.sessions().count == 2)
    #expect(try store.sessions().first(where: { $0.id == archive.activities[0].session.id })?.samples.count == 71)
    #expect(try store.sessions().contains(where: { $0.id == otherSession.id }))
    #expect(try store.uploadJobs().isEmpty)
    var shorter = archive
    shorter.activities[0].session.samples = [shorter.activities[0].session.samples[0]]
    try store.restore(shorter)
    #expect(try store.sessions().first(where: { $0.id == archive.activities[0].session.id })?.samples.count == 1)
}

@Test @MainActor func invalidRestoreDoesNotChangeExistingSQLiteHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.sqlite")
    let store = try LocalStore(url: url), archive = try PortableArchive.decode(archiveFixture())
    try store.restore(archive)
    var bad = archive; bad.activities[0].session.outcome = nil
    #expect(throws: (any Error).self) { try store.restore(bad) }
    let reopened = try LocalStore(url: url)
    #expect(try reopened.sessions().count == 1)
    #expect(try reopened.sessions()[0].samples.count == 71)
    #expect(try reopened.sessions()[0].result?.estimatedFTP == 225)
}

@Test func sessionOwnershipIncludesPreparationReleaseAndRejectsStaleCallbacks() throws {
    var owner = SessionOwnership()
    let firstValue = owner.begin(), first = try #require(firstValue)
    let overlapping = owner.begin(); #expect(overlapping == nil)
    owner.cancelStart("Screen locked")
    let cancelled = owner.started(first); #expect(!cancelled)
    let finishingFirst = owner.beginFinishing(first); #expect(finishingFirst)
    #expect(!owner.canControl(first))
    let whileReleasing = owner.begin(); #expect(whileReleasing == nil)
    owner.released(first)
    let secondValue = owner.begin(), second = try #require(secondValue)
    let startedSecond = owner.started(second); #expect(startedSecond)
    #expect(owner.canControl(second))
    #expect(!owner.canControl(first))
    owner.released(first)
    #expect(owner.isBusy)
    let finishingSecond = owner.beginFinishing(second); #expect(finishingSecond)
    let duplicateFinish = owner.beginFinishing(second); #expect(!duplicateFinish)
    owner.released(second)
    #expect(!owner.isBusy)
}

@Test @MainActor func restoreCancelsReplacedUploadsAndRejectsCrossRiderActivityCollisions() throws {
    let store = try LocalStore(inMemory: true), archive = try PortableArchive.decode(archiveFixture())
    try store.restore(archive)
    let job = ActivityUploadJob(sessionID: archive.activities[0].session.id, accountID: "reviewed-account",
                               file: Data(), name: "Approved upload", description: "Fixture")
    try store.saveUploadJob(job)
    try store.restore(archive)
    #expect(try store.uploadJobs().isEmpty)
    let other = RiderProfile(id: UUID(), name: "Other")
    var colliding = archive
    colliding.profiles = [other]
    colliding.activities[0].session.configuration = try SessionConfiguration(riderID: other.id, riderName: other.name)
    #expect(throws: ArchiveError.self) { try store.restore(colliding) }
    #expect(try store.profiles().count == 1)
    #expect(try store.sessions()[0].riderID == archive.profiles[0].id)
}
