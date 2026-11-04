import Foundation

/// A workout the rider built in the app. It is kept as blocks (targets in % FTP or watts, ramps, one level of repeats)
/// and resolved into a `TrainingPlan` when it is shown or started, so later edits never change a recording.
public struct CustomWorkout: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var riderID: UUID
    public var name: String
    public var category: WorkoutCategory?
    public var blocks: [Block]
    public var updatedAt: Date

    public enum Block: Equatable, Sendable {
        case step(Step)
        /// One level of nesting only.
        case repeats(count: Int, steps: [Step])
    }
    public struct Step: Codable, Equatable, Sendable {
        /// Empty means "unnamed": the plan calls it "Step N".
        public var name: String
        /// 5 s … 4 h.
        public var seconds: Double
        public var start: Target
        /// Nil is a constant target; otherwise a linear ramp to this one (the same unit as `start`).
        public var end: Target?
        public init(name: String = "", seconds: Double, start: Target, end: Target? = nil) {
            self.name = name; self.seconds = seconds; self.start = start; self.end = end
        }
    }
    public enum Target: Equatable, Sendable {
        /// 0.30 … 2.50 of FTP.
        case percentFTP(Double)
        /// 20 … 1500 W. Never rescales.
        case watts(Double)
        public var isPercent: Bool { if case .percentFTP = self { true } else { false } }
        public var number: Double { switch self { case .percentFTP(let value), .watts(let value): value } }
        func sameUnit(as other: Target) -> Bool { isPercent == other.isPercent }
    }

    public init(id: UUID = UUID(), riderID: UUID, name: String, category: WorkoutCategory? = nil, blocks: [Block], updatedAt: Date = Date()) {
        self.id = id; self.riderID = riderID; self.name = name; self.category = category; self.blocks = blocks; self.updatedAt = updatedAt
    }

    // MARK: Limits

    public static let stepSeconds: ClosedRange<Double> = 5...14400
    public static let percentRange: ClosedRange<Double> = 0.30...2.50
    public static let wattsRange: ClosedRange<Double> = 20...1500
    public static let repeatRange = 1...100
    public static let maximumExpandedSteps = 500
    public static let maximumDuration = 86400.0
    public static let maximumPerRider = 200

    public enum BuildError: Error, LocalizedError, Equatable {
        case needsFTP, invalid(String)
        public var errorDescription: String? {
            switch self {
            case .needsFTP: "This workout has % FTP targets. Set an FTP first."
            case .invalid(let reason): reason
            }
        }
    }

    // MARK: Reading

    /// Every step in riding order, repeats expanded.
    public var flattened: [Step] {
        blocks.flatMap { block -> [Step] in
            switch block {
            case .step(let step): [step]
            case .repeats(let count, let steps): (0..<max(0, count)).flatMap { _ in steps }
            }
        }
    }
    public var needsFTP: Bool { flattened.contains { $0.start.isPercent || $0.end?.isPercent == true } }
    public var duration: Double { flattened.reduce(0) { $0 + $1.seconds } }

    // MARK: Validation

    /// Everything that is wrong, worded for the rider ("Step 3: …"). Empty means the workout can be saved.
    public func issues() -> [String] {
        var found: [String] = []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { found.append("Give the workout a name.") }
        else if name.count > 100 { found.append("The name can have at most 100 characters.") }
        if blocks.isEmpty { found.append("Add at least one step.") }
        if blocks.count > Self.maximumExpandedSteps { found.append("A workout can have at most \(Self.maximumExpandedSteps) blocks.") }
        var number = 0
        func check(_ step: Step) {
            number += 1
            let label = "Step \(number)"
            if !step.seconds.isFinite || !Self.stepSeconds.contains(step.seconds) { found.append("\(label): the duration must be between 5 seconds and 4 hours.") }
            if step.name.count > 100 { found.append("\(label): the name can have at most 100 characters.") }
            if !Self.nameIsPlain(step.name) { found.append("\(label): the name cannot contain line breaks, '@', or words such as 10m, 80%, 200w, ramp or 5x.") }
            for target in [step.start] + (step.end.map { [$0] } ?? []) {
                switch target {
                case .percentFTP(let value): if !value.isFinite || !Self.percentRange.contains(value) { found.append("\(label): % FTP must be between 30 and 250.") }
                case .watts(let value): if !value.isFinite || !Self.wattsRange.contains(value) { found.append("\(label): watts must be between 20 and 1500.") }
                }
            }
            if let end = step.end, !end.sameUnit(as: step.start) { found.append("\(label): a ramp uses one unit for both ends (% FTP or watts).") }
        }
        for block in blocks {
            switch block {
            case .step(let step): check(step)
            case .repeats(let count, let steps):
                if !Self.repeatRange.contains(count) { found.append("A repeat block needs 1 to 100 repeats.") }
                if steps.isEmpty { found.append("A repeat block needs at least one step.") }
                steps.forEach(check)
            }
        }
        let expanded = flattened
        if expanded.count > Self.maximumExpandedSteps { found.append("The workout has \(expanded.count) steps once repeats are expanded; the limit is \(Self.maximumExpandedSteps).") }
        if expanded.reduce(0, { $0 + $1.seconds }) > Self.maximumDuration { found.append("The workout is longer than 24 hours.") }
        return found
    }
    public func validate() throws {
        if let first = issues().first { throw BuildError.invalid(first) }
    }
    /// A step name must survive the text editor unchanged: one line, no words that read as a duration, target or repeat count.
    public static func nameIsPlain(_ name: String) -> Bool {
        name == normalized(name) && !name.contains("\n") && WorkoutText.isPlainName(name)
    }
    /// Collapses runs of white space and trims the ends.
    public static func normalized(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: Building a plan

    /// The workout as fixed targets. `% FTP` steps resolve once with `ftp`; watt steps never change.
    public func plan(ftp: Double?) throws -> TrainingPlan {
        try validate()
        let usableFTP = ftp.flatMap { $0.isFinite && $0 > 0 && $0 <= 32767 ? $0 : nil }
        if needsFTP, usableFTP == nil { throw BuildError.needsFTP }
        func watts(_ target: Target) -> Int {
            switch target {
            case .watts(let value): max(1, Int(value.rounded()))
            case .percentFTP(let value): max(1, Int(((usableFTP ?? 0) * value).rounded()))
            }
        }
        let steps = flattened.enumerated().map { index, step -> TrainingPlan.Step in
            let end = step.end.map(watts), start = watts(step.start)
            return .init(step.name.isEmpty ? "Step \(index + 1)" : step.name, seconds: step.seconds, watts: start, endWatts: end == start ? nil : end)
        }
        return try TrainingPlan(kind: .workout, name: name.trimmingCharacters(in: .whitespacesAndNewlines), ftpWatts: usableFTP, steps: steps)
    }

    // MARK: From other workouts

    /// A built-in workout as % FTP blocks. Building it back at the same FTP gives the identical plan.
    public init?(definition: WorkoutDefinition, riderID: UUID, name: String? = nil, id: UUID = UUID(), date: Date = Date()) {
        let steps = definition.steps.map {
            Step(name: $0.name, seconds: $0.minutes * 60, start: .percentFTP($0.from), end: $0.to.map { .percentFTP($0) })
        }
        self.init(id: id, riderID: riderID, name: name ?? definition.name, category: definition.category, blocks: steps.map(Block.step), updatedAt: date)
        guard issues().isEmpty else { return nil }
    }
    /// Any plan as watt blocks, for "Duplicate & edit" of an imported or calendar workout. Nil when a step is outside the builder's limits.
    public init?(plan: TrainingPlan, riderID: UUID, name: String? = nil, id: UUID = UUID(), date: Date = Date()) {
        let steps = plan.steps.map {
            Step(name: CustomWorkout.normalized($0.name), seconds: $0.seconds, start: .watts(Double($0.watts)), end: $0.endWatts.map { .watts(Double($0)) })
        }
        self.init(id: id, riderID: riderID, name: name ?? plan.name, blocks: steps.map(Block.step), updatedAt: date)
        guard issues().isEmpty else { return nil }
    }
}

