import Foundation

/// A drawable slice of a workout: constant or ramped target over a span of seconds.
public struct ProfileSegment: Equatable, Sendable {
    public let name: String
    public let start: Double
    public let end: Double
    public let startWatts: Double
    public let endWatts: Double
    public var seconds: Double { end - start }
    public var averageWatts: Double { (startWatts + endWatts) / 2 }
}

public enum WorkoutProfile {
    /// Segments at the given intensity (percent). Targets are the plan's original watts scaled once.
    public static func segments(for plan: TrainingPlan, intensity: Int = 100) -> [ProfileSegment] {
        var cursor = 0.0
        let scale = Double(intensity) / 100
        return plan.steps.map { step in
            defer { cursor += step.seconds }
            return ProfileSegment(name: step.name, start: cursor, end: cursor + step.seconds,
                                  startWatts: Double(step.watts) * scale, endWatts: Double(step.endWatts ?? step.watts) * scale)
        }
    }
    /// Highest target in the plan, for scaling charts.
    public static func peakWatts(for plan: TrainingPlan, intensity: Int = 100) -> Double {
        segments(for: plan, intensity: intensity).map { max($0.startWatts, $0.endWatts) }.max() ?? 0
    }
    /// Time-weighted average target in watts.
    public static func averageWatts(for plan: TrainingPlan) -> Double {
        guard plan.duration > 0 else { return 0 }
        return segments(for: plan).reduce(0) { $0 + $1.averageWatts * $1.seconds } / plan.duration
    }
    /// Average target as a fraction of the plan's FTP snapshot, when it has one.
    public static func averageFraction(for plan: TrainingPlan) -> Double? {
        plan.ftpWatts.map { averageWatts(for: plan) / $0 }
    }
}

/// Training zones by share of FTP, as used by the workout profile charts. Percent is rounded to a whole number first:
/// recovery up to 55 %, endurance 56–75, tempo 76–87, sweet spot 88–94, threshold 95–105, VO2max from 106.
public enum IntensityZone: Int, CaseIterable, Comparable, Sendable {
    case recovery, endurance, tempo, sweetSpot, threshold, vo2max

    public static func zone(forFraction fraction: Double) -> IntensityZone {
        guard fraction.isFinite else { return fraction > 0 ? .vo2max : .recovery }
        switch Int((fraction * 100).rounded()) {
        case ..<56: return .recovery
        case 56...75: return .endurance
        case 76...87: return .tempo
        case 88...94: return .sweetSpot
        case 95...105: return .threshold
        default: return .vo2max
        }
    }
    public var title: String {
        switch self {
        case .recovery: "Recovery"
        case .endurance: "Endurance"
        case .tempo: "Tempo"
        case .sweetSpot: "Sweet spot"
        case .threshold: "Threshold"
        case .vo2max: "VO2max"
        }
    }
    public static func < (lhs: IntensityZone, rhs: IntensityZone) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One bar (or sloped ramp) of a profile chart. Positions are fractions of the chart: `start`/`end` across the
/// duration, `startHeight`/`endHeight` up the fixed intensity scale (0 at 0 % FTP, 1 at `WorkoutProfile.scaleMaxPercent`).
public struct ProfileBar: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let startHeight: Double
    public let endHeight: Double
    /// Nil when the plan has no FTP, so there is nothing to compare intensity with.
    public let zone: IntensityZone?
}

public extension WorkoutProfile {
    /// Top of the fixed vertical scale, in percent of FTP. Steps above it are clamped.
    static let scaleMaxPercent = 130.0

    /// Bars on a fixed 0–130 % of FTP scale, so VO2max looks taller than tempo on every card. Ramps keep their
    /// slope; the zone comes from a segment's average. Without an FTP the heights fall back to the plan's own peak
    /// and no zone is given (neutral drawing).
    static func bars(for plan: TrainingPlan, intensity: Int = 100) -> [ProfileBar] {
        let segments = segments(for: plan, intensity: intensity)
        let total = max(1, plan.duration)
        let ftp = plan.ftpWatts.flatMap { $0 > 0 ? $0 : nil }
        let reference = ftp.map { $0 * scaleMaxPercent / 100 } ?? max(1, peakWatts(for: plan, intensity: intensity))
        func height(_ watts: Double) -> Double { min(1, max(0, watts / reference)) }
        return segments.map { segment in
            ProfileBar(start: segment.start / total, end: segment.end / total,
                       startHeight: height(segment.startWatts), endHeight: height(segment.endWatts),
                       zone: ftp.map { IntensityZone.zone(forFraction: segment.averageWatts / $0) })
        }
    }
}

/// Plain-words intensity for workouts that are not in the built-in catalog.
public enum IntensityLabel {
    /// Based on the hardest constant-power step relative to the FTP the plan was resolved at.
    public static func label(for plan: TrainingPlan) -> String {
        guard let ftp = plan.ftpWatts, ftp > 0,
              let hardest = plan.steps.filter({ $0.endWatts == nil }).map(\.watts).max() else { return "Custom power targets" }
        let fraction = Double(hardest) / ftp
        switch fraction {
        case ..<0.56: return "Easy · active recovery"
        case ..<0.76: return "Endurance"
        case ..<0.91: return "Tempo"
        case ..<1.06: return "Threshold"
        default: return "VO2max and above"
        }
    }
    /// The hardest constant-power step, in watts, for a card caption.
    public static func mainSetWatts(for plan: TrainingPlan) -> Int? {
        plan.steps.filter { $0.endWatts == nil }.map(\.watts).max()
    }
}
