import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
import FTPunkIntegrations
@testable import FTPunkApp

private func connection(_ id: String, name: String = "Athlete") -> IntervalsConnection {
    IntervalsConnection(athleteID: id, athleteName: name, apiKey: "fixture-\(id)")
}

// MARK: Vault migration

@Test func legacyConnectionMovesToTheRiderOnceAndIsCleared() throws {
    let rider = UUID(), vault = InMemoryCredentialVault(legacy: connection("i1"))
    #expect(try vault.migrateLegacyConnection(to: rider)?.athleteID == "i1")
    #expect(try vault.load(riderID: rider)?.athleteID == "i1")
    #expect(try vault.loadLegacy() == nil)
    #expect(try vault.allRiderIDs() == [rider])
    // Already migrated: nothing happens, nothing is overwritten.
    #expect(try vault.migrateLegacyConnection(to: UUID()) == nil)
    #expect(try vault.load(riderID: rider)?.athleteID == "i1")
}

@Test func migrationWithoutALegacyItemDoesNothing() throws {
    let vault = InMemoryCredentialVault()
    #expect(try vault.migrateLegacyConnection(to: UUID()) == nil)
    #expect(try vault.allRiderIDs().isEmpty)
}

@Test func migrationNeverOverwritesARidersExistingConnection() throws {
    let rider = UUID(), vault = InMemoryCredentialVault(legacy: connection("old"), riders: [UUID(): connection("x")])
    try vault.save(connection("kept"), riderID: rider)
    try vault.migrateLegacyConnection(to: rider)
    #expect(try vault.load(riderID: rider)?.athleteID == "kept")
    #expect(try vault.loadLegacy() == nil)
}

@Test func keychainAccountsAreLowercasedRiderIDs() {
    let id = UUID()
    #expect(CredentialVault.account(for: id) == "rider:" + id.uuidString.lowercased())
    #expect(CredentialVault.riderID(fromAccount: CredentialVault.account(for: id)) == id)
    #expect(CredentialVault.riderID(fromAccount: "personal-connection") == nil)
}

@Test @MainActor func launchMigratesTheLegacyConnectionToTheSelectedRider() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true,
                             credentials: InMemoryCredentialVault(legacy: connection("i1", name: "Old")))
    #expect(model.connection?.athleteName == "Old")
    #expect(try model.credentials.loadLegacy() == nil)
    #expect(try model.credentials.load(riderID: model.profile.id)?.athleteID == "i1")
}

// MARK: Per-rider connections

@Test @MainActor func switchingRiderSwitchesTheConnection() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    let first = model.profile.id
    try model.store.saveProfile(model.profile)
    try await model.acceptConnection(connection("i1", name: "Alex Intervals"))
    #expect(model.addRider(name: "Guest"))
    #expect(model.connection == nil)
    try await model.acceptConnection(connection("i2", name: "Guest Intervals"))
    #expect(model.connection?.athleteID == "i2")
    model.selectRider(first)
    #expect(model.connection?.athleteID == "i1")
    #expect(try model.credentials.allRiderIDs().count == 2)
    await model.disconnectIntervals()
    #expect(model.connection == nil && model.connections.count == 1)
    #expect(try model.credentials.load(riderID: first) == nil)
}

@Test @MainActor func oneAccountConnectsToOneRiderOnly() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    let first = model.profile
    try await model.acceptConnection(connection("i1"))
    #expect(model.addRider(name: "Guest"))
    try await model.acceptConnection(connection("i1"))
    #expect(model.errorMessage == "This Intervals.icu account is already connected to \(first.name).")
    #expect(model.connection == nil)
    #expect(try model.credentials.allRiderIDs() == [first.id])
}

private actor AccountRecorder: ActivityUploader {
    private(set) var credentials: [String] = []
    func upload(_ job: ActivityUploadJob, credential: String) async throws -> [String] {
        credentials.append("\(job.accountID):\(credential)"); return ["i1"]
    }
}

private func rideSession(for rider: RiderProfile) throws -> TestSession {
    var session = TestSession(configuration: try SessionConfiguration(weightKG: 70, riderID: rider.id, riderName: rider.name))
    session.samples = [RideSample(time: 0, power: 200)]; session.endedAtOffset = 90; session.outcome = .exhaustion
    session.result = FTPResult(bestMinutePower: 300, windowStart: 20, windowEnd: 80, weightKG: 70)
    return session
}

