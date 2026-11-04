import Foundation

/// What Home shows for planned Intervals.icu workouts.
public enum TodayWorkouts {
    public enum Selection: Equatable, Sendable {
        case today([String])
        case nothingToday(next: String?)
        case notConnected
    }

    /// Workouts of the selected rider that come from the calendar.
    private static func calendar(_ workouts: [CachedWorkout], riderID: UUID) -> [CachedWorkout] {
        workouts.filter { $0.riderID == riderID && $0.isFromIntervals }
    }

    /// Today's workouts, shown even offline. Otherwise connected riders see the next planned
    /// workout, and riders who are not connected see a single quiet hint.
    public static func select(_ workouts: [CachedWorkout], riderID: UUID, today: String, connected: Bool) -> Selection {
        let planned = calendar(workouts, riderID: riderID)
        let todays = planned.filter { $0.scheduledDate == today }.map(\.id)
        if !todays.isEmpty { return .today(todays) }
        if !connected { return .notConnected }
        return .nothingToday(next: upcoming(workouts, riderID: riderID, today: today).first(where: { $0.scheduledDate != nil })?.id)
    }

    /// After today, in date order; entries without a date (older caches) follow.
    public static func upcoming(_ workouts: [CachedWorkout], riderID: UUID, today: String) -> [CachedWorkout] {
        let planned = calendar(workouts, riderID: riderID).filter { $0.scheduledDate.map { $0 > today } ?? true }
        return planned.sorted {
            switch ($0.scheduledDate, $1.scheduledDate) {
            case let (a?, b?): a == b ? $0.id < $1.id : a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.id < $1.id
            }
        }
    }

    /// Imported files; the calendar and the built-in classics have their own sections.
    public static func mine(_ workouts: [CachedWorkout], riderID: UUID) -> [CachedWorkout] {
        workouts.filter { $0.riderID == riderID && !$0.isFromIntervals }.sorted { $0.savedAt > $1.savedAt }
    }

    /// Cached calendar entries inside the downloaded window that the latest download no longer returned.
    public static func stale(cached: [CachedWorkout], riderID: UUID, accountID: String, downloaded: Set<String>, today: String, windowEnd: String) -> [String] {
        let prefix = "intervals:\(accountID):\(riderID.uuidString.lowercased()):"
        return cached.filter { $0.id.hasPrefix(prefix) && !downloaded.contains($0.id)
            && ($0.scheduledDate.map { $0 >= today && $0 <= windowEnd } ?? true) }.map(\.id)
    }
}

/// The calendar refreshes when Home appears if the last download is over an hour old, never during a ride.
public enum SyncPolicy {
    public static let refreshInterval: TimeInterval = 3600
    public static func shouldRefresh(lastDownload: Date?, now: Date = Date(), connected: Bool, rideActive: Bool, alreadyRunning: Bool = false) -> Bool {
        guard connected, !rideActive, !alreadyRunning else { return false }
        guard let lastDownload else { return true }
        return now.timeIntervalSince(lastDownload) > refreshInterval
    }
}