// MARK: - Codable (explicit shapes, so other apps can read them)

extension CustomWorkout.Target: Codable {
    private enum Keys: String, CodingKey { case unit, value }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let value = try values.decode(Double.self, forKey: .value)
        switch try values.decode(String.self, forKey: .unit) {
        case "percentFTP": self = .percentFTP(value)
        case "watts": self = .watts(value)
        default: throw DecodingError.dataCorruptedError(forKey: .unit, in: values, debugDescription: "Unknown target unit.")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(isPercent ? "percentFTP" : "watts", forKey: .unit); try values.encode(number, forKey: .value)
    }
}

extension CustomWorkout.Block: Codable {
    private enum Keys: String, CodingKey { case kind, step, count, steps }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "step": self = .step(try values.decode(CustomWorkout.Step.self, forKey: .step))
        case "repeats": self = .repeats(count: try values.decode(Int.self, forKey: .count), steps: try values.decode([CustomWorkout.Step].self, forKey: .steps))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown block kind.")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .step(let step): try values.encode("step", forKey: .kind); try values.encode(step, forKey: .step)
        case .repeats(let count, let steps): try values.encode("repeats", forKey: .kind); try values.encode(count, forKey: .count); try values.encode(steps, forKey: .steps)
        }
    }
}

// MARK: - Helpers for the editor

