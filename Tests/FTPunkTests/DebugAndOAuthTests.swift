import Foundation
import Testing
import FTPunkDomain
import FTPunkIntegrations

@Test func mockStreamCompletesRealEngineAndCalculatesResult() throws {
    let configuration = try SessionConfiguration(priorFTP: FTPEntry(watts: 250), weightKG: 75,
                                                 warmupSeconds: 10, cooldownSeconds: 10)
    var engine = RampEngine(configuration: configuration, isDemo: true)
    var stream = MockRideStream()
    for index in 1...1200 where engine.phase.isActive {
        let time = Double(index) / 2
        let value = stream.sample(at: time, target: engine.targetPower ?? 125, phase: engine.phase)
        engine.receive(value); engine.tick(at: time)
    }
    #expect(engine.phase == .completed)
    #expect(engine.session.outcome == .exhaustion)
    #expect(engine.session.isDemo)
    let result = try #require(engine.session.result)
    #expect(result.bestMinutePower > 200)
    #expect(result.wattsPerKG == result.estimatedFTP / 75)
    #expect(engine.session.configuration.warmupPower == 125)
}

@Test func mockPowerLossIsMissingAndInterruptsInsteadOfReportingZero() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0), isDemo: true)
    var stream = MockRideStream()
    for index in 1...160 where engine.phase.isActive {
        let time = Double(index) / 2
        let scenario: MockScenario = time > 70 ? .powerDropout : .steadyRider
        let value = stream.sample(at: time, target: engine.targetPower ?? 100, phase: engine.phase, scenario: scenario)
        if time > 70 { #expect(value.power == nil) }
        engine.receive(value); engine.tick(at: time)
    }
    #expect(engine.phase == .interrupted)
    #expect(engine.session.outcome == .interrupted)
    #expect(engine.session.result == nil)
}

@Test func mockManualValuesAreExactAndStreamsRepeat() {
    var a = MockRideStream(), b = MockRideStream()
    for index in 1...20 {
        let time = Double(index) / 2
        #expect(a.sample(at: time, target: 200, phase: .ramp) == b.sample(at: time, target: 200, phase: .ramp))
    }
    let manual = a.sample(at: 11, target: 300, phase: .ramp, manualPower: 0, manualCadence: 0, manualHeartRate: 120)
    #expect(manual.power == 0); #expect(manual.cadence == 0); #expect(manual.heartRate == 120)
}

private func oauthFixture() throws -> IntervalsOAuthAttempt {
    try IntervalsOAuthAttempt(
        configuration: IntervalsOAuthConfiguration(clientID: "fixture-client", redirectURI: URL(string: "ftpunk://oauth/intervals")!),
        verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "fixture-state"
    )
}

@Test func pkceChallengeMatchesStandardFixtureAndRequestsOnlyActivityUpload() throws {
    let attempt = try oauthFixture()
    #expect(attempt.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let query = try #require(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.first(where: { $0.name == "scope" })?.value == "ACTIVITY:WRITE")
    #expect(query.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    let body = String(decoding: attempt.tokenRequest(code: "code+&=").httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains("code=code%2B%26%3D"))
    #expect(body.contains("code_verifier=")); #expect(!body.contains("client_secret"))
}

@Test func oauthCallbacksRejectForgedStateRoutesAndDuplicateCodes() throws {
    let attempt = try oauthFixture()
    #expect(try attempt.authorizationCode(from: URL(string: "ftpunk://oauth/intervals?state=fixture-state&code=valid")!) == "valid")
    for url in [
        "ftpunk://oauth/intervals?state=wrong&code=valid",
        "ftpunk://other/intervals?state=fixture-state&code=valid",
        "ftpunk://oauth/intervals?state=fixture-state&code=a&code=b",
        "ftpunk://oauth/intervals?state=fixture-state&state=fixture-state&code=a"
    ] {
        #expect(throws: OAuthError.invalidCallback) { try attempt.authorizationCode(from: URL(string: url)!) }
    }
    #expect(throws: OAuthError.denied) {
        try attempt.authorizationCode(from: URL(string: "ftpunk://oauth/intervals?state=fixture-state&error=access_denied")!)
    }
}

@Test func oauthAttemptsHaveUniqueSecureStateAndBearerAuthorization() throws {
    let configuration = try oauthFixture().configuration
    let a = try IntervalsOAuthAttempt(configuration: configuration), b = try IntervalsOAuthAttempt(configuration: configuration)
    #expect(a.state != b.state); #expect(a.verifier != b.verifier); #expect(a.verifier.count >= 43)
    let connection = IntervalsConnection(athleteID: "i1", athleteName: "Rider", accessToken: "fixture-token")
    let job = ActivityUploadJob(sessionID: UUID(), accountID: "i1", file: Data(), name: "Test", description: "")
    #expect(IntervalsClient.uploadRequest(job, credential: connection.authorizationHeader).value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
    let legacy = Data(#"{"athleteID":"i1","athleteName":"Rider","apiKey":"fixture-key"}"#.utf8)
    let migrated = try JSONDecoder().decode(IntervalsConnection.self, from: legacy)
    #expect(!migrated.usesOAuth)
    #expect(migrated.authorizationHeader == "Basic " + Data("API_KEY:fixture-key".utf8).base64EncodedString())
}

private final class OAuthFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let revoking = request.httpMethod == "DELETE"
        let authorized = !revoking || request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token"
        let response = HTTPURLResponse(url: request.url!, statusCode: authorized ? (revoking ? 204 : 200) : 401,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !revoking {
            let data = Data(#"{"token_type":"Bearer","access_token":"fixture-token","scope":"ACTIVITY:WRITE","athlete":{"id":"12345","name":"Fixture Rider"}}"#.utf8)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func oauthExchangesDocumentedResponseAndRevokesBearerToken() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OAuthFixtureProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = IntervalsClient(session: session)
    let connection = try await client.exchange(oauthFixture(), code: "fixture-code")
    #expect(connection.athleteID == "12345")
    #expect(connection.athleteName == "Fixture Rider")
    #expect(connection.usesOAuth)
    #expect(connection.authorizationHeader == "Bearer fixture-token")
    try await client.revoke(connection)
}
