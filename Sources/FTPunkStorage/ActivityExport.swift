import Foundation
import FTPunkDomain

public enum ExportError: Error { case notFinalized, emptyActivity }

public enum ActivityExport {
    public static func json(_ session: TestSession) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }
    public static func csv(_ session: TestSession) -> Data {
        let rows: [String] = session.samples.map { s in
            let columns: [String] = [String(s.time), s.power.map { String($0) } ?? "", s.cadence.map { String($0) } ?? "",
                                     s.heartRate.map { String($0) } ?? "", s.trainerPower.map { String($0) } ?? "",
                                     session.configuration.resolvedPowerSource.rawValue, session.configuration.resolvedCadenceSource.rawValue]
            return columns.joined(separator: ",")
        }
        return Data((["seconds,power_watts,cadence_rpm,heart_rate_bpm,trainer_watts,power_source,cadence_source"] + rows).joined(separator: "\n").utf8)
    }
    public static func tcx(_ session: TestSession) throws -> Data {
        guard let end = session.endedAtOffset else { throw ExportError.notFinalized }
        guard !session.samples.isEmpty else { throw ExportError.emptyActivity }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func timestamp(_ offset: Double) -> String { iso.string(from: session.startedAt.addingTimeInterval(offset)) }
        let boundaries = Set([0, session.rampStart, session.rampEnd, end].compactMap { $0 }.filter { $0 >= 0 && $0 <= end }).sorted()
        var laps = ""
        for (a, b) in zip(boundaries, boundaries.dropFirst()) where b > a {
            let points = session.samples.filter { $0.time >= a && ($0.time < b || b == end && $0.time == b) }.map { sample -> String in
                let hr = sample.heartRate.map { "<HeartRateBpm><Value>\($0)</Value></HeartRateBpm>" } ?? ""
                let cadence = sample.cadence.map { "<Cadence>\(Int(min(254, max(0, $0.rounded()))))</Cadence>" } ?? ""
                let watts = sample.power.map { "<Extensions><ns3:TPX><ns3:Watts>\(Int(max(0, $0.rounded())))</ns3:Watts></ns3:TPX></Extensions>" } ?? ""
                return "<Trackpoint><Time>\(timestamp(sample.time))</Time>\(hr)\(cadence)\(watts)</Trackpoint>"
            }.joined()
            // TCX requires a lap distance and calories; indoor distance is unmeasured.
            laps += "<Lap StartTime=\"\(timestamp(a))\"><TotalTimeSeconds>\(b - a)</TotalTimeSeconds><DistanceMeters>0</DistanceMeters><Calories>0</Calories><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod><Track>\(points)</Track></Lap>"
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2"><Activities><Activity Sport="Biking"><Id>\(timestamp(0))</Id>\(laps)<Notes>\(escaped(description(session)))</Notes></Activity></Activities></TrainingCenterDatabase>
        """
        return Data(xml.utf8)
    }
    public static func description(_ session: TestSession) -> String {
        var text = "FTPunk \(session.configuration.preset.title). \(session.outcome?.title ?? "Recording")."
        text += " Rider: \(session.riderName)."
        text += " Power source: \(session.configuration.resolvedPowerSource.title). Cadence source: \(session.configuration.resolvedCadenceSource.title)."
        if session.isDemo { text = "DEMO — synthetic activity. " + text }
        if let ftp = session.configuration.priorFTP { text += " Prior FTP: \(ftp.watts) W." }
        if let weight = session.configuration.weightKG { text += " Weight: \(weight) kg." }
        if let result = session.result { text += " Estimated FTP: \(result.estimatedFTP) W (\(Int(result.factor * 100))% of best 60 seconds)." }
        return text
    }
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
