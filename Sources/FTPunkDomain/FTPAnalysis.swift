import Foundation

public enum AnalysisError: Error, LocalizedError, Equatable {
    case invalidSamples, insufficientCoverage
    public var errorDescription: String? {
        self == .invalidSamples ? "Power sample times or values are invalid." : "A complete, fresh 60-second power window is required."
    }
}

public enum FTPAnalysis {
    /// Piecewise constant integration. A measurement expires after maximumSampleAge.
    /// Candidate extrema occur at a segment boundary or one window length before it.
    public static func calculate(samples: [PowerSample], start: Double, end: Double,
                                 weightKG: Double? = nil, factor: Double = 0.72,
                                 maximumSampleAge: Double = 2) throws -> FTPResult {
        guard start.isFinite, end.isFinite, end - start >= 60, maximumSampleAge.isFinite,
              maximumSampleAge > 0, factor.isFinite, factor > 0,
              weightKG.map({ $0.isFinite && $0 > 0 }) ?? true else { throw AnalysisError.insufficientCoverage }
        guard samples.allSatisfy({ $0.time.isFinite && $0.watts.isFinite }),
              zip(samples, samples.dropFirst()).allSatisfy({ $0.time < $1.time }) else { throw AnalysisError.invalidSamples }
        struct Segment { let start: Double; let end: Double; let watts: Double }
        var segments: [Segment] = []
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].time : end
            let a = max(start, sample.time)
            let b = min(end, min(next, sample.time + maximumSampleAge))
            if b > a { segments.append(Segment(start: a, end: b, watts: sample.watts)) }
        }
        var candidates: Set<Double> = [start, end - 60]
        for segment in segments {
            for t in [segment.start, segment.end, segment.start - 60, segment.end - 60]
                where t >= start && t + 60 <= end { candidates.insert(t) }
        }
        var best: (power: Double, time: Double)?
        for window in candidates.sorted() {
            var cursor = window
            var energy = 0.0
            for segment in segments where segment.end > window && segment.start < window + 60 {
                let a = max(window, segment.start), b = min(window + 60, segment.end)
                if a > cursor + 0.000_001 { break }
                energy += (b - a) * segment.watts
                cursor = b
            }
            if cursor >= window + 60 - 0.000_001, best == nil || energy / 60 > best!.power {
                best = (energy / 60, window)
            }
        }
        guard let best, best.power > 0 else { throw AnalysisError.insufficientCoverage }
        return FTPResult(bestMinutePower: best.power, windowStart: best.time, windowEnd: best.time + 60,
                         factor: factor, weightKG: weightKG)
    }
}
