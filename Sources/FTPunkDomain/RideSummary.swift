import Foundation

/// The figures a finished ride shows: averages, normalized power and the peaks. Computed from the recorded samples only; samples that
/// arrive during a pause don't count, and `duration` is the elapsed time including pauses.
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
    /// The trainer's own power, only while a power meter was the ride's source (otherwise it is the same number as above).
    public var trainerAveragePower: Double? = nil
    public var trainerNormalizedPower: Double? = nil

    public static func make(_ session: TestSession) -> RideSummary {
        let pauses = RidePause.list(session)
        let samples = session.samples.filter { sample in !pauses.contains { $0.contains(sample.time) } }
        let power = Series(samples) { $0.power }
        let track = RideTrack.make(session), ridden = !track.points.isEmpty
        let trainer = trainerSamples(session, unpaused: samples)
        return RideSummary(
            duration: session.endedAtOffset ?? session.samples.last?.time ?? 0,
            averagePower: power.average(),
            normalizedPower: TrainingLoad.make(session, track: track).normalizedPower,
            maximumPower: samples.compactMap(\.power).filter(\.isFinite).max(),
            averageHeartRate: Series(samples) { $0.heartRate.map(Double.init) }.average(includeZero: false),
            maximumHeartRate: samples.compactMap(\.heartRate).max(),
            averageCadence: Series(samples) { $0.cadence }.average(includeZero: false),
            kilojoules: ridden ? track.kilojoules : nil,
            kilocalories: ridden ? track.kilocalories : nil,
            distance: ridden ? track.distance : nil,
            leftBalance: RideBalance.make(session, track: track)?.left,
            trainerAveragePower: trainer.flatMap { Series($0) { $0.power }.average() },
            trainerNormalizedPower: trainer.flatMap { normalizedPower($0, pauses: pauses) })
    }

    /// The trainer's readings as power samples, when a meter was the source and the trainer reported power.
    private static func trainerSamples(_ session: TestSession, unpaused samples: [RideSample]) -> [RideSample]? {
        guard session.configuration.resolvedPowerSource == .externalPowerMeter else { return nil }
        let trainer = samples.compactMap { sample in sample.trainerPower.map { RideSample(time: sample.time, power: $0) } }
        return trainer.isEmpty ? nil : trainer
    }

    /// Normalized power: a 30-second rolling mean of one-second power, raised to the fourth power, averaged, and rooted.
    /// Needs at least 30 seconds of riding; gaps longer than two seconds (pauses) are skipped, not counted as zeros. Samples inside
    /// `pauses` keep arriving but don't count. The root is two square roots because `pow` can differ between platforms and the FIT
    /// files written here and by the web app must match byte for byte.
    public static func normalizedPower(_ samples: [RideSample], pauses: [RidePause] = []) -> Double? {
        let perSecond = oneHertzPower(samples, pauses: pauses)
        guard perSecond.count >= 30 else { return nil }
        var window = perSecond[0..<30].reduce(0, +)
        var fourth = 0.0, count = 0
        for end in 29..<perSecond.count {
            if end > 29 { window += perSecond[end] - perSecond[end - 30] }
            let mean = window / 30
            fourth += mean * mean * mean * mean; count += 1
        }
        guard count > 0 else { return nil }
        let root = (fourth / Double(count)).squareRoot().squareRoot()
        return root.isFinite ? root : nil
    }

    /// One value per second of riding: the mean of that second's samples, held across gaps of up to two seconds.
    static func oneHertzPower(_ samples: [RideSample], pauses: [RidePause] = []) -> [Double] {
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
            guard let watts = sample.power, watts.isFinite, sample.time.isFinite, sample.time >= 0,
                  !pauses.contains(where: { $0.contains(sample.time) }) else { continue }
            let second = Int(sample.time.rounded(.down))
            if second != bucketSecond {
                flush()
                if let last = lastSecond, let held, second > last + 1 {
                    // Fill short gaps with the last value; a longer gap (a pause) leaves no entries.
                    let missing = ((last + 1)..<second).filter { gap in !pauses.contains { $0.contains(Double(gap)) } }.count
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

/// Normalized power, intensity factor and training stress score of a session. Paused samples don't count. NP needs 30 seconds of riding;
/// IF and TSS also need a known FTP (nil, never 0, without one).
public struct TrainingLoad: Equatable, Sendable {
    public var normalizedPower: Double?
    public var intensityFactor: Double? = nil
    public var trainingStressScore: Double? = nil

    public static func make(_ session: TestSession, track: RideTrack? = nil) -> TrainingLoad {
        let end = session.endedAtOffset ?? session.samples.last?.time ?? 0
        let normalized = RideSummary.normalizedPower(session.samples.filter { $0.time <= end }, pauses: RidePause.list(session))
        guard let power = normalized, let ftp = session.configuration.priorFTP?.watts, ftp.isFinite, ftp > 0 else {
            return TrainingLoad(normalizedPower: normalized)
        }
        let seconds = Double((track ?? RideTrack.make(session)).points.count), intensity = power / ftp
        return TrainingLoad(normalizedPower: power, intensityFactor: intensity,
                            trainingStressScore: seconds * power * intensity / (ftp * 3600) * 100)
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

    /// The target at one moment of the recording (nil when there was none, e.g. while paused).
    public static func value(_ session: TestSession, at time: Double) -> Int? { targetFunction(session)?(time) }

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
        guard plan.resistance == nil, let clock = WorkoutClock(session) else { return nil }
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
            guard let training = clock.trainingTime(at: t) else { return nil }
            if plan.kind == .freeRide {
                return ergChanges.last { $0.0 <= t }?.1 ?? plan.steps.first?.watts
            }
            let intensity = intensityChanges.last { $0.0 <= t }?.1 ?? 100
            return plan.target(at: training, intensity: intensity)
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

/// The training clock of a recorded workout, rebuilt from its events: it starts with riding, stops while paused and
/// jumps ahead when a step is skipped. Matches `RideEngine`'s own clock.
public struct WorkoutClock: Sendable {
    static let skipPrefix = "Skipped ahead "
    public static func skipMessage(seconds: Double, toStep index: Int) -> String {
        "\(skipPrefix)\(String(format: "%.1f", seconds)) s to step \(index + 1)"
    }
    public let begin: Double
    let pauses: [Pause]
    let skips: [Skip]
    struct Pause: Sendable { let start: Double, end: Double }
    struct Skip: Sendable { let time: Double, seconds: Double }

    public init?(_ session: TestSession) {
        let events = session.events.sorted { $0.time < $1.time }
        guard session.training != nil, let begin = events.first(where: { $0.message == WorkoutPhase.riding.title })?.time else { return nil }
        var pauses: [Pause] = [], skips: [Skip] = [], requested: Double?
        for event in events {
            if event.message == "Training paused; trainer release requested" { requested = event.time }
            else if event.message == "Training resumed", let start = requested { pauses.append(Pause(start: start, end: event.time)); requested = nil }
            else if event.message.hasPrefix(Self.skipPrefix),
                    let seconds = Double(event.message.dropFirst(Self.skipPrefix.count).prefix { $0 != " " }), seconds.isFinite, seconds > 0 {
                skips.append(Skip(time: event.time, seconds: seconds))
            }
        }
        if let requested { pauses.append(Pause(start: requested, end: .infinity)) }
        self.begin = begin; self.pauses = pauses; self.skips = skips
    }

    /// Training seconds at a moment of the recording; nil before riding started and while paused.
    public func trainingTime(at t: Double) -> Double? {
        guard t >= begin else { return nil }
        var paused = 0.0
        for pause in pauses {
            if t >= pause.start && t < pause.end { return nil }
            if t >= pause.end { paused += pause.end - pause.start }
        }
        let skipped = skips.reduce(0.0) { $1.time <= t ? $0 + $1.seconds : $0 }
        return t - begin - paused + skipped
    }

    /// Heart rate on the training clock, for drawing over the workout profile: at most one point per second, paused
    /// samples left out.
    public static func heartRate(_ session: TestSession) -> [(time: Double, bpm: Int)] {
        guard let clock = WorkoutClock(session) else { return [] }
        var result: [(time: Double, bpm: Int)] = []
        for sample in session.samples {
            guard let bpm = sample.heartRate, bpm > 0, let time = clock.trainingTime(at: sample.time) else { continue }
            if let last = result.last, time >= last.time, time - last.time < 1 { continue }
            result.append((time, bpm))
        }
        return result
    }
}

/// Every reading of a recording at one moment, for the charts' hover detail. Each value is the latest reading in the
/// two seconds up to that moment (the same freshness the cockpit uses), so a gap or a pause shows as no value.
public struct RideMoment: Equatable, Sendable {
    public var time: Double
    public var power: Double?
    public var target: Int?
    public var trainerPower: Double?
    public var heartRate: Int?
    public var cadence: Double?
    public var leftBalance: Double?

    public static func at(_ session: TestSession, time: Double) -> RideMoment {
        var moment = RideMoment(time: time)
        let window = session.samples.filter { $0.time <= time && time - $0.time <= 2 }
        moment.power = window.last { $0.power != nil }?.power
        moment.trainerPower = session.configuration.resolvedPowerSource == .externalPowerMeter ? window.last { $0.trainerPower != nil }?.trainerPower : nil
        moment.heartRate = window.last { $0.heartRate != nil }?.heartRate
        moment.cadence = window.last { $0.cadence != nil }?.cadence
        moment.leftBalance = window.last { $0.leftBalance != nil }?.leftBalance
        moment.target = TargetSeries.value(session, at: time)
        return moment
    }
}