extension CustomWorkout {
    /// A duration typed into a field: `m:ss`, `h:mm:ss`, a plain number of minutes, or the text-editor forms (`90s`, `1m30`, `1h`).
    public static func parseDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
            guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
            let numbers = parts.compactMap { $0 }
            if numbers.count == 2 { return numbers[1] < 60 ? Double(numbers[0] * 60 + numbers[1]) : nil }
            return numbers[1] < 60 && numbers[2] < 60 ? Double(numbers[0] * 3600 + numbers[1] * 60 + numbers[2]) : nil
        }
        if let minutes = Double(trimmed), minutes.isFinite, minutes > 0 { return minutes * 60 }
        return WorkoutText.duration(trimmed)
    }
    /// "m:ss", or "h:mm:ss" from an hour on.
    public static func durationText(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The flat step index (repeats expanded) of the first step of each block row, and how many flat steps the row spans.
    public func flatRanges() -> [Range<Int>] {
        var next = 0
        return blocks.map { block in
            let count: Int
            switch block {
            case .step: count = 1
            case .repeats(let repeats, let steps): count = repeats * steps.count
            }
            defer { next += count }
            return next..<(next + count)
        }
    }

    /// Estimated intensity factor and training stress: power is averaged the way normalised power is (fourth-power mean),
    /// but over whole steps instead of rolling 30 s windows, so it is an estimate. Watt steps count against `ftp`.
    public func estimatedLoad(ftp: Double?) -> (intensityFactor: Double, tss: Double)? {
        guard let ftp, ftp.isFinite, ftp > 0, issues().isEmpty else { return nil }
        func watts(_ target: Target) -> Double { target.isPercent ? target.number * ftp : target.number }
        var weighted = 0.0, seconds = 0.0
        for step in flattened {
            let from = watts(step.start), to = step.end.map(watts) ?? from
            let slices = max(1, Int((step.seconds / 5).rounded()))
            for slice in 0..<slices {
                let power = from + (to - from) * (Double(slice) + 0.5) / Double(slices)
                weighted += pow(power, 4) * (step.seconds / Double(slices)); seconds += step.seconds / Double(slices)
            }
        }
        guard seconds > 0 else { return nil }
        let factor = pow(weighted / seconds, 0.25) / ftp
        return (factor, seconds / 3600 * factor * factor * 100)
    }
}
