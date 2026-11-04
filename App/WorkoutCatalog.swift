import Foundation
import Observation
import FTPunkDomain
import FTPunkStorage
import FTPunkIntegrations

/// The offline workout library: imported files, the Intervals.icu calendar cache and its refresh state.
/// The built-in classics live in `FTPunkDomain` (`WorkoutLibrary`).
@MainActor @Observable final class WorkoutCatalog {
    /// What a download or import needs to know about the app right now.
    struct Context {
        var riderID: UUID
        var ftp: Double?
        var connection: IntervalsConnection?
        var isBusy: Bool
    }

    private let store: LocalStore
    private let persistTimes: Bool
    private(set) var cached: [CachedWorkout] = []
    private(set) var downloading = false
    var report: String?
    /// Quiet status for automatic refreshes, shown beside the calendar rather than as an alert.
    var syncMessage: String?
    @ObservationIgnored private var lastDownloads: [String: Date] = [:]

    init(store: LocalStore, persistTimes: Bool) {
        self.store = store; self.persistTimes = persistTimes
    }

    func reload() throws { cached = try store.workouts() }

    func lastDownload(for accountID: String?) -> Date? {
        guard let accountID else { return nil }
        if let date = lastDownloads[accountID] { return date }
        guard persistTimes, let seconds = UserDefaults.standard.object(forKey: "workoutsDownloadedAt.\(accountID)") as? Double else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
    private func recordDownload(for accountID: String, at date: Date) {
        lastDownloads[accountID] = date
        if persistTimes { UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "workoutsDownloadedAt.\(accountID)") }
    }

    @discardableResult func importWorkout(_ data: Data, context: Context) throws -> TrainingPlan {
        // A ZWO file is XML and starts with "<"; the JSON formats start with "{".
        let isZWO = data.first(where: { !" \n\r\t".utf8.contains($0) && $0 != 0xEF && $0 != 0xBB && $0 != 0xBF }) == UInt8(ascii: "<")
        let plan = isZWO ? try ZWOImport.parse(data, ftp: context.ftp) : try WorkoutImport.parse(data, ftp: context.ftp)
        try store.saveWorkouts([CachedWorkout(riderID: context.riderID, source: isZWO ? "Imported ZWO" : "Imported JSON", plan: plan)])
        try reload()
        report = "Saved \(plan.name) for offline riding. Targets are fixed in watts."
        return plan
    }

    func delete(_ workout: CachedWorkout) throws {
        try store.deleteWorkout(id: workout.id); try reload()
    }

    /// Downloads the next 14 days. Returns an error message for the caller to show unless `quiet`.
    func download(context current: @MainActor () -> Context, quiet: Bool, now: Date = Date()) async -> String? {
        let context = current()
        guard !context.isBusy, !downloading, let connection = context.connection else { return nil }
        downloading = true; defer { downloading = false }
        let today = ScheduledDate.string(for: now)
        let end = ScheduledDate.string(for: Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now)
        do {
            let result = try await AppInfo.intervalsClient.workouts(connection: connection, riderID: context.riderID, ftp: context.ftp, oldest: today, newest: end)
            let after = current()
            guard after.connection?.authorizationHeader == connection.authorizationHeader, after.riderID == context.riderID, !after.isBusy else {
                throw ArchiveError.invalid("The rider, ride or account changed. Download again.")
            }
            try store.saveWorkouts(result.workouts)
            // Calendar entries inside the window that were removed or moved are not kept as phantom workouts.
            let stale = TodayWorkouts.stale(cached: try store.workouts(), riderID: context.riderID, accountID: connection.athleteID,
                                            downloaded: Set(result.workouts.map(\.id)), today: today, windowEnd: end)
            for id in stale { try store.deleteWorkout(id: id) }
            try reload()
            recordDownload(for: connection.athleteID, at: now)
            syncMessage = nil
            report = "Saved \(result.workouts.count) workouts for offline use." + (result.skipped.isEmpty ? "" : "\nSkipped:\n" + result.skipped.prefix(20).joined(separator: "\n"))
            return nil
        } catch {
            if quiet { syncMessage = "Couldn’t refresh Intervals.icu workouts: \(error.localizedDescription)"; return nil }
            return error.localizedDescription
        }
    }
}
