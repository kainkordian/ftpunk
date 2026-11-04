import Foundation
import FTPunkDomain
import FTPunkStorage

@MainActor public final class UploadWorker {
    private let repository: any UploadQueueRepository
    private let uploader: any ActivityUploader
    private var running = false
    public var isRunning: Bool { running }
    public init(repository: any UploadQueueRepository, uploader: any ActivityUploader = IntervalsClient()) {
        self.repository = repository; self.uploader = uploader
    }
    public func enqueue(_ session: TestSession, connection: IntervalsConnection, automatic: Bool = false) throws {
        guard !session.isDemo else { return }
        guard try !repository.uploadJobs().contains(where: { $0.sessionID == session.id && $0.accountID == connection.athleteID }) else { return }
        var job = ActivityUploadJob(
            sessionID: session.id, accountID: connection.athleteID, file: try ActivityExport.tcx(session),
            name: "FTPunk · \(session.riderName) · \(session.outcome?.title ?? "Activity")", description: ActivityExport.description(session)
        )
        job.automaticallyQueued = automatic
        try repository.saveUploadJob(job)
    }
    public func retryPending(accountID: String) throws {
        for var job in try repository.uploadJobs() where job.accountID == accountID && job.status != .uploaded && job.status != .uploading {
            job.status = .queued; job.nextAttemptAt = .distantPast; try repository.saveUploadJob(job)
        }
    }
    public func cancelAutomaticUploads(accountID: String) throws {
        for job in try repository.uploadJobs() where job.accountID == accountID && job.automaticallyQueued && job.status != .uploaded {
            try repository.deleteUploadJob(id: job.id)
        }
    }
    public func run(connection: IntervalsConnection, now: Date = Date()) async throws {
        guard !running else { return }; running = true; defer { running = false }
        for var job in try repository.uploadJobs() where job.accountID == connection.athleteID && job.status == .queued && job.nextAttemptAt <= now {
            // Re-read to honor a disconnect/delete while an earlier network call was suspended.
            guard try repository.uploadJobs().contains(where: { $0.id == job.id }) else { continue }
            job.status = .uploading; job.attempts += 1; try repository.saveUploadJob(job)
            do {
                let ids = try await uploader.upload(job, credential: connection.authorizationHeader)
                guard try repository.uploadJobs().contains(where: { $0.id == job.id }) else { continue }
                job.remoteIDs = ids; job.status = .uploaded; job.lastError = nil
            } catch {
                guard try repository.uploadJobs().contains(where: { $0.id == job.id }) else { continue }
                job.lastError = error.localizedDescription
                if let apiError = error as? IntervalsError {
                    if let delay = apiError.retryDelay {
                        job.status = .queued; job.nextAttemptAt = now.addingTimeInterval(delay)
                    } else { job.status = .needsAttention }
                } else {
                    job.status = .queued
                    job.nextAttemptAt = now.addingTimeInterval(min(3600, pow(2, Double(min(job.attempts, 10))) * 15))
                }
            }
            try repository.saveUploadJob(job)
        }
    }
}