@Test @MainActor func queuedJobsFlushForEveryRidersOwnAccount() async throws {
    let recorder = AccountRecorder(), store = try LocalStore(inMemory: true)
    let model = try AppModel(store: store, preview: true, uploader: recorder)
    let alex = model.profile
    try store.saveProfile(alex)
    try await model.acceptConnection(connection("i1"))
    #expect(model.addRider(name: "Guest"))
    let guest = model.profile
    try await model.acceptConnection(connection("i2"))
    // The selected rider is Guest, yet Alex's activity goes to Alex's account.
    let alexSession = try rideSession(for: alex), guestSession = try rideSession(for: guest)
    try store.save(alexSession); try store.save(guestSession); try model.reload()
    model.requestUpload(alexSession)
    let consent = try #require(model.uploadConsent)
    #expect(consent.accountID == "i1" && consent.riderID == alex.id)
    await model.confirmUpload(consent)
    model.requestUpload(guestSession)
    await model.confirmUpload(try #require(model.uploadConsent))
    let sent = Set(await recorder.credentials.map { $0.split(separator: ":").first.map(String.init) ?? "" })
    #expect(sent == ["i1", "i2"])
    #expect(try store.uploadJobs().allSatisfy { $0.status == .uploaded })
    // Disconnecting Alex removes only account i1's jobs.
    model.selectRider(alex.id)
    await model.disconnectIntervals()
    #expect(try store.uploadJobs().map(\.accountID) == ["i2"])
}

@Test @MainActor func aRidersCredentialWithoutARiderIsDeletedWithItsJobs() throws {
    let store = try LocalStore(inMemory: true), ghost = UUID()
    let vault = InMemoryCredentialVault(riders: [ghost: connection("i9")])
    try store.saveUploadJob(ActivityUploadJob(sessionID: UUID(), accountID: "i9", file: Data(), name: "x", description: ""))
    let model = try AppModel(store: store, preview: true, credentials: vault)
    #expect(try vault.allRiderIDs().isEmpty)
    #expect(try store.uploadJobs().isEmpty)
    #expect(model.connections.isEmpty)
}

// MARK: Upload prompt

private func promptSession(training: TrainingPlan? = nil, outcome: SessionOutcome, ended: Double, result: Bool = false, demo: Bool = false) throws -> TestSession {
    var session = TestSession(configuration: try SessionConfiguration(), isDemo: demo)
    session.training = training; session.outcome = outcome; session.endedAtOffset = ended
    if result { session.result = FTPResult(bestMinutePower: 300, windowStart: 20, windowEnd: 80) }
    return session
}
private func ask(_ session: TestSession, connected: Bool = true, enabled: Bool = true, job: ActivityUploadJob? = nil) -> Bool {
    UploadPromptRule.shouldAsk(session: session, hasConnection: connected, askEnabled: enabled, existingJob: job)
}

@Test func uploadPromptRuleCoversEveryCase() throws {
    let workout = try TrainingPlan(kind: .workout, name: "W", steps: [.init("a", seconds: 600, watts: 150)])
    let free = try TrainingPlan.freeRide(watts: 150)
    #expect(ask(try promptSession(outcome: .exhaustion, ended: 900, result: true)))              // FTP result
    #expect(!ask(try promptSession(outcome: .aborted, ended: 900)))                              // FTP test stopped without a result
    #expect(ask(try promptSession(training: workout, outcome: .completed, ended: 1800)))        // completed workout
    #expect(ask(try promptSession(training: workout, outcome: .aborted, ended: 600)))           // stopped by the rider after 10 minutes
    #expect(ask(try promptSession(training: free, outcome: .aborted, ended: 300)))              // exactly 5 minutes
    #expect(!ask(try promptSession(training: free, outcome: .aborted, ended: 240)))             // 4-minute free ride
    #expect(!ask(try promptSession(training: workout, outcome: .interrupted, ended: 1200)))     // interrupted
    #expect(!ask(try promptSession(outcome: .exhaustion, ended: 900, result: true, demo: true))) // demo
    let queued = ActivityUploadJob(sessionID: UUID(), accountID: "i1", file: Data(), name: "x", description: "")
    #expect(!ask(try promptSession(training: workout, outcome: .completed, ended: 1800), job: queued)) // already queued or uploaded
    #expect(!ask(try promptSession(training: workout, outcome: .completed, ended: 1800), connected: false))
    #expect(!ask(try promptSession(training: workout, outcome: .completed, ended: 1800), enabled: false))
}

@Test @MainActor func askingAfterARideOpensTheSheetPerRiderPreferenceWithoutUploading() async throws {
    let store = try LocalStore(inMemory: true), recorder = AccountRecorder()
    let model = try AppModel(store: store, preview: true, uploader: recorder)
    let session = try rideSession(for: model.profile)
    try store.save(session); try model.reload()
    model.askToUploadAfterRide(session)
    #expect(model.uploadConsent == nil)                      // no connection
    try await model.acceptConnection(connection("i1"))
    model.askToUploadAfterRide(session)
    #expect(model.uploadConsent?.accountID == "i1")
    #expect(await recorder.credentials.isEmpty)
    #expect(try store.uploadJobs().isEmpty)
    model.uploadConsent = nil
    model.askToUploadAfterRide = false
    model.askToUploadAfterRide(session)
    #expect(model.uploadConsent == nil)                      // prompt switched off for this rider
    #expect(model.addRider(name: "Guest") && model.askToUploadAfterRide) // on by default for the next rider
}

// MARK: User-Agent

@Test func everyIntervalsRequestCarriesTheAppUserAgent() throws {
    let agent = IntervalsClient.userAgent(version: "1.2", platform: "iOS")
    #expect(agent == "FTPunk/1.2 (iOS)")
    let oauth = IntervalsConnection(athleteID: "i1", athleteName: "A", accessToken: "t", scopes: ["CALENDAR:READ"])
    let job = ActivityUploadJob(sessionID: UUID(), accountID: "i1", file: Data(), name: "n", description: "")
    #expect(IntervalsClient.uploadRequest(job, credential: "c", userAgent: agent).value(forHTTPHeaderField: "User-Agent") == agent)
    #expect(try IntervalsClient.workoutRequest(connection: oauth, oldest: "2026-11-01", newest: "2026-11-14", userAgent: agent)
        .value(forHTTPHeaderField: "User-Agent") == agent)
    let attempt = try IntervalsOAuthAttempt(configuration: IntervalsOAuthConfiguration(clientID: "c", redirectURI: URL(string: "ftpunk://oauth/intervals")!))
    #expect(IntervalsClient.exchangeRequest(attempt, code: "x", userAgent: agent).value(forHTTPHeaderField: "User-Agent") == agent)
    // Without an explicit value the requests still say who is asking.
    #expect(IntervalsClient.uploadRequest(job, credential: "c").value(forHTTPHeaderField: "User-Agent") == "FTPunk")
}

