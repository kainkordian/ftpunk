import Foundation

/// Zwift workout files (`.zwo`). Powers are fractions of FTP, so an import needs the rider's FTP and is resolved to
/// whole watts once. Only timed power steps are supported: a step that would need guessed watts rejects the file.
/// The limits match `WorkoutImport`: 2 MiB, 500 expanded steps, 24 hours and 100 repeats.
public enum ZWOImport {
    public static func parse(_ data: Data, ftp: Double?) throws -> TrainingPlan {
        guard data.count <= WorkoutImport.maximumBytes else { throw ArchiveError.invalid("Workout files must be under 2 MB.") }
        // A workout file has no use for a DTD; refusing it closes the door on entity tricks.
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        guard !head.contains("<!doctype"), !head.contains("<!entity") else { throw ArchiveError.invalid("This is not a valid ZWO workout file.") }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.failure == nil, reader.sawRoot else {
            throw reader.failure ?? ArchiveError.invalid("This is not a valid ZWO workout file.")
        }
        guard let ftp, ftp.isFinite, ftp > 0, ftp <= 32767 else {
            throw ArchiveError.invalid("Set an FTP first: ZWO powers are fractions of FTP.")
        }
        var steps: [TrainingPlan.Step] = []
        func watts(_ fraction: Double) throws -> Int {
            let value = (fraction * ftp).rounded()
            guard value >= 1, value <= 32767 else { throw ArchiveError.invalid("Power targets must be positive watts within the supported file range.") }
            return Int(value)
        }
        func add(_ name: String, seconds: Double, from: Double, to: Double?) throws {
            guard steps.count < 500 else { throw ArchiveError.invalid("Workout repeats are too deeply nested or too large.") }
            steps.append(.init(name, seconds: seconds, watts: try watts(from), endWatts: try to.map(watts)))
        }
        for block in reader.blocks {
            switch block {
            case .steady(let seconds, let power): try add("Steady", seconds: seconds, from: power, to: nil)
            case .ramp(let name, let seconds, let from, let to): try add(name, seconds: seconds, from: from, to: to)
            case .intervals(let repeats, let onSeconds, let offSeconds, let on, let off):
                for _ in 0..<repeats {
                    try add("On", seconds: onSeconds, from: on.from, to: on.to)
                    try add("Off", seconds: offSeconds, from: off.from, to: off.to)
                }
            }
        }
        guard !steps.isEmpty else { throw ArchiveError.invalid("The workout contains no steps.") }
        let name = String(reader.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        return try TrainingPlan(kind: .workout, name: name.isEmpty ? "Imported workout" : name, ftpWatts: ftp, steps: steps)
    }

    private enum Block {
        case steady(seconds: Double, power: Double)
        case ramp(name: String, seconds: Double, from: Double, to: Double)
        case intervals(repeats: Int, onSeconds: Double, offSeconds: Double, on: (from: Double, to: Double?), off: (from: Double, to: Double?))
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var blocks: [Block] = []
        var name = "", sawRoot = false
        var failure: ArchiveError?
        private var path: [String] = []
        private var text = ""
        private var expandedSteps = 0, seconds = 0.0

        private func fail(_ message: String, _ parser: XMLParser) {
            if failure == nil { failure = .invalid(message) }
            parser.abortParsing()
        }
        private func number(_ attributes: [String: String], _ key: String) -> Double? {
            guard let raw = attributes[key]?.trimmingCharacters(in: .whitespaces), let value = Double(raw), value.isFinite else { return nil }
            return value
        }
        private func fraction(_ attributes: [String: String], _ key: String, _ parser: XMLParser) -> Double? {
            guard let value = number(attributes, key), value > 0, value <= 5 else {
                fail("ZWO powers are fractions of FTP (for example 0.75), and every step needs one.", parser); return nil
            }
            return value
        }
        private func duration(_ attributes: [String: String], _ key: String, _ parser: XMLParser) -> Double? {
            guard let value = number(attributes, key), value > 0, value <= 86400 else {
                fail("Every step must have a timed power target; free, distance and lap steps are unsupported.", parser); return nil
            }
            return value
        }
        private func count(_ more: Int, _ addedSeconds: Double, _ parser: XMLParser) {
            expandedSteps += more; seconds += addedSeconds
            if expandedSteps > 500 || seconds > 86400 { fail("Workout repeats are too deeply nested or too large.", parser) }
        }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if path.isEmpty {
                guard element == "workout_file" else { fail("This is not a valid ZWO workout file.", parser); return }
                sawRoot = true
            }
            path.append(element); text = ""
            // Steps are the direct children of <workout>; anything nested inside a step (textevent, …) is ignored.
            guard path.count == 3, path[1] == "workout" else { return }
            switch element {
            case "SteadyState":
                guard let length = duration(attributes, "Duration", parser), let power = fraction(attributes, "Power", parser) else { return }
                count(1, length, parser); blocks.append(.steady(seconds: length, power: power))
            case "Warmup", "Cooldown", "Ramp":
                // PowerLow is where the step starts and PowerHigh where it ends, even when a cool-down falls.
                guard let length = duration(attributes, "Duration", parser), let low = fraction(attributes, "PowerLow", parser),
                      let high = fraction(attributes, "PowerHigh", parser) else { return }
                count(1, length, parser)
                blocks.append(.ramp(name: element == "Warmup" ? "Warm-up" : element == "Cooldown" ? "Cool-down" : "Ramp", seconds: length, from: low, to: high))
            case "IntervalsT":
                guard let repeats = number(attributes, "Repeat"), repeats >= 1, repeats <= 100, repeats.rounded() == repeats else {
                    fail("Invalid repeat count.", parser); return
                }
                guard let on = duration(attributes, "OnDuration", parser), let off = duration(attributes, "OffDuration", parser) else { return }
                func power(_ single: String, _ low: String, _ high: String) -> (from: Double, to: Double?)? {
                    if attributes[low] != nil || attributes[high] != nil {
                        guard let from = fraction(attributes, low, parser), let to = fraction(attributes, high, parser) else { return nil }
                        return (from, to)
                    }
                    return fraction(attributes, single, parser).map { ($0, nil) }
                }
                guard let onPower = power("OnPower", "PowerOnLow", "PowerOnHigh"), let offPower = power("OffPower", "PowerOffLow", "PowerOffHigh") else { return }
                count(Int(repeats) * 2, repeats * (on + off), parser)
                blocks.append(.intervals(repeats: Int(repeats), onSeconds: on, offSeconds: off, on: onPower, off: offPower))
            case "SolidState":
                if attributes["Power"] != nil || attributes["PowerLow"] != nil {
                    guard let length = duration(attributes, "Duration", parser) else { return }
                    if attributes["PowerLow"] != nil {
                        guard let low = fraction(attributes, "PowerLow", parser), let high = fraction(attributes, "PowerHigh", parser) else { return }
                        count(1, length, parser); blocks.append(.ramp(name: "Ramp", seconds: length, from: low, to: high))
                    } else if let power = fraction(attributes, "Power", parser) {
                        count(1, length, parser); blocks.append(.steady(seconds: length, power: power))
                    }
                } else { fail("This workout has a free-ride or maximal-effort step, which has no power target. Those are unsupported.", parser) }
            case "FreeRide", "MaxEffort":
                fail("This workout has a free-ride or maximal-effort step, which has no power target. Those are unsupported.", parser)
            default: break // textevent, Cadence, pace and other metadata do not change the power plan
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if text.count < 4000 { text += string } }
        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            defer { path.removeLast() }
            guard path.count == 2 else { return }
            switch element {
            case "name": name = text
            case "sportType":
                let sport = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !sport.isEmpty, sport != "bike" { fail("Only cycling (bike) workouts are supported.", parser) }
            default: break
            }
        }
        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            if failure == nil { failure = .invalid("This is not a valid ZWO workout file.") }
        }
    }
}
