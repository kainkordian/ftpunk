import Foundation
import CoreFoundation

public struct CachedWorkout: Codable, Identifiable, Sendable {
    public let id: String
    public let riderID: UUID
    public let source: String
    public let savedAt: Date
    public let plan: TrainingPlan
    /// Local `yyyy-MM-dd` from an Intervals.icu event's `start_date_local`. Absent in older caches and
    /// archives, and for imported files; those appear without a date until the next download.
    public let scheduledDate: String?
    public init(id: String = UUID().uuidString.lowercased(), riderID: UUID, source: String, plan: TrainingPlan, date: Date = Date(), scheduledDate: String? = nil) {
        self.id = id; self.riderID = riderID; self.source = source; self.plan = plan; savedAt = date; self.scheduledDate = scheduledDate
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 300, !source.isEmpty, source.count <= 300, plan.kind == .workout,
              scheduledDate.map(ScheduledDate.isValid) ?? true else { throw ArchiveError.invalid("Invalid cached workout.") }
        try plan.validate()
    }
    public var isFromIntervals: Bool { id.hasPrefix("intervals:") }
}

/// Calendar days travel as local `yyyy-MM-dd` text, never as instants, so a workout planned for
/// Tuesday stays on Tuesday in any time zone.
public enum ScheduledDate {
    public static func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year >= 1970, year <= 2200 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        return components.isValidDate(in: calendar) && calendar.dateComponents([.year, .month, .day], from: components.date!) == DateComponents(year: year, month: month, day: day)
    }
    /// "2026-11-02T06:30:00" (Intervals `start_date_local`) → "2026-11-02".
    public static func from(intervalsLocal text: String?) -> String? {
        guard let text, text.count >= 10 else { return nil }
        let day = String(text.prefix(10))
        return isValid(day) ? day : nil
    }
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
    public static func date(from text: String, calendar: Calendar = .current) -> Date? {
        guard isValid(text) else { return nil }
        let p = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

/// Deliberately supports only timed power workouts. Unsupported targets never
/// turn into guessed watts. Expansion and input limits bound untrusted JSON.
public enum WorkoutImport {
    public static let exampleJSON = #"{"format":"ftpunk-workout","version":1,"name":"Ramps and repeats · 12 min","ftpWatts":200,"steps":[{"name":"Warm-up ramp","seconds":180,"watts":80,"endWatts":120},{"repeat":3,"steps":[{"name":"Effort","seconds":90,"watts":160},{"name":"Recover","seconds":30,"watts":90}]},{"name":"Cooldown ramp","seconds":180,"watts":100,"endWatts":60}]}"#
    public static let maximumBytes = 2 * 1024 * 1024
    public static func parse(_ data: Data, ftp: Double? = nil) throws -> TrainingPlan {
        guard data.count <= maximumBytes else { throw ArchiveError.invalid("Workout files must be under 2 MB.") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ArchiveError.invalid("Choose one workout JSON object.") }
        if object["format"] as? String == "ftpunk-workout" {
            guard number(object["version"]) == 1 else { throw ArchiveError.invalid("Unsupported workout file version.") }
            if let value = object["ftpWatts"], !(value is NSNull), number(value) == nil { throw ArchiveError.invalid("Invalid workout FTP.") }
            return try build(object, document: object, ftp: number(object["ftpWatts"]) ?? ftp, native: true)
        }
        guard let doc = object["workout_doc"] as? [String: Any],
              object["type"] as? String == "Ride", object["category"] as? String == "WORKOUT" else {
            throw ArchiveError.invalid("Use FTPunk workout JSON or an Intervals.icu cycling workout event.")
        }
        if let value = doc["ftp"], !(value is NSNull), number(value) == nil { throw ArchiveError.invalid("Invalid workout FTP.") }
        return try build(object, document: doc, ftp: number(doc["ftp"]) ?? ftp, native: false)
    }
    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private static func build(_ object: [String: Any], document: [String: Any], ftp: Double?, native: Bool) throws -> TrainingPlan {
        func invalid(_ message: String) -> ArchiveError { .invalid(message) }
        let name = object["name"] as? String ?? "Imported workout"
        if let target = document["target"] as? String, !["POWER", "W", "AUTO", "A"].contains(target) { throw invalid("Only timed power workouts are supported.") }
        guard let input = document["steps"] as? [[String: Any]], !input.isEmpty else { throw invalid("The workout contains no steps.") }
        var steps: [TrainingPlan.Step] = []
        func expand(_ list: [[String: Any]], depth: Int) throws {
            guard depth <= 4, list.count <= 500 else { throw invalid("Workout repeats are too deeply nested or too large.") }
            for item in list {
                if let children = item["steps"] as? [[String: Any]] {
                    guard let count = number(item[native ? "repeat" : "reps"]), count >= 1, count <= 100, count.rounded() == count, !children.isEmpty else { throw invalid("Invalid repeat count.") }
                    for _ in 0..<Int(count) { try expand(children, depth: depth + 1) }
                    continue
                }
                guard steps.count < 500, !["freeride", "maxeffort", "until_lap_press"].contains(where: { item[$0] as? Bool == true }), item["distance"] == nil, item["repeat"] == nil, item["reps"] == nil,
                      let seconds = number(item[native ? "seconds" : "duration"]), seconds > 0, seconds <= 86400 else { throw invalid("Every step must have a timed power target; free, distance and lap steps are unsupported.") }
                var from: Double?, to: Double?
                if native { from = number(item["watts"]); to = number(item["endWatts"]) }
                else {
                    let resolved = item["_power"] as? [String: Any]
                    let power = resolved ?? (item["power"] as? [String: Any]) ?? [:]
                    let units = power["units"] as? String ?? (resolved == nil ? "" : "w")
                    let multiplier: Double
                    if resolved != nil || ["w", "watts"].contains(units.lowercased()) { multiplier = 1 }
                    else if units.lowercased() == "%ftp", let ftp, ftp.isFinite, ftp > 0, ftp <= 32767 { multiplier = ftp / 100 }
                    else { throw invalid("This workout needs resolved watts or a valid FTP for percent targets.") }
                    if item["ramp"] as? Bool == true {
                        from = number(power["start"]).map { $0 * multiplier }; to = number(power["end"]).map { $0 * multiplier }
                        guard to != nil else { throw invalid("A ramp needs both power endpoints.") }
                    } else { from = number(power["value"]).map { $0 * multiplier } }
                }
                guard let from, from > 0, from <= 32767, to.map({ $0 > 0 && $0 <= 32767 }) ?? true else { throw invalid("Power targets must be positive watts within the supported file range.") }
                if native, item["endWatts"] != nil, to == nil { throw invalid("Invalid ramp endpoint.") }
                let title = String((item[native ? "name" : "text"] as? String ?? "Step \(steps.count + 1)").prefix(100))
                steps.append(.init(title.isEmpty ? "Step \(steps.count + 1)" : title, seconds: seconds, watts: max(1, Int(from.rounded())), endWatts: to.map { max(1, Int($0.rounded())) }))
            }
        }
        try expand(input, depth: 0)
        return try TrainingPlan(kind: .workout, name: name, ftpWatts: ftp, steps: steps)
    }
}
