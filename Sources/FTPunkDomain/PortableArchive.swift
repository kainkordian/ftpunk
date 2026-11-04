import Foundation

/// Versioned activity boundary. The ramp payload remains unchanged so its history
/// and analysis retain their original meaning as more activity kinds are added.
public struct ActivityRecord: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case rampTest, workout, freeRide }
    public let schemaVersion: Int
    public let kind: Kind
    public var session: TestSession
    public init(session: TestSession) { schemaVersion = 1; kind = session.training.map { $0.kind == .workout ? .workout : .freeRide } ?? .rampTest; self.session = session }
}

public struct PortableArchive: Codable, Sendable {
    public static let maximumBytes = 64 * 1024 * 1024
    public let format: String
    public let version: Int
    public let exportedAt: Date
    public var workouts: [CachedWorkout]?
    /// The riders' own workouts (native only for now). Older readers ignore the key.
    public var customWorkouts: [CustomWorkout]?
    public var profiles: [RiderProfile]
    public var activities: [ActivityRecord]

    public init(profiles: [RiderProfile], sessions: [TestSession], date: Date = Date(), workouts: [CachedWorkout] = [], customWorkouts: [CustomWorkout] = []) {
        self.workouts = workouts.isEmpty ? nil : workouts
        self.customWorkouts = customWorkouts.isEmpty ? nil : customWorkouts
        format = "ftpunk-portable"; version = !workouts.isEmpty || !customWorkouts.isEmpty || sessions.contains(where: { ($0.training?.version ?? 1) >= 2 || $0.adventureStartMilliseconds != nil }) ? 3 : sessions.contains(where: { $0.training != nil || $0.adventureEnabled == true }) || profiles.contains(where: { $0.cycleProgress != nil }) ? 2 : 1; exportedAt = date
        self.profiles = profiles; activities = sessions.map(ActivityRecord.init)
    }
    public func validate() throws {
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition { throw ArchiveError.invalid(reason) }
        }
        try require(format == "ftpunk-portable" && (1...3).contains(version), "This archive format or version is not supported.")
        try require(!profiles.isEmpty && profiles.count <= 1000 && activities.count <= 100000, "The archive has an invalid number of riders or activities.")
        let riderIDs = Set(profiles.map(\.id))
        try require(riderIDs.count == profiles.count, "Duplicate rider identities in archive.")
        try require(Set(activities.map { $0.session.id }).count == activities.count, "Duplicate activity identities in archive.")
        let library = workouts ?? []
        try require(version >= 3 || library.isEmpty, "Workout libraries require archive version 3.")
        try require(library.count <= 2000 && Set(library.map(\.id)).count == library.count, "Invalid workout library identities.")
        for workout in library { try workout.validate(); try require(riderIDs.contains(workout.riderID), "A workout references a missing rider.") }
        let custom = customWorkouts ?? []
        try require(version >= 3 || custom.isEmpty, "Custom workouts require archive version 3.")
        try require(custom.count <= 2000 && Set(custom.map(\.id)).count == custom.count, "Invalid custom workout identities.")
        for workout in custom { try workout.validate(); try require(riderIDs.contains(workout.riderID), "A custom workout references a missing rider.") }
        try require(Dictionary(grouping: custom, by: \.riderID).values.allSatisfy { $0.count <= CustomWorkout.maximumPerRider }, "Too many custom workouts for one rider.")
        for profile in profiles {
            try profile.cycleProgress?.validate()
            try require(version >= 2 || profile.cycleProgress == nil, "Legacy story progress requires archive version 2.")
            try require(!profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && profile.name.count <= 80, "Invalid rider name.")
            try require(profile.weightKG.map { $0.isFinite && $0 > 0 } ?? true, "Invalid rider weight.")
            let entries = Set(profile.ftpHistory.map(\.id))
            try require(entries.count == profile.ftpHistory.count, "Duplicate FTP history identities.")
            try require(profile.currentFTPID.map { entries.contains($0) } ?? true, "The current FTP entry is missing.")
            try require(profile.ftpHistory.allSatisfy { $0.watts.isFinite && $0.watts > 0 && $0.watts <= 32767 }, "Invalid FTP history.")
        }
        for activity in activities {
            let session = activity.session, c = session.configuration
            try session.training?.validate()
            try require(version >= 3 || (session.training?.version ?? 1) == 1, "Ramp and resistance plans require archive version 3.")
            try require(activity.kind == (session.training.map { $0.kind == .workout ? .workout : .freeRide } ?? .rampTest), "Activity kind does not match its plan.")
            try require(version >= 2 || (session.training == nil && session.adventureEnabled != true), "Training and legacy story data require archive version 2.")
            try require(session.training == nil || session.result == nil, "Training activities cannot contain FTP estimates.")
            try require(session.adventureStartMilliseconds.map { version >= 3 && $0 >= 0 && $0 <= 8640000000000 } ?? true, "Invalid legacy story starting point.")
            try require(activity.schemaVersion == 1, "This activity version is not supported.")
            try require(riderIDs.contains(session.riderID), "An activity references a missing rider.")
            guard let end = session.endedAtOffset, end.isFinite, end >= 0, session.outcome != nil else {
                throw ArchiveError.invalid("Finish or recover all activities before transferring them.")
            }
            try require(session.eligibleMilliseconds.map { $0 >= 0 && Double($0) <= min(86400000, (end + 0.001) * 1000) } ?? true, "Invalid legacy story time.")
            try require(c.protocolVersion >= 1 && c.protocolVersion <= 3, "This test protocol version is not supported.")
            try require(c.warmupPower > 0 && c.warmupPower <= 32767 && c.maximumPower >= c.preset.startingPower && c.maximumPower <= 32767, "Invalid power targets.")
            try require([c.warmupSeconds, c.cooldownSeconds].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 3600 }, "Invalid phase duration.")
            try require(c.maximumRampSeconds.isFinite && c.maximumRampSeconds >= 60 && [0.72, 0.75].contains(c.ftpFactor), "Invalid ramp configuration.")
            try require(c.weightKG.map { $0.isFinite && $0 > 0 } ?? true, "Invalid session weight.")
            try require(c.priorFTP.map { $0.watts.isFinite && $0.watts > 0 && $0.watts <= 32767 } ?? true, "Invalid prior FTP.")
            try require([session.rampStart, session.rampEnd, session.cooldownStart].allSatisfy { $0.map { $0.isFinite && $0 >= 0 && $0 <= end } ?? true }, "Invalid activity phase timestamps.")
            if let result = session.result {
                try require(session.outcome?.allowsEstimate == true && result.algorithmVersion == 1 && result.bestMinutePower.isFinite && result.bestMinutePower > 0 && result.windowStart >= 0 && result.windowEnd <= end && abs(result.windowEnd - result.windowStart - 60) < 0.001 && [0.72, 0.75].contains(result.factor), "Invalid FTP result.")
                try require(result.weightKG.map { $0.isFinite && $0 > 0 } ?? true, "Invalid result weight.")
            }
            try require(session.samples.count <= 2_000_000, "The activity contains too many samples.")
            for sample in session.samples {
                try require(sample.time.isFinite && sample.time >= 0 && sample.time <= end + 2, "Invalid sample timestamp.")
                try require([sample.power, sample.trainerPower, sample.cadence].allSatisfy { $0.map(\.isFinite) ?? true }, "Invalid measurement.")
                try require(sample.heartRate.map { $0 >= 0 && $0 <= 65535 } ?? true, "Invalid heart rate.")
            }
            try require(session.events.allSatisfy { $0.time.isFinite && $0.time >= 0 && $0.time <= end + 2 }, "Invalid event timestamp.")
        }
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer(); try container.encode(formatter.string(from: date))
        }
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ArchiveError.invalid("The archive exceeds 64 MB. Export fewer riders or recordings.") }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ArchiveError.invalid("The archive exceeds the 64 MB import limit.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw ArchiveError.invalid("An archive date is not an ISO-8601 timestamp.")
            }
            return date
        }
        let archive = try decoder.decode(Self.self, from: data)
        try archive.validate(); return archive
    }
}

public enum ArchiveError: Error, LocalizedError {
    case invalid(String), identityConflict
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .identityConflict: "An imported activity belongs to a different local rider. Nothing was changed."
        }
    }
}