private final class AgentProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var seen: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seen[request.url?.path ?? "?"] = request.value(forHTTPHeaderField: "User-Agent")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"id":"i1","name":"A","icu_weight":70,"sportSettings":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func connectAthleteSettingsAndRevokeSendTheUserAgent() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AgentProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let client = IntervalsClient(session: session, userAgent: "FTPunk/9 (macOS)")
    let made = try await client.connect(apiKey: "k")
    _ = try await client.athleteSettings(connection: made)
    try await client.revoke(IntervalsConnection(athleteID: "i1", athleteName: "A", accessToken: "t"))
    #expect(AgentProtocol.seen.values.allSatisfy { $0 == "FTPunk/9 (macOS)" } && AgentProtocol.seen.count >= 2)
}

// MARK: Athlete settings fixture (verified shape, 2026-11-04)

private func liveShape(indoor: String) -> String {
    #"""
    {"id":"i1","name":"Rider","icu_weight":71.0,"weight":null,"weight_pref_lb":false,"icu_weight_sync":"NONE",
     "sportSettings":[
      {"types":["Ride","VirtualRide","MountainBikeRide","GravelRide","TrackRide","Cyclocross"],"ftp":230,"indoor_ftp":\#(indoor),"sft_ftp":null,"ftp_est_min_secs":1200,"eFTPSupported":true},
      {"types":["Run"],"ftp":null,"indoor_ftp":null,"eFTPSupported":false},
      {"types":["Swim"],"ftp":null,"indoor_ftp":null,"eFTPSupported":false},
      {"types":["Other"],"ftp":null,"indoor_ftp":null,"eFTPSupported":false}]}
    """#
}

@Test func athleteSettingsDecodeTheVerifiedLiveShape() throws {
    let plain = try IntervalsClient.decodeAthleteSettings(Data(liveShape(indoor: "null").utf8))
    #expect(plain == IntervalsAthleteSettings(weightKG: 71, ftpWatts: 230))
    let indoor = try IntervalsClient.decodeAthleteSettings(Data(liveShape(indoor: "250").utf8))
    #expect(indoor == IntervalsAthleteSettings(weightKG: 71, ftpWatts: 250))
}
