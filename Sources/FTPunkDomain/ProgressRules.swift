import Foundation

public enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case watts = "FTP, W", wattsPerKG = "FTP, W/kg"
    public var id: String { rawValue }
    public func value(_ session: TestSession) -> Double? {
        self == .watts ? session.result?.estimatedFTP : session.result?.wattsPerKG
    }
}

public enum ActivityFilter: String, CaseIterable, Identifiable, Sendable {
    case all, ftpTests, workouts, freeRides
    public var id: String { rawValue }
    public var title: String {
        switch self { case .all: "All"; case .ftpTests: "FTP tests"; case .workouts: "Workouts"; case .freeRides: "Free rides" }
    }
    public func matches(_ session: TestSession) -> Bool {
        switch self {
        case .all: true
        case .ftpTests: session.training == nil
        case .workouts: session.training?.kind == .workout
        case .freeRides: session.training?.kind == .freeRide
        }
    }
}

public enum ActivityBadge: String, Equatable, Sendable {
    case debug = "Debug", uploaded = "Uploaded", uploadQueued = "Upload queued", uploadFailed = "Upload needs attention", interrupted = "Interrupted"
}

/// One row of the activity list: date and activity as the title, a result value, and badges.
public struct ActivityRowModel: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let value: String?
    public let badges: [ActivityBadge]

    public static func make(_ session: TestSession, uploadStatus: UploadStatus?, showRider: Bool = true) -> ActivityRowModel {
        let date = session.startedAt.formatted(.dateTime.day().month(.abbreviated))
        let activity = session.training == nil ? "FTP test" : session.activityTitle
        let length = DurationFormat.compact(session.endedAtOffset ?? session.samples.last?.time ?? 0)
        let value: String?
        if let result = session.result { value = "\(Int(result.estimatedFTP.rounded())) W" }
        else if session.training != nil { value = length }
        else { value = nil }
        var badges: [ActivityBadge] = []
        if session.isDemo { badges.append(.debug) }
        if session.outcome == .interrupted { badges.append(.interrupted) }
        switch uploadStatus {
        case .uploaded: badges.append(.uploaded)
        case .queued, .uploading: badges.append(.uploadQueued)
        case .needsAttention: badges.append(.uploadFailed)
        case nil: break
        }
        let detail = session.training == nil ? (session.outcome?.title ?? "Recording") : length
        return ActivityRowModel(id: session.id, title: "\(date) · \(activity)",
                                subtitle: showRider ? "\(session.riderName) · \(detail)" : detail, value: value, badges: badges)
    }
}

public enum ProgressRules {
    /// Sessions that appear in the FTP trend: real results by default, debug results on request.
    public static func trendSessions(_ sessions: [TestSession], rider: UUID?, metric: TrendMetric, includeDebug: Bool) -> [TestSession] {
        sessions.filter { (rider == nil || $0.riderID == rider) && metric.value($0) != nil && (includeDebug || !$0.isDemo) }
    }
    /// Newest first, for the selected rider (or everyone) and activity type.
    public static func activities(_ sessions: [TestSession], rider: UUID?, filter: ActivityFilter) -> [TestSession] {
        sessions.filter { (rider == nil || $0.riderID == rider) && filter.matches($0) }.sorted { $0.startedAt > $1.startedAt }
    }
}
