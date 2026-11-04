import Foundation

public struct WorkoutTextError: Error, LocalizedError, Equatable, Sendable {
    /// 1-based line number in the text.
    public let line: Int
    public let message: String
    public init(line: Int, message: String) { self.line = line; self.message = message }
    public var errorDescription: String? { "Line \(line): \(message)" }
}

/// The workout text editor's language: a documented subset of the Intervals.icu workout builder syntax. Nothing is guessed:
/// cadence, heart rate, pace, zones, distance, ranges and free-ride steps are errors that name the line.
///
///     Warm-up
///     - 10m 50%
///     Main set 5x
///     - 3m 115%
///     - 3m 55%
///     Ramp down
///     - 5m ramp 60-40%
///     Sprint
///     - 20s 650w
///
/// A line starting with `-` is a step: a duration (`30s`, `10m`, `1h30m`, `1m30`), a target (`80%` of FTP, `200w`,
/// `ramp 60-80%`, `ramp 100-200w`) and optional text, which names the step ("- Recovery 30s 50%"). Any other line is a header.
/// A header ending in `Nx` starts a repeat of the steps below it, up to the next blank line or header; any other header
/// names the first unnamed step below it.
public enum WorkoutText {
    public static let maximumCharacters = 100_000

    public struct Result: Equatable, Sendable {
        public var blocks: [CustomWorkout.Block]
        public var errors: [WorkoutTextError]
        public var isValid: Bool { errors.isEmpty }
    }

    // MARK: Tokens

    enum Token: Equatable {
        case word(String), at
        case duration(Double), percent(Double), watts(Double), ramp
        case rangePercent(Double, Double), rangeWatts(Double, Double)
        case unsupported(String, why: String)
    }

