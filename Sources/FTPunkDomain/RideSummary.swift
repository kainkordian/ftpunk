import Foundation

/// The figures a finished ride shows: averages, normalized power and the peaks. Computed from the recorded samples only.
public struct RideSummary: Equatable, Sendable {
    public var duration: Double
    public var averagePower: Double?
    public var normalizedPower: Double?
    public var maximumPower: Double?
    public var averageHeartRate: Double?
    public var maximumHeartRate: Int?
    /// Average cadence while pedalling (zeros, i.e. coasting and stops, are left out, as other ride apps do).
    public var averageCadence: Double?
    /// Work done, the rider's estimated energy use and the simulated distance. Nil when no power was recorded.
    public var kilojoules: Double? = nil
    public var kilocalories: Double? = nil
    public var distance: Double? = nil
    /// The left leg's share of the ride's work, in percent. Nil when balance was not reported.
    public var leftBalance: Double? = nil

    public static func make(_ session: TestSession) -> RideSummary {
        let samples = session.samples
        let power = Series(samples) { $0.power }
        let track = RideTrack.make(session), ridden = !track.points.isEmpty
        return RideSummary(
            duration: session.endedAtOffset ?? samples.last?.time ?? 0,
            averagePower: power.average(),
            normalizedPower: normalizedPower(samples),
            maximumPower: samples.compactMap(\.power).filter(\.isFinite).max(),
            averageHeartRate: Series(samples) { $0.heartRate.map(Double.init) }.average(includeZero: false),
            maximumHeartRate: samples.compactMap(\.heartRate).max(),
            averageCadence: Series(samples) { $0.cadence }.average(includeZero: false),
            kilojoules: ridden ? track.kilojoules : nil,
            kilocalories: ridden ? track.kilocalories : nil,
            distance: ridden ? track.distance : nil,
            leftBalance: RideBalance.make(session, track: track)?.left)
    }

    /// Normalized power: a 30-second rolling mean of one-second power, raised to the fourth power, averaged, and rooted.
    /// Needs at least 30 seconds of riding; gaps longer than two seconds (pauses) are skipped, not counted as zeros.
    public static func normalizedPower(_ samples: [RideSample]) -> Double? {
        let perSecond = oneHertzPower(samples)
        guard perSecond.count >= 30 else { return nil }
        var window = perSecond[0..<30].reduce(0, +)
        var fourth = 0.0, count = 0
        for end in 29..<perSecond.count {
            if end > 29 { window += perSecond[end] - perSecond[end - 30] }
            let mean = window / 30
            fourth += mean * mean * mean * mean; count += 1
        }
        return count > 0 ? pow(fourth / Double(count), 0.25) : nil
    }

    /// One value per second of riding: the mean of that second's samples, held across gaps of up to two seconds.
    static func oneHertzPower(_ samples: [RideSample]) -> [Double] {
        var result: [Double] = [], held: Double?, heldAt = -Double.infinity
        var bucket: [Double] = [], bucketSecond: Int?
        func flush() {
            if let second = bucketSecond, !bucket.isEmpty {
                let value = bucket.reduce(0, +) / Double(bucket.count)
                held = value; heldAt = Double(second)
                result.append(value)
            }
            bucket = []; bucketSecond = nil
        }
        var lastSecond: Int?
        for sample in samples {
            guard let watts = sample.power, watts.isFinite, sample.time.isFinite, sample.time >= 0 else { continue }
            let second = Int(sample.time.rounded(.down))
            if second != bucketSecond {
                flush()
                if let last = lastSecond, let held, second > last + 1 {
                    // Fill short gaps with the last value; a longer gap (a pause) leaves no entries.
                    let missing = second - last - 1
                    if Double(second) - heldAt <= 2 { result.append(contentsOf: Array(repeating: held, count: missing)) }
                }
                bucketSecond = second; lastSecond = second
            }
            bucket.append(watts)
        }
        flush()
        return result
    }

    /// Time-weighted average of an optional value over the samples, ignoring gaps over two seconds.
    struct Series {
        let points: [(time: Double, value: Double)]
        init(_ samples: [RideSample], value: (RideSample) -> Double?) {
            points = samples.compactMap { sample in value(sample).flatMap { $0.isFinite ? (sample.time, $0) : nil } }
        }
        func average(includeZero: Bool = true) -> Double? {
            var total = 0.0, seconds = 0.0
            for (previous, next) in zip(points, points.dropFirst()) {
                if !includeZero && previous.value <= 0 { continue }
                let span = min(2, max(0, next.time - previous.time))
                total += previous.value * span; seconds += span
            }
            return seconds > 0 ? total / seconds : nil
        }
    }
}

public struct TargetPoint: Equatable, Sendable {
    public let time: Double
    public let watts: Double
    /// Points with the same segment are joined by a line; a pause or a gap starts a new one.
    public let segment: Int
}

