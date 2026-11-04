import Foundation

/// One step of a workout as the preview shows it: name, duration, % of FTP and watts.
public struct WorkoutStepSummary: Equatable, Sendable {
    public let index: Int
    public let name: String
    public let start: Double, seconds: Double
    public let watts: Int, endWatts: Int?
    /// Nil without an FTP (or when values are hidden).
    public let percent: Int?, endPercent: Int?
    public let zone: IntensityZone?

    public var durationText: String { DurationFormat.clock(seconds) }
    public var percentText: String? {
        percent.map { start in endPercent.map { "\(start)→\($0) %" } ?? "\(start) %" }
    }
    public var wattsText: String { endWatts.map { "\(watts)→\($0) W" } ?? "\(watts) W" }
    /// "10:00 · 50 % · 125 W", "5:00 · 60→40 % · 150→100 W", or just "10:00" when values are hidden.
    public var valueText: String {
        guard let percentText else { return durationText }
        return "\(durationText) · \(percentText) · \(wattsText)"
    }
    /// Spoken form for VoiceOver.
    public var spokenText: String {
        guard percent != nil else { return "\(name), \(DurationFormat.compact(seconds))" }
        return "\(name), \(DurationFormat.compact(seconds)), \(valueText.split(separator: "·").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", "))"
    }
    /// "3:00 @ 115 % (288 W)" for compact summaries; the ramp form uses arrows.
    fileprivate var compactText: String {
        guard let percentText else { return durationText }
        return "\(durationText) @ \(percentText) (\(wattsText))"
    }
}

/// Consecutive repeat blocks for the compact step list. `repeats == 1` is a plain step.
public struct StepGroup: Equatable, Sendable {
    public let range: Range<Int>
    public let repeats: Int
    /// One repetition of the block.
    public let pattern: [WorkoutStepSummary]
    public var text: String {
        let body = pattern.map { "\(Self.baseName($0.name)) \($0.compactText)" }.joined(separator: " / ")
        return repeats > 1 ? "\(repeats)× \(body)" : body
    }
    /// "VO2max 2 of 5" becomes "VO2max".
    static func baseName(_ name: String) -> String {
        name.replacingOccurrences(of: #" \d+ of \d+$"#, with: "", options: .regularExpression)
    }
}

public enum WorkoutPreview {
    /// Steps with % FTP and watts at the given intensity. `showValues: false` gives durations only (no FTP yet).
    public static func steps(for plan: TrainingPlan, intensity: Int = 100, showValues: Bool = true) -> [WorkoutStepSummary] {
        let scale = Double(intensity) / 100
        let ftp = showValues ? plan.ftpWatts.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } : nil
        var cursor = 0.0
        return plan.steps.enumerated().map { index, step in
            defer { cursor += step.seconds }
            let start = Int((Double(step.watts) * scale).rounded())
            let end = step.endWatts.map { Int((Double($0) * scale).rounded()) }
            func percent(_ watts: Int) -> Int? { ftp.map { Int((Double(watts) / $0 * 100).rounded()) } }
            let average = (Double(start) + Double(end ?? start)) / 2
            return WorkoutStepSummary(index: index, name: step.name, start: cursor, seconds: step.seconds,
                                      watts: start, endWatts: end, percent: percent(start), endPercent: end.flatMap(percent),
                                      zone: ftp.map { IntensityZone.zone(forFraction: average / $0) })
        }
    }

    /// The step under a horizontal position (0...1 across the duration), for hover and drag. A boundary belongs to the later step.
    public static func step(atFraction x: Double, in plan: TrainingPlan) -> Int? {
        guard x.isFinite, x >= 0, x <= 1, !plan.steps.isEmpty, plan.duration > 0 else { return nil }
        let time = x * plan.duration
        var end = 0.0
        for (index, step) in plan.steps.enumerated() {
            end += step.seconds
            if time < end { return index }
        }
        return plan.steps.count - 1
    }

    /// Groups runs of identical (seconds, watts) patterns that repeat at least twice. A block may end after its work
    /// step without the final recovery, as the library's repeat workouts do.
    public static func groups(for plan: TrainingPlan, intensity: Int = 100, showValues: Bool = true) -> [StepGroup] {
        let summaries = steps(for: plan, intensity: intensity, showValues: showValues)
        let keys = plan.steps.map { Key(seconds: $0.seconds, watts: $0.watts, endWatts: $0.endWatts) }
        var result: [StepGroup] = []
        var i = 0
        while i < keys.count {
            var best: (length: Int, repeats: Int, covered: Int)?
            for length in 1...min(8, keys.count - i) {
                let pattern = Array(keys[i..<(i + length)])
                var repeats = 1, cursor = i + length
                while cursor + length <= keys.count, Array(keys[cursor..<(cursor + length)]) == pattern { repeats += 1; cursor += length }
                var covered = repeats * length
                if length > 1, cursor + length - 1 <= keys.count, Array(keys[cursor..<(cursor + length - 1)]) == Array(pattern.dropLast()) {
                    repeats += 1; covered += length - 1
                }
                if repeats >= 2, covered > (best?.covered ?? 0) { best = (length, repeats, covered) }
            }
            if let best {
                result.append(StepGroup(range: i..<(i + best.covered), repeats: best.repeats, pattern: Array(summaries[i..<(i + best.length)])))
                i += best.covered
            } else {
                result.append(StepGroup(range: i..<(i + 1), repeats: 1, pattern: [summaries[i]]))
                i += 1
            }
        }
        return result
    }

    /// "5 × 3:00 @ 115 % (288 W)": the constant step that does the most work in the plan (occurrences × duration × watts),
    /// and how often it occurs. A short sprint therefore never outranks the repeated efforts. Nil for ramp-only plans.
    public static func mainSetText(for plan: TrainingPlan, intensity: Int = 100, showValues: Bool = true) -> String? {
        let all = steps(for: plan, intensity: intensity, showValues: showValues)
        let constant = all.filter { $0.endWatts == nil }
        func count(_ step: WorkoutStepSummary) -> Int { constant.filter { $0.watts == step.watts && $0.seconds == step.seconds }.count }
        func work(_ step: WorkoutStepSummary) -> Double { Double(count(step)) * step.seconds * Double(step.watts) }
        guard let top = constant.max(by: { work($0) < work($1) }) else { return nil }
        let n = count(top)
        return n > 1 ? "\(n) × \(top.compactText)" : top.compactText
    }

    private struct Key: Equatable { let seconds: Double, watts: Int, endWatts: Int? }
}
