import Foundation

public enum WorkoutPhase: String, Sendable {
    case waiting, warmup, ramp, cooldown, completed, interrupted
    public var title: String {
        switch self {
        case .waiting: "Start pedaling"
        case .warmup: "Warm-up"
        case .ramp: "Ramp test"
        case .cooldown: "Cooldown"
        case .completed: "Activity saved"
        case .interrupted: "Interrupted"
        }
    }
    public var isActive: Bool { self != .completed && self != .interrupted }
}

/// Deterministic state machine: all times are monotonic offsets supplied by its owner.
public struct RampEngine: Sendable {
    public private(set) var phase: WorkoutPhase = .waiting
    public private(set) var session: TestSession
    public private(set) var targetPower: Int?
    public private(set) var phaseStartedAt: Double = 0
    public private(set) var lastPower: PowerSample?
    public private(set) var lastCadence: (time: Double, rpm: Double)?
    private var lowCadenceSince: Double?
    private var lastTick: Double = 0

    public init(configuration: SessionConfiguration, isDemo: Bool = false, date: Date = Date(), devices: [DeviceSnapshot] = []) {
        session = TestSession(startedAt: date, configuration: configuration, isDemo: isDemo, devices: devices)
    }

    public mutating func receive(_ sample: RideSample) {
        guard phase.isActive, sample.time.isFinite, sample.time >= 0 else { return }
        if let power = sample.power, power.isFinite, lastPower.map({ sample.time > $0.time }) ?? true {
            lastPower = PowerSample(time: sample.time, watts: power)
        }
        if let cadence = sample.cadence, cadence.isFinite, cadence >= 0,
           lastCadence.map({ sample.time > $0.time }) ?? true {
            lastCadence = (sample.time, cadence)
        }
        session.samples.append(sample)
    }

    public mutating func tick(at time: Double) {
        guard phase.isActive, time.isFinite, time >= lastTick else { return }
        defer { lastTick = time }
        if time - lastTick > 3, phase != .waiting {
            interrupt(at: time, reason: "Workout scheduling was interrupted."); return
        }
        let fresh = lastPower.map({ time >= $0.time && time - $0.time <= 2 }) ?? false
        if phase != .waiting && !fresh {
            interrupt(at: time, reason: "Power from the selected source is no longer fresh."); return
        }
        switch phase {
        case .waiting:
            let moving = session.configuration.resolvedCadenceSource == .unavailable
                ? (lastPower?.watts ?? 0) > 0
                : lastCadence.map { time - $0.time <= 2 && $0.rpm >= 20 } ?? false
            if fresh && moving {
                transition(to: .warmup, at: time)
                targetPower = session.configuration.warmupPower
            }
        case .warmup:
            if time - phaseStartedAt >= session.configuration.warmupSeconds {
                let boundary = phaseStartedAt + session.configuration.warmupSeconds
                transition(to: .ramp, at: boundary)
                session.rampStart = boundary
                targetPower = session.configuration.preset.startingPower
            }
        case .ramp:
            let elapsed = time - phaseStartedAt
            if session.configuration.resolvedCadenceSource != .unavailable,
               lastCadence.map({ time - $0.time <= 2 }) != true {
                interrupt(at: time, reason: "Cadence from the selected source is no longer fresh."); return
            }
            if elapsed >= session.configuration.maximumRampSeconds ||
                session.configuration.preset.startingPower + Int(elapsed / session.configuration.preset.stepSeconds) * session.configuration.preset.stepWatts > session.configuration.maximumPower {
                finishRamp(at: time, outcome: .limitReached); return
            }
            targetPower = session.configuration.rampPower(at: elapsed)
            if session.configuration.resolvedCadenceSource != .unavailable,
               elapsed >= 10, let cadence = lastCadence, cadence.rpm < 45 {
                if lowCadenceSince == nil { lowCadenceSince = time }
                if let onset = lowCadenceSince, time - onset >= 5 {
                    finishRamp(at: onset, outcome: .exhaustion, cooldownStart: time)
                }
            } else { lowCadenceSince = nil }
        case .cooldown:
            if time - phaseStartedAt >= session.configuration.cooldownSeconds { endActivity(at: time) }
        case .completed, .interrupted: break
        }
    }

    public mutating func finishRamp(at time: Double, outcome: SessionOutcome = .finishedEarly, cooldownStart: Double? = nil) {
        guard phase == .ramp else { return }
        session.outcome = outcome; session.rampEnd = time
        if outcome.allowsEstimate, let start = session.rampStart {
            let samples = session.samples.compactMap { sample in sample.power.map { PowerSample(time: sample.time, watts: $0) } }
            session.result = try? FTPAnalysis.calculate(samples: samples, start: start, end: time,
                                                       weightKG: session.configuration.weightKG, factor: session.configuration.ftpFactor)
        }
        transition(to: .cooldown, at: cooldownStart ?? time)
        targetPower = session.configuration.preset.cooldownPower
    }

    public mutating func endActivity(at time: Double) {
        guard phase.isActive else { return }
        if phase == .ramp { finishRamp(at: time) }
        if session.outcome == nil { session.outcome = .aborted }
        session.endedAtOffset = time
        transition(to: .completed, at: time)
        targetPower = nil
    }

    public mutating func interrupt(at time: Double, reason: String) {
        guard phase.isActive else { return }
        // A completed scored ramp stays usable if only the optional cooldown was interrupted.
        if phase != .cooldown { session.outcome = .interrupted; session.result = nil }
        session.endReason = reason; session.endedAtOffset = time
        transition(to: .interrupted, at: time); targetPower = nil
    }

    public mutating func recordEvent(at time: Double, message: String) {
        session.events.append(SessionEvent(time: time, message: message))
    }

    private mutating func transition(to phase: WorkoutPhase, at time: Double) {
        self.phase = phase; phaseStartedAt = time
        recordEvent(at: time, message: phase.title)
    }
}
