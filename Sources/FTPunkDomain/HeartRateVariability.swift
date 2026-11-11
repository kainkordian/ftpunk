import Foundation

/// Heart-rate variability from the strap's beat-to-beat (RR) intervals.
///
/// - RMSSD: the root mean square of successive differences, in milliseconds, over the whole ride. During exercise it is
///   small and mostly tells how hard the ride was; it is shown because it is the figure people know.
/// - DFA α1: the short-term scaling exponent of detrended fluctuation analysis (box sizes 4–16 beats) in two-minute
///   windows. Around 1.0 at easy effort, it falls with intensity: about 0.75 near the aerobic threshold and 0.5 near the
///   anaerobic one (Rogers et al. 2021). It needs clean data, so windows with more than 5 % rejected beats are left out.
public enum HeartRateVariability {
    public struct Beat: Equatable, Sendable {
        public var time: Double
        /// RR interval in seconds.
        public var interval: Double
    }

    public struct AlphaPoint: Equatable, Sendable {
        /// The end of the two-minute window, in ride seconds.
        public var time: Double
        public var alpha1: Double
    }

    public struct Result: Equatable, Sendable {
        public var rmssd: Double?
        /// Share of the strap's intervals rejected as artifacts (missed or extra beats), 0–1.
        public var artifactShare: Double
        public var alpha1: [AlphaPoint]
    }

    public static let windowSeconds = 120.0
    public static let stepSeconds = 30.0
    public static let maximumArtifactShare = 0.05

    /// Nil when the ride has no RR intervals.
    public static func make(_ session: TestSession) -> Result? {
        let all = beats(session)
        guard all.count >= 30 else { return nil }
        let (clean, accepted) = filtered(all)
        let rejected = Double(all.count - clean.count) / Double(all.count)
        return Result(rmssd: rmssd(clean.map(\.interval)), artifactShare: rejected, alpha1: alpha1Series(all, accepted: accepted))
    }

    /// Every RR interval outside pauses, timed by its beat: a notification carries the intervals that ended at or before it,
    /// so the last one is placed at the notification and the earlier ones before it.
    public static func beats(_ session: TestSession) -> [Beat] {
        let pauses = RidePause.list(session)
        var result: [Beat] = []
        for sample in session.samples where !pauses.contains(where: { $0.contains(sample.time) }) {
            guard let intervals = sample.rrIntervals, !intervals.isEmpty else { continue }
            var time = sample.time
            var placed: [Beat] = []
            for interval in intervals.reversed() where interval.isFinite && interval > 0 {
                placed.append(Beat(time: time, interval: interval)); time -= interval
            }
            result.append(contentsOf: placed.reversed())
        }
        return result
    }

    /// Drops intervals outside 0.25–2 s (240–30 bpm) and those more than 20 % from the median of the last five accepted
    /// ones (a missed or an extra beat). Returns the kept beats and, for each input beat, whether it was kept.
    static func filtered(_ beats: [Beat]) -> (kept: [Beat], accepted: [Bool]) {
        var kept: [Beat] = [], accepted: [Bool] = []
        for beat in beats {
            var ok = beat.interval >= 0.25 && beat.interval <= 2
            if ok, kept.count >= 3 {
                let recent = kept.suffix(5).map(\.interval).sorted()
                let median = recent[recent.count / 2]
                ok = abs(beat.interval - median) <= 0.2 * median
            }
            if ok { kept.append(beat) }
            accepted.append(ok)
        }
        return (kept, accepted)
    }

    /// RMSSD in milliseconds; nil with fewer than 30 intervals.
    public static func rmssd(_ intervals: [Double]) -> Double? {
        guard intervals.count >= 30 else { return nil }
        var sum = 0.0
        for index in 1..<intervals.count {
            let difference = (intervals[index] - intervals[index - 1]) * 1000
            sum += difference * difference
        }
        return (sum / Double(intervals.count - 1)).squareRoot()
    }

    /// DFA α1 over box sizes 4–16; nil with fewer than 50 intervals.
    public static func alpha1(_ intervals: [Double]) -> Double? {
        guard intervals.count >= 50 else { return nil }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        var profile: [Double] = [], running = 0.0
        for value in intervals { running += value - mean; profile.append(running) }
        var logN: [Double] = [], logF: [Double] = []
        for size in 4...16 {
            let boxes = profile.count / size
            guard boxes > 0 else { continue }
            var squares = 0.0
            for box in 0..<boxes {
                let slice = Array(profile[(box * size)..<((box + 1) * size)])
                squares += residualSquares(slice)
            }
            let fluctuation = (squares / Double(boxes * size)).squareRoot()
            guard fluctuation > 0 else { continue }
            logN.append(log10(Double(size))); logF.append(log10(fluctuation))
        }
        guard logN.count >= 3 else { return nil }
        let slope = slopeOf(logF, over: logN)
        return slope.isFinite ? slope : nil
    }

    /// α1 in two-minute windows every 30 s. A window counts when at most 5 % of its beats were rejected.
    static func alpha1Series(_ beats: [Beat], accepted: [Bool]) -> [AlphaPoint] {
        guard let first = beats.first?.time, let last = beats.last?.time, last - first >= windowSeconds else { return [] }
        var points: [AlphaPoint] = []
        var end = first + windowSeconds, lower = 0
        while end <= last + 0.001 {
            while lower < beats.count, beats[lower].time < end - windowSeconds { lower += 1 }
            var upper = lower, total = 0, rejected = 0
            var intervals: [Double] = []
            while upper < beats.count, beats[upper].time <= end {
                total += 1
                if accepted[upper] { intervals.append(beats[upper].interval) } else { rejected += 1 }
                upper += 1
            }
            // A window spanning a pause has a hole; its beats are not one continuous series.
            let continuous = zip(beats[lower..<upper], beats[lower..<upper].dropFirst()).allSatisfy { $1.time - $0.time <= 3 }
            if total > 0, continuous, Double(rejected) / Double(total) <= maximumArtifactShare, let alpha = alpha1(intervals) {
                points.append(AlphaPoint(time: end, alpha1: alpha))
            }
            end += stepSeconds
        }
        return points
    }

    /// Sum of squared residuals of a least-squares line through `values` at x = 0, 1, 2, …
    private static func residualSquares(_ values: [Double]) -> Double {
        let xs = values.indices.map(Double.init)
        let slope = slopeOf(values, over: xs)
        let meanX = xs.reduce(0, +) / Double(xs.count), meanY = values.reduce(0, +) / Double(values.count)
        let intercept = meanY - slope * meanX
        return zip(xs, values).reduce(0) { sum, point in
            let residual = point.1 - (intercept + slope * point.0)
            return sum + residual * residual
        }
    }

    private static func slopeOf(_ ys: [Double], over xs: [Double]) -> Double {
        let meanX = xs.reduce(0, +) / Double(xs.count), meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0, denominator = 0.0
        for (x, y) in zip(xs, ys) { numerator += (x - meanX) * (y - meanY); denominator += (x - meanX) * (x - meanX) }
        return denominator > 0 ? numerator / denominator : .nan
    }
}
