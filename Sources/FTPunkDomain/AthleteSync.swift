import Foundation

/// FTP and weight as Intervals.icu reports them. Nil means missing or out of range.
public struct IntervalsAthleteSettings: Equatable, Sendable {
    public let weightKG: Double?
    public let ftpWatts: Double?
    public init(weightKG: Double?, ftpWatts: Double?) {
        self.weightKG = weightKG; self.ftpWatts = ftpWatts
    }
    public static let weightRange: ClosedRange<Double> = 30...250
    public static let ftpRange: ClosedRange<Double> = 50...1000

    /// Lenient decoding of `GET /api/v1/athlete/0`. Missing, zero, non-numeric or out-of-range values become nil.
    /// The field names (`icu_weight`, `sportSettings[].types / ftp / indoor_ftp`) were verified against a live
    /// `GET /api/v1/athlete/0` response on 2026-11-04. Other keys in that response are ignored.
    public static func decode(_ json: [String: Any]) -> IntervalsAthleteSettings {
        func number(_ value: Any?) -> Double? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        let weight = number(json["icu_weight"]).flatMap { weightRange.contains($0) ? $0 : nil }
        let sports = (json["sportSettings"] as? [[String: Any]]) ?? []
        func entry(containing type: String) -> [String: Any]? {
            sports.first { ($0["types"] as? [Any])?.contains { ($0 as? String) == type } == true }
        }
        var ftp: Double?
        for type in ["VirtualRide", "Ride"] {
            guard let settings = entry(containing: type) else { continue }
            let candidates = [number(settings["indoor_ftp"]), number(settings["ftp"])]
            if let value = candidates.compactMap({ $0 }).first(where: { ftpRange.contains($0) }) { ftp = value; break }
        }
        return IntervalsAthleteSettings(weightKG: weight, ftpWatts: ftp)
    }
}

/// What was last seen on Intervals.icu, per account. A remote value is only applied when it differs from this.
public struct AthleteSyncState: Codable, Equatable, Sendable {
    public var lastSeenFTP: Double?
    public var lastSeenWeight: Double?
    public init(lastSeenFTP: Double? = nil, lastSeenWeight: Double? = nil) {
        self.lastSeenFTP = lastSeenFTP; self.lastSeenWeight = lastSeenWeight
    }
}

/// Per-rider sync choices (the rider who owns the connection is the rider that syncs), persisted by the app (outside the Keychain blob, so old connections still decode).
public struct AthleteSyncSettings: Codable, Equatable, Sendable {
    public var enabled = true
    /// Only read once, by the migration from account-wide settings; the connection's owner is the linked rider now.
    public var linkedRiderID: UUID?
    public var lastSynced: Date?
    public var state = AthleteSyncState()
    public init(enabled: Bool = true, linkedRiderID: UUID? = nil, lastSynced: Date? = nil, state: AthleteSyncState = AthleteSyncState()) {
        self.enabled = enabled; self.linkedRiderID = linkedRiderID; self.lastSynced = lastSynced; self.state = state
    }
}

public enum AthleteSync {
    public struct Changes: Equatable, Sendable {
        public var ftp: Double?
        public var weight: Double?
        public init(ftp: Double? = nil, weight: Double? = nil) { self.ftp = ftp; self.weight = weight }
        public var isEmpty: Bool { ftp == nil && weight == nil }
    }
    public static let ftpTolerance = 0.5
    public static let weightTolerance = 0.05

    /// A remote value is applied only when it changed on Intervals.icu since the last sync and differs from the rider's
    /// current local value. `lastSeen*` follows the remote either way, so a local edit is never fought over.
    public static func changes(remote: IntervalsAthleteSettings, state: AthleteSyncState, rider: RiderProfile) -> (Changes, AthleteSyncState) {
        var changes = Changes(), next = state
        if let ftp = remote.ftpWatts {
            if state.lastSeenFTP.map({ abs($0 - ftp) > ftpTolerance }) ?? true {
                if rider.currentFTP.map({ abs($0.watts - ftp) > ftpTolerance }) ?? true { changes.ftp = ftp }
                next.lastSeenFTP = ftp
            }
        }
        if let weight = remote.weightKG {
            if state.lastSeenWeight.map({ abs($0 - weight) > weightTolerance }) ?? true {
                if rider.weightKG.map({ abs($0 - weight) > weightTolerance }) ?? true { changes.weight = weight }
                next.lastSeenWeight = weight
            }
        }
        return (changes, next)
    }

    /// The rider whose data syncs: the stored link while that rider still exists, otherwise the one selected now.
    public static func linkedRiderID(stored: UUID?, riders: [RiderProfile], selected: UUID) -> UUID {
        if let stored, riders.contains(where: { $0.id == stored }) { return stored }
        return selected
    }

    /// "FTP 262 W and weight 71.5 kg updated from Intervals.icu".
    public static func note(for changes: Changes) -> String? {
        let ftp = changes.ftp.map { "FTP \(Int($0.rounded())) W" }
        let weight = changes.weight.map { "weight \(String(format: "%.1f", $0)) kg" }
        let parts = [ftp, weight].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " and ") + " updated from Intervals.icu"
    }

    /// The rider with the changes applied: FTP becomes a new current history entry; existing entries are untouched.
    public static func applying(_ changes: Changes, to rider: RiderProfile, date: Date = Date()) -> RiderProfile {
        var rider = rider
        if let ftp = changes.ftp {
            let entry = FTPEntry(watts: ftp, date: date, source: "Intervals.icu")
            rider.ftpHistory.insert(entry, at: 0); rider.currentFTPID = entry.id
        }
        if let weight = changes.weight { rider.weightKG = weight }
        return rider
    }
}