    private static func number(_ text: Substring) -> Double? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), text.filter({ $0 == "." }).count <= 1,
              text.first != ".", text.last != ".", let value = Double(text), value.isFinite else { return nil }
        return value
    }
    /// `10m`, `30s`, `1h`, `1h30m`, `1m30s` and the short `1m30`.
    static func duration(_ text: String) -> Double? {
        var total = 0.0, digits = "", lastUnit = 3 // h = 0, m = 1, s = 2
        for character in text.lowercased() {
            if character.isASCII && character.isNumber { digits.append(character); continue }
            guard let value = Double(digits), !digits.isEmpty else { return nil }
            let unit: Int
            switch character { case "h": unit = 0; case "m": unit = 1; case "s": unit = 2; default: return nil }
            guard unit > (lastUnit == 3 ? -1 : lastUnit) else { return nil }
            total += value * [3600.0, 60, 1][unit]; lastUnit = unit; digits = ""
        }
        if !digits.isEmpty {
            // A bare trailing number is seconds, and only after minutes ("1m30").
            guard lastUnit == 1, let value = Double(digits) else { return nil }
            total += value
        }
        return lastUnit == 3 ? nil : total
    }

    static func token(_ raw: String) -> Token {
        let text = raw.lowercased()
        if text == "@" { return .at }
        if text == "ramp" { return .ramp }
        let unsupportedWords: [String: String] = [
            "hr": "heart rate targets", "lthr": "heart rate targets", "pace": "pace targets", "freeride": "free-ride steps",
            "rpm": "cadence targets", "press": "lap-button steps", "lap": "lap-button steps", "noshowavg": "Zwift display flags",
            "/noshowavg": "Zwift display flags", "ftp": "the ftp keyword", "%hr": "heart rate targets"
        ]
        if let why = unsupportedWords[text] { return .unsupported(raw, why: why) }
        if text.hasSuffix("rpm"), text.dropLast(3).allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) { return .unsupported(raw, why: "cadence targets") }
        if text.first == "z", text.dropFirst().first?.isNumber == true, text.dropFirst().allSatisfy({ $0.isNumber || $0 == "-" || $0 == "z" }) {
            return .unsupported(raw, why: "training zones")
        }
        for suffix in ["km", "mtr", "mi", "yd"] where text.hasSuffix(suffix) && number(text.dropLast(suffix.count)) != nil {
            return .unsupported(raw, why: "distance steps")
        }
        if let seconds = duration(text) { return .duration(seconds) }
        if text.hasSuffix("%"), let value = number(text.dropLast()) { return .percent(value / 100) }
        if text.hasSuffix("w"), let value = number(text.dropLast()) { return .watts(value) }
        for (suffix, percent) in [("%", true), ("w", false)] where text.hasSuffix(suffix) {
            let parts = text.dropLast().split(separator: "-", omittingEmptySubsequences: false)
            if parts.count == 2, let low = number(parts[0]), let high = number(parts[1]) {
                return percent ? .rangePercent(low / 100, high / 100) : .rangeWatts(low, high)
            }
        }
        return .word(raw)
    }

    /// True when every word of a name reads as plain text (so printing the name and parsing it again gives the same name).
    public static func isPlainName(_ name: String) -> Bool {
        let words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if let last = words.last, last.count >= 2, last.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }), last.last?.lowercased() == "x" { return false }
        if name.hasPrefix("-") { return false }
        return words.allSatisfy { if case .word = token($0) { true } else { false } }
    }

    // MARK: Parsing

    public static func parse(_ text: String) -> Result {
        var errors: [WorkoutTextError] = []
        guard text.count <= maximumCharacters else {
            return Result(blocks: [], errors: [WorkoutTextError(line: 1, message: "The text is too long.")])
        }
        var blocks: [CustomWorkout.Block] = []
        var header: String?
        var group: (count: Int, line: Int, steps: [CustomWorkout.Step])?
        func flush() {
            if let open = group {
                if open.steps.isEmpty { errors.append(WorkoutTextError(line: open.line, message: "This repeat has no steps under it.")) }
                else { blocks.append(.repeats(count: open.count, steps: open.steps)) }
            }
            group = nil
        }
        // "\r\n" is one Character in Swift, so line endings are normalised before splitting.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (index, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); header = nil; continue }
            if line.hasPrefix("-") {
                do {
                    var step = try step(String(line.dropFirst()), line: number)
                    if group != nil { group?.steps.append(step) }
                    else {
                        if step.name.isEmpty, let header { step.name = header }
                        header = nil; blocks.append(.step(step))
                    }
                } catch let error as WorkoutTextError { errors.append(error) } catch {}
                continue
            }
            flush()
            let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if let last = words.last, last.count >= 2, last.last?.lowercased() == "x", let count = Int(last.dropLast()) {
                if CustomWorkout.repeatRange.contains(count) { group = (count, number, []); header = nil }
                else { errors.append(WorkoutTextError(line: number, message: "A repeat needs 1 to 100 repeats.")) }
            } else {
                header = CustomWorkout.normalized(line)
            }
        }
        flush()
        if errors.isEmpty, blocks.isEmpty { errors.append(WorkoutTextError(line: 1, message: "Add a step such as \"- 10m 50%\".")) }
        return Result(blocks: errors.isEmpty ? blocks : [], errors: errors)
    }

    private static func step(_ text: String, line: Int) throws -> CustomWorkout.Step {
        func fail(_ message: String) -> WorkoutTextError { WorkoutTextError(line: line, message: message) }
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map { token(String($0)) }
        var seconds: Double?, target: (start: CustomWorkout.Target, end: CustomWorkout.Target?)?, rampNext = false
        for item in tokens {
            switch item {
            case .unsupported(let raw, let why): throw fail("\"\(raw)\" is not supported (\(why)).")
            case .word:
                if rampNext { throw fail("\"ramp\" needs two values, like ramp 60-80% or ramp 100-200w.") }
            case .at:
                if rampNext { throw fail("\"ramp\" needs two values, like ramp 60-80% or ramp 100-200w.") }
            case .duration(let value):
                if rampNext { throw fail("\"ramp\" needs two values, like ramp 60-80% or ramp 100-200w.") }
                guard seconds == nil else { throw fail("A step has one duration.") }
                seconds = value
            case .percent(let value), .watts(let value):
                if rampNext { throw fail("\"ramp\" needs two values, like ramp 60-80% or ramp 100-200w.") }
                guard target == nil else { throw fail("A step has one target.") }
                if case .percent = item { target = (.percentFTP(value), nil) } else { target = (.watts(value), nil) }
            case .ramp:
                guard target == nil, !rampNext else { throw fail("A step has one target.") }
                rampNext = true
            case .rangePercent(let low, let high), .rangeWatts(let low, let high):
                guard rampNext else { throw fail("Ranges are not supported. Write ramp followed by the two values to ramp gradually, or use one value.") }
                guard target == nil else { throw fail("A step has one target.") }
                rampNext = false
                if case .rangePercent = item { target = (.percentFTP(low), .percentFTP(high)) } else { target = (.watts(low), .watts(high)) }
            }
        }
        if rampNext { throw fail("\"ramp\" needs two values, like ramp 60-80% or ramp 100-200w.") }
        guard let seconds else { throw fail("This step needs a duration such as 10m, 30s or 1m30.") }
        guard let target else { throw fail("This step needs a target such as 80%, 200w or ramp 60-80%.") }
        guard CustomWorkout.stepSeconds.contains(seconds) else { throw fail("The duration must be between 5 seconds and 4 hours.") }
        for value in [target.start, target.end].compactMap({ $0 }) {
            switch value {
            case .percentFTP(let percent): guard CustomWorkout.percentRange.contains(percent) else { throw fail("% FTP must be between 30 and 250.") }
            case .watts(let watts): guard CustomWorkout.wattsRange.contains(watts) else { throw fail("Watts must be between 20 and 1500.") }
            }
        }
        let joined = CustomWorkout.normalized(nameWords(text).joined(separator: " "))
        guard joined.count <= 100 else { throw fail("The step name can have at most 100 characters.") }
        return CustomWorkout.Step(name: joined, seconds: seconds, start: target.start, end: target.end)
    }

    /// The words of the step line that are text: everything that is not a duration, target, "@", or an "at" right before a target.
    private static func nameWords(_ text: String) -> [String] {
        let raw = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result: [String] = []
        for (index, word) in raw.enumerated() {
            guard case .word = token(word) else { continue }
            if word.lowercased() == "at", index + 1 < raw.count {
                switch token(raw[index + 1]) {
                case .percent, .watts, .ramp, .rangePercent, .rangeWatts: continue
                default: break
                }
            }
            result.append(word)
        }
        return result
    }

    // MARK: Printing

    public static func print(_ blocks: [CustomWorkout.Block]) -> String {
        var sections: [String] = []
        for block in blocks {
            switch block {
            case .step(let step):
                sections.append((step.name.isEmpty ? [] : [step.name]).appending("- " + stepText(step, name: false)).joined(separator: "\n"))
            case .repeats(let count, let steps):
                sections.append((["\(count)x"] + steps.map { "- " + stepText($0, name: true) }).joined(separator: "\n"))
            }
        }
        return sections.joined(separator: "\n\n")
    }
    private static func stepText(_ step: CustomWorkout.Step, name: Bool) -> String {
        var parts: [String] = []
        if name, !step.name.isEmpty { parts.append(step.name) }
        parts.append(durationText(step.seconds))
        parts.append(targetText(step.start, step.end))
        return parts.joined(separator: " ")
    }
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded()), hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return (hours > 0 ? "\(hours)h" : "") + (minutes > 0 ? "\(minutes)m" : "") + (rest > 0 || total == 0 ? "\(rest)s" : "")
    }
    private static func numberText(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    }
    private static func targetText(_ start: CustomWorkout.Target, _ end: CustomWorkout.Target?) -> String {
        func text(_ target: CustomWorkout.Target) -> String { numberText(target.isPercent ? target.number * 100 : target.number) }
        let unit = start.isPercent ? "%" : "w"
        guard let end else { return text(start) + unit }
        return "ramp \(text(start))-\(text(end))\(unit)"
    }
}

private extension Array {
    func appending(_ element: Element) -> [Element] { self + [element] }
}
