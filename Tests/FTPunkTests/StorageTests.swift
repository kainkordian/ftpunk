import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing
import FTPunkDomain
@testable import FTPunkStorage
@testable import FTPunkIntegrations

@MainActor @Test func storageCheckpointRecoveryAndHistory() throws {
    let store = try LocalStore(inMemory: true)
    let ftp = FTPEntry(watts: 250)
    try store.saveProfile(RiderProfile(weightKG: 75, ftpHistory: [ftp], currentFTPID: ftp.id))
    var session = TestSession(configuration: try SessionConfiguration(priorFTP: ftp, weightKG: 75))
    session.samples.append(RideSample(time: 0, power: 200))
    try store.save(session)
    session.samples.append(RideSample(time: 1, power: 210))
    try store.save(session); try store.save(session)
    #expect(try store.sessions().first?.samples.count == 2)
    #expect(try store.loadProfile().currentFTP?.watts == 250)
    try store.recoverInterruptedSessions()
    let recovered = try #require(store.sessions().first)
    #expect(recovered.outcome == .interrupted); #expect(recovered.endedAtOffset == 1)
    #expect(recovered.configuration.weightKG == 75)
    try store.deleteSession(id: session.id)
    #expect(try store.sessions().isEmpty)
}

@MainActor @Test func sqliteSurvivesReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.sqlite")
    let session = TestSession(configuration: try SessionConfiguration(weightKG: 72.5))
    do { let store = try LocalStore(url: url); try store.save(session) }
    let reopened = try LocalStore(url: url)
    #expect(try reopened.sessions().first?.id == session.id)
    #expect(try reopened.sessions().first?.configuration.weightKG == 72.5)
}

@Test func tcxExportIsWellFormedAndKeepsMeasuredStreams() throws {
    var session = TestSession(configuration: try SessionConfiguration(weightKG: 75))
    session.rampStart = 1; session.rampEnd = 61; session.endedAtOffset = 62; session.outcome = .finishedEarly
    session.samples = [RideSample(time: 0, power: 100, cadence: 90), RideSample(time: 2, power: 200, heartRate: 150), RideSample(time: 61.5, cadence: 80)]
    let data = try ActivityExport.tcx(session)
    #expect(XMLParser(data: data).parse())
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("<ns3:Watts>200</ns3:Watts>"))
    #expect(text.components(separatedBy: "<ns3:Watts>").count == 3)
    #expect(!text.contains("<Position>"))
    #expect(text.components(separatedBy: "<Lap ").count == 4)
}

private actor RecordingUploader: ActivityUploader {
    private(set) var files: [Data] = []
    func upload(_ job: ActivityUploadJob, credential: String) async throws -> [String] {
        files.append(job.file); return ["i123"]
    }
}

@MainActor @Test func queueSavesOnceAndExcludesDemo() async throws {
    let store = try LocalStore(inMemory: true), uploader = RecordingUploader()
    let worker = UploadWorker(repository: store, uploader: uploader)
    let connection = IntervalsConnection(athleteID: "i1", athleteName: "Rider", apiKey: "test-secret")
    var session = TestSession(configuration: try SessionConfiguration())
    session.samples = [RideSample(time: 0, power: 200)]; session.endedAtOffset = 1; session.outcome = .finishedEarly
    try worker.enqueue(session, connection: connection); try worker.enqueue(session, connection: connection)
    #expect(try store.uploadJobs().count == 1)
    await #expect(throws: Never.self) { try await worker.run(connection: connection) }
    #expect(try store.uploadJobs().first?.status == .uploaded)
    #expect(await uploader.files.count == 1)
    session.id = UUID(); session.isDemo = true
    try worker.enqueue(session, connection: connection)
    #expect(try store.uploadJobs().count == 1)
}

@Test func uploadRequestContainsStableFileAndCorrelationID() {
    let job = ActivityUploadJob(sessionID: UUID(), accountID: "i1", file: Data("<test/>".utf8), name: "FTP & ramp", description: "A test")
    let a = IntervalsClient.uploadRequest(job, credential: "test"), b = IntervalsClient.uploadRequest(job, credential: "test")
    #expect(a.httpBody == b.httpBody)
    #expect(a.httpMethod == "POST")
    #expect(a.url?.query?.contains("external_id=ftpunk-") == true)
    #expect(String(decoding: a.httpBody ?? Data(), as: UTF8.self).contains("<test/>"))
}

private actor TimeoutThenSuccess: ActivityUploader {
    private(set) var files: [Data] = []
    func upload(_ job: ActivityUploadJob, credential: String) async throws -> [String] {
        files.append(job.file)
        if files.count == 1 { throw URLError(.timedOut) }
        return ["i456"]
    }
}

@MainActor @Test func retryKeepsFileAndAccountAndHonorsCancellation() async throws {
    let store = try LocalStore(inMemory: true), uploader = TimeoutThenSuccess()
    let worker = UploadWorker(repository: store, uploader: uploader)
    let owner = IntervalsConnection(athleteID: "i1", athleteName: "Rider", apiKey: "test")
    let other = IntervalsConnection(athleteID: "i2", athleteName: "Other", apiKey: "test")
    var session = TestSession(configuration: try SessionConfiguration())
    session.samples = [RideSample(time: 0, power: 200)]; session.endedAtOffset = 1
    try worker.enqueue(session, connection: owner)
    try await worker.run(connection: other)
    #expect(await uploader.files.isEmpty)
    let now = Date()
    try await worker.run(connection: owner, now: now)
    let failed = try #require(store.uploadJobs().first)
    #expect(failed.status == .queued); #expect(failed.nextAttemptAt > now)
    try await worker.run(connection: owner, now: now)
    #expect(await uploader.files.count == 1)
    try worker.retryPending(accountID: owner.athleteID)
    try await worker.run(connection: owner, now: now)
    let files = await uploader.files
    #expect(files.count == 2); #expect(files[0] == files[1])
    #expect(try store.uploadJobs().first?.status == .uploaded)
    session.id = UUID()
    try worker.enqueue(session, connection: owner, automatic: true)
    try worker.cancelAutomaticUploads(accountID: owner.athleteID)
    #expect(try store.uploadJobs().count == 1)
}
