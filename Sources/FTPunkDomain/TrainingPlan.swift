import Foundation

/// Fully resolved, immutable targets travel with the recording. Changing FTP later
/// never changes the meaning of a workout that has already started.
public struct TrainingPlan: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case workout, freeRide }
    public struct Step: Codable, Equatable, Sendable {
        public let name: String
        public let seconds: Double
        public let watts: Int
        public let endWatts: Int?
        public init(_ name: String, seconds: Double, watts: Int, endWatts: Int? = nil) {
            self.name = name; self.seconds = seconds; self.watts = watts; self.endWatts = endWatts
        }
    }
    public let resistance: Int?
    public let version: Int
    public let kind: Kind
    public let name: String
    public let ftpWatts: Double?
    public let steps: [Step]
    public var duration: Double { steps.reduce(0) { $0 + $1.seconds } }
    public init(kind: Kind, name: String, ftpWatts: Double? = nil, steps: [Step], resistance: Int? = nil) throws {
        version = resistance != nil || steps.contains(where: { $0.endWatts != nil }) ? 2 : 1; self.resistance = resistance; self.kind = kind; self.name = name; self.ftpWatts = ftpWatts; self.steps = steps
        try validate()
    }
    public func validate() throws {
        guard (1...2).contains(version), version >= 2 || (resistance == nil && steps.allSatisfy { $0.endWatts == nil }),
              resistance.map({ (0...32767).contains($0) && kind == .freeRide }) ?? true, !name.isEmpty, name.count <= 100, !steps.isEmpty, steps.count <= 500,
              ftpWatts.map({ $0.isFinite && $0 > 0 && $0 <= 32767 }) ?? true,
              steps.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 100 && $0.seconds.isFinite && $0.seconds > 0 && $0.watts > 0 && $0.watts <= 32767 && ($0.endWatts.map { (1...32767).contains($0) } ?? true) }),
              duration <= 86400, kind != .freeRide || steps.count == 1 else {
            throw ArchiveError.invalid("Invalid workout duration or power target.")
        }
    }
    public func step(at elapsed: Double) -> (index: Int, step: Step, remaining: Double)? {
        var start = 0.0
        for (index, step) in steps.enumerated() {
            if elapsed < start + step.seconds { return (index, step, start + step.seconds - elapsed) }
            start += step.seconds
        }
        return nil
    }
    public func target(at elapsed: Double, intensity: Int = 100) -> Int? {
        guard resistance == nil, let current = step(at: elapsed) else { return nil }
        let fraction = max(0, min(1, 1 - current.remaining / current.step.seconds))
        let power = Double(current.step.watts) + Double((current.step.endWatts ?? current.step.watts) - current.step.watts) * fraction
        return Int((power * Double(intensity) / 100).rounded())
    }
    public func supports(intensity: Int, minimum: Int, maximum: Int) -> Bool {
        (50...150).contains(intensity) && steps.allSatisfy { step in
            [step.watts, step.endWatts ?? step.watts].allSatisfy {
                let watts = Int((Double($0) * Double(intensity) / 100).rounded())
                return watts >= max(1, minimum) && watts <= maximum
            }
        }
    }
    public static func resistanceRide(level: Int) throws -> Self {
        try Self(kind: .freeRide, name: "Resistance ride", steps: [.init("Ride at your own pace", seconds: 86400, watts: 1)], resistance: level)
    }
    public static func freeRide(watts: Int) throws -> Self {
        try Self(kind: .freeRide, name: "Free ERG ride", steps: [.init("Ride at your own pace", seconds: 86400, watts: watts)])
    }
    public static func starters(ftp: Double) throws -> [Self] {
        guard ftp.isFinite, ftp > 0, ftp <= 32767 else { throw ArchiveError.invalid("Set your FTP before choosing a workout.") }
        func step(_ name: String, _ minutes: Double, _ fraction: Double) -> Step {
            .init(name, seconds: minutes * 60, watts: max(1, Int((ftp * fraction).rounded())))
        }
        return try [
            Self(kind: .workout, name: "Easy spin · 20 min", ftpWatts: ftp, steps: [step("Warm-up", 3, 0.50), step("Easy spin", 14, 0.55), step("Cooldown", 3, 0.40)]),
            Self(kind: .workout, name: "Endurance · 30 min", ftpWatts: ftp, steps: [step("Warm-up", 5, 0.50), step("Endurance", 20, 0.65), step("Cooldown", 5, 0.40)]),
            Self(kind: .workout, name: "Tempo intervals · 30 min", ftpWatts: ftp, steps: [step("Warm-up", 5, 0.50)] + (1...3).flatMap { [step("Tempo \($0) of 3", 5, 0.80), step("Recovery", 2, 0.45)] } + [step("Cooldown", 4, 0.40)])
        ]
    }
}

/// Progress from the removed Lowline story. The native app no longer grants or shows it, but the record stays
/// decodable, validated and preserved unchanged, so backups from the web app (which still has the story) round-trip.
/// A high-water mark per activity keeps repeated checkpoints and imports idempotent.
public struct CycleProgress: Codable, Equatable, Sendable {
    public var version = 1
    public var credits: [String: Int] = [:]
    public init() {}
    public var milliseconds: Int { credits.values.reduce(0, +) }
    public mutating func credit(_ session: TestSession) {
        guard !session.isDemo, session.adventureEnabled == true,
              let milliseconds = session.eligibleMilliseconds, (0...86400000).contains(milliseconds) else { return }
        let id = session.id.uuidString.lowercased()
        credits[id] = max(credits[id] ?? 0, milliseconds)
    }
    public func validate() throws {
        guard version == 1, credits.count <= 100000,
              credits.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value >= 0 && $0.value <= 86400000 }) else {
            throw ArchiveError.invalid("Invalid legacy story progress.")
        }
    }
}
