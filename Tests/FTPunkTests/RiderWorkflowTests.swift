import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
import FTPunkIntegrations
@testable import FTPunkApp

@Test func zwiftStepsChangeOnlyOnMinuteBoundariesAndRespectLimits() throws {
    let config = try SessionConfiguration(preset: .zwift, warmupSeconds: 0)
    #expect(config.rampPower(at: 0) == 100)
    #expect(config.rampPower(at: 59.999) == 100)
    #expect(config.rampPower(at: 60) == 120)
    #expect(config.rampPower(at: 119.999) == 120)
    #expect(config.rampPower(at: 120) == 140)
    #expect(config.rampPower(at: 1500) == 600)
    var engine = RampEngine(configuration: config, isDemo: true)
    for second in 0...1561 {
        engine.receive(RideSample(time: Double(second), power: 200, cadence: 90))
        engine.tick(at: Double(second))
    }
    #expect(engine.session.outcome == .limitReached)
    #expect(engine.session.result == nil)
}

@Test func oldProfilesAndSessionsDecodeWithoutLosingTheirOwner() throws {
    let oldProfile = Data(#"{"weightKG":75,"ftpHistory":[]}"#.utf8)
    let profile = try JSONDecoder().decode(RiderProfile.self, from: oldProfile)
    #expect(profile.id == RiderProfile.legacyID)
    #expect(profile.name == "You")
    let original = TestSession(configuration: try SessionConfiguration(weightKG: 75))
    let encoder = JSONEncoder()
    var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
    var configuration = try #require(object["configuration"] as? [String: Any])
    configuration.removeValue(forKey: "riderID"); configuration.removeValue(forKey: "riderName")
    configuration["protocolVersion"] = 1; object["configuration"] = configuration
    let restored = try JSONDecoder().decode(TestSession.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.riderID == profile.id)
    #expect(restored.configuration.protocolVersion == 1)
    #expect(restored.configuration.rampPower(at: 12) == 105)
}

@Test @MainActor func profilesPersistSeparatelyAndHistoryUsesIdentity() throws {
    let store = try LocalStore(inMemory: true)
    let a = RiderProfile(name: "Alex", weightKG: 75, ftpHistory: [FTPEntry(watts: 250)])
    let b = RiderProfile(id: UUID(), name: "Alex", weightKG: 55, ftpHistory: [FTPEntry(watts: 180)])
    try store.saveProfile(a); try store.saveProfile(b)
    var renamed = a; renamed.name = "Alex One"; try store.saveProfile(renamed)
    #expect(try store.profiles().count == 2)
    #expect(try store.profiles().first { $0.id == b.id }?.currentFTP == nil)
    #expect(try store.profiles().first { $0.id == b.id }?.weightKG == 55)
    let first = TestSession(configuration: try SessionConfiguration(weightKG: 75, riderID: a.id, riderName: a.name))
    let second = TestSession(configuration: try SessionConfiguration(weightKG: 55, riderID: b.id, riderName: b.name))
    try store.save(first); try store.save(second)
    let groups = RiderHistory.groups(sessions: try store.sessions(), profiles: try store.profiles())
    #expect(groups.count == 2)
    #expect(groups.first { $0.id == a.id }?.name == "Alex One")
    #expect(groups.first { $0.id == a.id }?.sessions.first?.riderName == "Alex")
    try store.deleteSession(id: first.id)
    #expect(try store.sessions().map(\.id) == [second.id])
    #expect(try store.profiles().count == 2)
}

private func finalizedSession(rider: RiderProfile, demo: Bool = false) throws -> TestSession {
    var session = TestSession(configuration: try SessionConfiguration(weightKG: rider.weightKG, riderID: rider.id, riderName: rider.name), isDemo: demo)
    session.endedAtOffset = 90; session.outcome = .exhaustion
    session.samples = [RideSample(time: 0, power: 300, cadence: 90)]
    session.result = FTPResult(bestMinutePower: 300, windowStart: 20, windowEnd: 80, weightKG: rider.weightKG)
    return session
}

@Test @MainActor func uploadRequiresConsentAndRejectsAccountChangesAndMockRides() async throws {
    let store = try LocalStore(inMemory: true)
    let model = try AppModel(store: store, preview: true)
    let session = try finalizedSession(rider: model.profile)
    try store.save(session); try model.reload()
    model.requestUpload(session)
    #expect(model.uploadConsent == nil)
    model.connection = IntervalsConnection(athleteID: "account-a", athleteName: "Account A", apiKey: "fixture")
    model.requestUpload(session)
    let consent = try #require(model.uploadConsent)
    #expect(consent.accountID == "account-a")
    #expect(consent.session.riderID == session.riderID)
    #expect(try store.uploadJobs().isEmpty) // Displaying the prompt does not enqueue or send.
    model.connection = IntervalsConnection(athleteID: "account-b", athleteName: "Account B", apiKey: "fixture")
    await model.confirmUpload(consent)
    #expect(model.errorMessage != nil)
    #expect(try store.uploadJobs().isEmpty)
    model.uploadConsent = nil
    model.requestUpload(try finalizedSession(rider: model.profile, demo: true))
    #expect(model.uploadConsent == nil)
}

@Test @MainActor func adoptingAnotherRidersResultNeverChangesSelectedRidersFTP() throws {
    let store = try LocalStore(inMemory: true)
    let model = try AppModel(store: store, preview: true)
    let firstID = model.profile.id
    #expect(model.addRider(name: "Guest"))
    model.weight = "55"; #expect(model.saveRiderDetails())
    let guest = model.profile
    model.selectRider(firstID)
    model.adopt(try finalizedSession(rider: guest))
    #expect(model.profile.id == firstID)
    #expect(model.profile.ftpHistory.isEmpty)
    let savedGuest = try #require(store.profiles().first { $0.id == guest.id })
    #expect(savedGuest.currentFTP?.watts == 216)
    #expect(savedGuest.weightKG == 55)
}

@Test @MainActor func debugWorkoutStoresRiderSnapshotAndDeleteClearsCurrentResult() async throws {
    let store = try LocalStore(inMemory: true)
    let model = try AppModel(store: store, preview: true)
    model.riderName = "Casey"; model.weight = "60"; model.manualFTP = "240"
    model.preset = .zwift
    await model.start()
    model.mockPaused = true
    model.skipMockWarmup(); model.advanceMock(seconds: 800)
    let session = try #require(model.engine?.session)
    #expect(session.endedAtOffset != nil)
    #expect(session.riderName == "Casey")
    #expect(session.configuration.warmupPower == 120)
    #expect(session.result?.wattsPerKG == session.result.map { $0.estimatedFTP / 60 })
    #expect(model.history.contains { $0.id == session.id })
    model.delete(session)
    #expect(model.engine == nil)
    #expect(model.history.isEmpty)
}
