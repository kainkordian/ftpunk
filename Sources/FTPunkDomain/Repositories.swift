import Foundation

@MainActor public protocol SessionRepository {
    func save(_ session: TestSession) throws
    func sessions() throws -> [TestSession]
    func deleteSession(id: UUID) throws
}

@MainActor public protocol ProfileRepository {
    func loadProfile() throws -> RiderProfile
    func saveProfile(_ profile: RiderProfile) throws
    func profiles() throws -> [RiderProfile]
}

public enum UploadStatus: String, Codable, Sendable { case queued, uploading, uploaded, needsAttention }

/// The file name and media type of an upload, read from the bytes: jobs queued before uploads moved to FIT still hold TCX.
public struct ActivityUploadFile: Equatable, Sendable {
    public let name: String
    public let mediaType: String

    public static func make(sessionID: UUID, bytes: Data) -> ActivityUploadFile {
        if bytes.count >= 12, bytes.dropFirst(8).prefix(4).elementsEqual(Array(".FIT".utf8)) {
            return ActivityUploadFile(name: "\(sessionID.uuidString).fit", mediaType: "application/octet-stream")
        }
        return ActivityUploadFile(name: "\(sessionID.uuidString).tcx", mediaType: "application/vnd.garmin.tcx+xml")
    }
}

public struct ActivityUploadJob: Identifiable, Codable, Sendable {
    public var id: UUID
    public var sessionID: UUID
    public var accountID: String
    public var file: Data
    public var name: String
    public var description: String
    public var status: UploadStatus = .queued
    public var automaticallyQueued: Bool = false
    public var attempts: Int = 0
    public var lastError: String?
    public var remoteIDs: [String] = []
    public var nextAttemptAt: Date = .distantPast
    public init(sessionID: UUID, accountID: String, file: Data, name: String, description: String) {
        id = UUID(); self.sessionID = sessionID; self.accountID = accountID
        self.file = file; self.name = name; self.description = description
    }
}

@MainActor public protocol UploadQueueRepository {
    func uploadJobs() throws -> [ActivityUploadJob]
    func saveUploadJob(_ job: ActivityUploadJob) throws
    func deleteUploadJob(id: UUID) throws
    func deleteUploadJobs(accountID: String) throws
}

public protocol ActivityUploader: Sendable {
    func upload(_ job: ActivityUploadJob, credential: String) async throws -> [String]
}
