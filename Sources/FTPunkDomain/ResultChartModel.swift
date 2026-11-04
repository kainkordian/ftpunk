import Foundation

public struct ResultBand: Equatable, Sendable {
    public let title: String
    public let start: Double
    public let end: Double
}

/// What the result chart draws behind the power line: phase bands and the best-minute window.
public enum ResultChartModel {
    public static func bands(for session: TestSession) -> [ResultBand] {
        guard session.training == nil else { return [] }
        let end = session.endedAtOffset ?? session.samples.last?.time ?? 0
        var bands: [ResultBand] = []
        if let rampStart = session.rampStart {
            if rampStart > 0 { bands.append(ResultBand(title: "Warm-up", start: 0, end: rampStart)) }
            let rampEnd = session.rampEnd ?? end
            if rampEnd > rampStart { bands.append(ResultBand(title: "Ramp", start: rampStart, end: rampEnd)) }
            if let cooldown = session.cooldownStart ?? session.rampEnd, end > cooldown { bands.append(ResultBand(title: "Cool-down", start: cooldown, end: end)) }
        } else if end > 0 {
            bands.append(ResultBand(title: "Warm-up", start: 0, end: end))
        }
        return bands
    }
    public static func bestMinute(for session: TestSession) -> ResultBand? {
        session.result.map { ResultBand(title: "Best minute \(Int($0.bestMinutePower.rounded())) W", start: $0.windowStart, end: $0.windowEnd) }
    }
}

/// Label placement rules for the result chart. Phase labels sit at the left edge of their band and may never be
/// wider than it, so two labels cannot overlap; a band too narrow for even the short form gets no label (the
/// chart's accessibility value still names every phase). The best-minute label is clamped inside the plot.
public enum ResultChartLayout {
    /// The forms a label may take, longest first.
    public static func candidates(for title: String) -> [String] {
        switch title {
        case "Warm-up": return ["Warm-up", "Warm"]
        case "Cool-down": return ["Cool-down", "Cool"]
        default:
            let prefix = "Best minute "
            if title.hasPrefix(prefix) { return [title, "Best " + title.dropFirst(prefix.count)] }
            return [title]
        }
    }
    public static func estimatedWidth(of text: String, characterWidth: Double) -> Double { Double(text.count) * max(1, characterWidth) }

    /// The longest form of `title` that fits `availableWidth` points, or nil if none does.
    public static func fittingLabel(for title: String, availableWidth: Double, characterWidth: Double) -> String? {
        guard availableWidth.isFinite else { return nil }
        return candidates(for: title).first { estimatedWidth(of: $0, characterWidth: characterWidth) <= availableWidth }
    }

    /// Left edge for a label of `width` centred on `centre`, kept inside a plot `plotWidth` wide.
    public static func clampedLeading(centre: Double, width: Double, plotWidth: Double) -> Double {
        guard plotWidth.isFinite, width.isFinite, centre.isFinite else { return 0 }
        return min(max(0, centre - width / 2), max(0, plotWidth - width))
    }

    /// Vertical headroom above the highest power so the two label rows never touch the line.
    public static func ceiling(forPeak peak: Double) -> Double { max(100, peak.isFinite ? peak : 0) * 1.32 }
}