/// The ERG target the ride asked for over time, rebuilt from the session (the plan or ramp settings, the recorded phase
/// changes, pauses and intensity changes). Nothing extra is stored per sample, so older recordings have it too.
public enum TargetSeries {
    /// - Parameter from: the first second to include (a live chart only needs its visible window).
    public static func make(_ session: TestSession, from start: Double = 0) -> [TargetPoint] {
        let end = session.endedAtOffset ?? session.samples.last?.time ?? 0
        guard end > 0, let target = targetFunction(session) else { return [] }
        var points: [TargetPoint] = []
        var segment = 0, runValue: Int?, runStart = 0.0
        func close(at time: Double) {
            if let value = runValue, time > runStart {
                points.append(TargetPoint(time: runStart, watts: Double(value), segment: segment))
                points.append(TargetPoint(time: time, watts: Double(value), segment: segment))
            }
        }
        var second = max(0, Int(start.rounded(.down)))
        runStart = Double(second)
        while Double(second) < end {
            let value = target(Double(second))
            if value != runValue {
                close(at: Double(second))
                if value == nil { segment += 1 }
                runValue = value; runStart = Double(second)
            }
            second += 1
        }
        close(at: end)
        return points
    }

    private static func targetFunction(_ session: TestSession) -> ((Double) -> Int?)? {
        let events = session.events.sorted { $0.time < $1.time }
        func time(of message: String) -> Double? { events.first { $0.message == message }?.time }
        let config = session.configuration
        guard let plan = session.training else {
            let warmStart = time(of: WorkoutPhase.warmup.title)
            let rampStart = session.rampStart
            let rampEnd = session.cooldownStart ?? session.rampEnd
            let cooldown = session.cooldownStart ?? session.rampEnd
            return { t in
                if let rampStart, t >= rampStart, rampEnd.map({ t < $0 }) ?? true { return config.rampPower(at: t - rampStart) }
                if let warmStart, t >= warmStart, rampStart.map({ t < $0 }) ?? true { return config.warmupPower }
                if let cooldown, t >= cooldown, session.outcome != .exhaustion { return config.preset.cooldownPower }
                return nil
            }
        }
        guard plan.resistance == nil, let begin = time(of: WorkoutPhase.riding.title) else { return nil }
        var pauses: [(start: Double, end: Double)] = [], requested: Double?
        for event in events {
            if event.message == "Training paused; trainer release requested" { requested = event.time }
            else if event.message == "Training resumed", let start = requested { pauses.append((start, event.time)); requested = nil }
        }
        if let requested { pauses.append((requested, .infinity)) }
        let intensityChanges: [(Double, Int)] = events.compactMap { event in
            let prefix = "Workout intensity changed to ", suffix = "%"
            guard event.message.hasPrefix(prefix), event.message.hasSuffix(suffix),
                  let value = Int(event.message.dropFirst(prefix.count).dropLast(suffix.count)) else { return nil }
            return (event.time, value)
        }
        let ergChanges: [(Double, Int)] = events.compactMap { event in
            let prefix = "ERG target changed to ", suffix = " W"
            guard event.message.hasPrefix(prefix), event.message.hasSuffix(suffix),
                  let value = Int(event.message.dropFirst(prefix.count).dropLast(suffix.count)) else { return nil }
            return (event.time, value)
        }
        return { t in
            guard t >= begin else { return nil }
            var paused = 0.0
            for pause in pauses {
                if t >= pause.start && t < pause.end { return nil }
                if t >= pause.end { paused += pause.end - pause.start }
            }
            if plan.kind == .freeRide {
                return ergChanges.last { $0.0 <= t }?.1 ?? plan.steps.first?.watts
            }
            let intensity = intensityChanges.last { $0.0 <= t }?.1 ?? 100
            return plan.target(at: t - begin - paused, intensity: intensity)
        }
    }
}

/// Decides when a workout pauses itself because the rider stopped pedalling, and when it resumes once they start again.
/// A pause the rider made by hand is never resumed automatically.
public struct AutoPause: Sendable {
    public enum Action: Equatable, Sendable { case pause, resume }
    public static let stopSeconds = 3.0
    public static let startSeconds = 2.0
    private var stoppedSince: Double?
    private var pedallingSince: Double?
    private var automatic = false
    public init() {}

    /// - Parameters:
    ///   - phase: the ride's current phase; only `.riding` can pause, only an automatic `.paused` can resume.
    ///   - power: the selected source's latest reading, or nil when it is not fresh.
    ///   - canResume: the engine's own check that fresh power and cadence are arriving.
    public mutating func update(time: Double, phase: WorkoutPhase, power: Double?, canResume: Bool) -> Action? {
        switch phase {
        case .riding:
            pedallingSince = nil
            guard let power, power < 1 else { stoppedSince = nil; automatic = false; return nil }
            let since = stoppedSince ?? time
            stoppedSince = since
            if time - since >= Self.stopSeconds { automatic = true; return .pause }
            return nil
        case .paused:
            stoppedSince = nil
            guard automatic, canResume else { pedallingSince = nil; return nil }
            let since = pedallingSince ?? time
            pedallingSince = since
            if time - since >= Self.startSeconds { automatic = false; pedallingSince = nil; return .resume }
            return nil
        default:
            self = AutoPause()
            return nil
        }
    }
}
