import Foundation

public enum LivePower {
    public static let windows = [3, 10, 30, 60]
    /// Zero-order hold, bounded to fresh signal spans. Pause boundaries clip the integral.
    public static func average(samples: [RideSample], at time: Double, window: Int, pauses: [RidePause] = []) -> Double? {
        guard windows.contains(window), time.isFinite else { return nil }
        let points = samples.filter { $0.time <= time && $0.power?.isFinite == true }.sorted { $0.time < $1.time }
        guard let newest = points.last, time - newest.time <= 2 else { return nil }
        var energy = 0.0, duration = 0.0
        for (i, point) in points.enumerated() {
            let start = max(time - Double(window), point.time)
            let end = min(time, point.time + 2, i + 1 < points.count ? points[i + 1].time : time)
            guard end > start else { continue }
            var seconds = end - start
            for pause in pauses { seconds -= max(0, min(end, pause.resume ?? time) - max(start, pause.stop)) }
            seconds = max(0, seconds)
            energy += (point.power ?? 0) * seconds; duration += seconds
        }
        return duration > 0 ? energy / duration : pauses.contains(where: { $0.contains(newest.time) }) ? nil : newest.power
    }
}

public enum StepHeartRate {
    public static func averages(session: TestSession) -> [Double?] {
        guard let plan = session.training, let clock = WorkoutClock(session) else { return [] }
        let endTime = session.endedAtOffset ?? session.samples.last?.time ?? 0
        let end = clock.trainingTime(at: endTime) ?? session.events.last(where: { $0.time <= endTime && $0.message == "Training paused; trainer release requested" }).flatMap { clock.trainingTime(at: max(0, $0.time - 0.000001)).map { $0 + 0.000001 } } ?? 0
        var start = 0.0
        return plan.steps.map { step in
            defer { start += step.seconds }
            guard start + step.seconds <= end else { return nil }
            let values = session.samples.compactMap { sample -> Double? in
                guard let bpm = sample.heartRate, bpm > 0, let t = clock.trainingTime(at: sample.time), t >= start, t < start + step.seconds else { return nil }
                return Double(bpm)
            }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }
}

public struct DashboardMetrics: Equatable, Sendable {
    public let scale, hero, reading, caption, target, headerHeight, heroHeight, readingHeight, stripHeight, gap, padding: Double
    public static func make(width: Double, height: Double, accessibilitySize: Bool = false, compact: Bool = false) -> Self {
        let scale = max(0.1, min(width / 1470, height / 920))
        let numberScale = compact ? scale * 0.8 : scale
        let header = 60 * scale, heroRow = 372 * scale, readingRow = 252 * scale
        return Self(scale: scale, hero: max(96, 220 * numberScale), reading: max(64, 185 * numberScale),
                    caption: max(15, 30 * scale), target: 76 * numberScale, headerHeight: header,
                    heroHeight: heroRow, readingHeight: readingRow,
                    stripHeight: max(0, height - header - heroRow - readingRow - 92 * scale), gap: 16 * scale, padding: 24 * scale)
    }
}

public struct DashboardSlots: Equatable, Sendable {
    public enum Content: Equatable, Sendable { case power, stepTime, rideTime, phaseTime, heartRate, cadence, next, firstStep, bestMinute, averagePower, profile, liveChart, timeline, rampNext }
    public let focus: Bool
    public let a, b, c, d, e, f: Content
    public static func make(kind: CockpitKind, phase: WorkoutPhase) -> Self {
        if kind == .ftpTest && phase == .ramp { return Self(focus: true, a: .power, b: .cadence, c: .heartRate, d: .rampNext, e: .bestMinute, f: .timeline) }
        return Self(focus: false, a: .power, b: kind == .workout ? .stepTime : kind == .freeRide ? .rideTime : .phaseTime,
                    c: .heartRate, d: .cadence, e: kind == .workout ? .next : kind == .freeRide ? .averagePower : phase == .cooldown ? .bestMinute : .firstStep,
                    f: kind == .workout ? .profile : kind == .freeRide ? .liveChart : .timeline)
    }
}

public enum StepCue {
    public static func due(remaining: Double, previous: Double?) -> [Int] {
        guard let previous, remaining >= 0, previous > remaining else { return [] }
        return [3, 2, 1].filter { previous > Double($0) && remaining <= Double($0) }
    }
}

public enum RampCadenceState: Equatable, Sendable {
    case normal, speedUp, ending(Int), noSignal
    public static func make(cadence: Double?, at time: Double, lowCadenceSince: Double?) -> Self {
        guard let cadence else { return .noSignal }
        if cadence < 45, let onset = lowCadenceSince { return .ending(max(0, Int(ceil(5 - (time - onset))))) }
        return cadence < 60 ? .speedUp : .normal
    }
}

/// Elapsed segments fill left-to-right, then reset to empty at a step boundary.
public enum StepSegments {
    public static func filled(remaining: Double, stepSeconds: Double) -> Int {
        guard remaining.isFinite, stepSeconds.isFinite, stepSeconds > 0 else { return 0 }
        return min(12, max(0, Int(((1 - remaining / stepSeconds) * 12 + 0.000001).rounded(.down))))
    }
}
