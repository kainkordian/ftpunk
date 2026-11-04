import Foundation

/// Any workout plan as a Zwift `.zwo` file: a step with an end power becomes a `Ramp`, every other step a `SteadyState`.
/// Powers are fractions of FTP, from the plan's own FTP snapshot when it has one, otherwise the rider's. Step names
/// have no place in the format and are not kept; repeats are not folded back into `IntervalsT`.
public enum ZWOExport {
    public static func data(_ plan: TrainingPlan, ftp riderFTP: Double?) throws -> Data {
        guard let ftp = plan.ftpWatts ?? riderFTP, ftp.isFinite, ftp > 0 else {
            throw ArchiveError.invalid("Set an FTP first: ZWO powers are fractions of FTP.")
        }
        guard plan.kind == .workout, plan.resistance == nil else { throw ArchiveError.invalid("Only timed power workouts can be exported as ZWO.") }
        func fraction(_ watts: Int) -> String { String(format: "%.3f", (Double(watts) / ftp * 1000).rounded() / 1000) }
        var lines = [#"<?xml version="1.0" encoding="UTF-8"?>"#, "<workout_file>", "    <author>FTPunk</author>",
                     "    <name>\(escaped(plan.name))</name>", "    <description></description>", "    <sportType>bike</sportType>", "    <tags/>", "    <workout>"]
        for step in plan.steps {
            let seconds = max(1, Int(step.seconds.rounded()))
            if let end = step.endWatts {
                lines.append(#"        <Ramp Duration="\#(seconds)" PowerLow="\#(fraction(step.watts))" PowerHigh="\#(fraction(end))"/>"#)
            } else {
                lines.append(#"        <SteadyState Duration="\#(seconds)" Power="\#(fraction(step.watts))"/>"#)
            }
        }
        lines += ["    </workout>", "</workout_file>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// `FTPunk-<workout name>.zwo`, reduced to letters, digits and hyphens.
    public static func fileName(for plan: TrainingPlan) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var title = ""
        for character in plan.name { if allowed.contains(character) { title.append(character) } else if title.last != "-" { title.append("-") } }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "FTPunk-\(title.isEmpty ? "Workout" : title).zwo"
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
