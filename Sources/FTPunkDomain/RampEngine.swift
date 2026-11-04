import Foundation

public enum WorkoutPhase: String, Sendable {
    case waiting, warmup, ramp, cooldown, riding, paused, completed, interrupted
    public var title: String {
        switch self {
        case .waiting: "Start pedaling"
        case .warmup: "Warm-up"
        case .ramp: "Ramp test"
        case .riding: "Training"
        case .paused: "Paused"
        case .cooldown: "Cooldown"
        case .completed: "Activity saved"
        case .interrupted: "Interrupted"
        }
    }
    public var isActive: Bool { self != .completed && self != .interrupted }
}

/// Deterministic state machine: all times are monotonic offsets supplied by its owner.
public struct RideEngine: Sendable {
    public private(set) var phase: WorkoutPhase = .waiting
    public private(set) var session: TestSession
    public private(set) var targetPower: Int?
    public private(set) var phaseStartedAt: Double = 0
    public private(set) var lastPower: PowerSample?
    /// What the trainer itself reports. With an external meter as the power source these arrive on their own samples,
    /// not on the meter's (each Bluetooth notification becomes one sample).
    public private(set) var lastTrainerPower: PowerSample?
    public private(set) var lastCadence: (time: Double, rpm: Double)?
    public private(set) var liveBestMinutePower: Double?
    public var isFreewheelCooldown: Bool { phase == .cooldown && session.outcome == .exhaustion }
    private var trainingStartedAt: Double?
    private var pausedAt: Double?
    private var phaseBeforePause: WorkoutPhase?
    private var pausedSeconds = 0.0
    public private(set) var intensity = 100
    private var resistanceLevel: Int?
    public var resumeResistance: Int? { resistanceLevel }
    public var targetResistance: Int? { phase == .riding ? resistanceLevel : nil }
    private var freeRideTarget: Int?
    private var lowCadenceSince: Double?
    private var lastTick: Double = 0
    private var lastLiveAnalysisAt = -Double.infinity

    public init(configuration: SessionConfiguration, isDemo: Bool = false, date: Date = Date(), devices: [DeviceSnapshot] = [], training: TrainingPlan? = nil) {
        session = TestSession(startedAt: date, configuration: configuration, isDemo: isDemo, devices: devices)
        session.training = training
        freeRideTarget = training?.resistance == nil ? training?.steps.first?.watts : nil
        resistanceLevel = training?.resistance
    }

    public mutating func receive(_ sample: RideSample) {
        guard phase.isActive, sample.time.isFinite, sample.time >= 0 else { return }
        if let power = sample.power, power.isFinite, lastPower.map({ sample.time > $0.time }) ?? true {
            lastPower = PowerSample(time: sample.time, watts: power)
        }
        if let power = sample.trainerPower, power.isFinite, lastTrainerPower.map({ sample.time > $0.time }) ?? true {
            lastTrainerPower = PowerSample(time: sample.time, watts: power)
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
        if phase == .paused { return }
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
                if let plan = session.training {
                    trainingStartedAt = time
                    transition(to: .riding, at: time); targetPower = plan.kind == .freeRide ? freeRideTarget : plan.target(at: 0, intensity: intensity)
                    return
                }
                if session.configuration.warmupSeconds == 0 {
                    transition(to: .ramp, at: time)
                    session.rampStart = time
                    targetPower = session.configuration.preset.startingPower
                } else {
                    transition(to: .warmup, at: time)
                    targetPower = session.configuration.warmupPower
                }
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
            updateLiveBestMinute(at: time)
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
        case .riding:
            guard let plan = session.training else { return }
            if plan.step(at: activeTrainingTime(at: time)) != nil {
                targetPower = plan.kind == .freeRide ? freeRideTarget : plan.target(at: activeTrainingTime(at: time), intensity: intensity)
            } else { session.outcome = .completed; endActivity(at: time) }
        case .cooldown:
            if time - phaseStartedAt >= session.configuration.cooldownSeconds { endActivity(at: time) }
        case .paused, .completed, .interrupted: break
        }
    }

    public var trainingElapsed: Double { activeTrainingTime(at: session.endedAtOffset ?? lastTick) }
    private func activeTrainingTime(at time: Double) -> Double {
        guard let start = trainingStartedAt else { return 0 }
        return max(0, (pausedAt ?? time) - start - pausedSeconds)
    }
    public var resumeTarget: Int? {
        guard let plan = session.training else { return nil }
        return plan.kind == .freeRide ? freeRideTarget : plan.target(at: trainingElapsed, intensity: intensity)
    }
    public func canResume(at time: Double) -> Bool {
        guard phase == .paused, time.isFinite, time >= lastTick,
              let power = lastPower, power.watts > 0, time >= power.time, time - power.time <= 2 else { return false }
        return session.configuration.resolvedCadenceSource == .unavailable ||
            lastCadence.map { time >= $0.time && time - $0.time <= 2 && $0.rpm >= 20 } == true
    }
    @discardableResult public mutating func pause(at time: Double) -> Bool {
        guard session.training != nil, phase == .waiting || phase == .riding,
              time.isFinite, time >= lastTick else { return false }
        tick(at: time)
        guard phase == .waiting || phase == .riding else { return false }
        phaseBeforePause = phase; pausedAt = time; phase = .paused; targetPower = nil
        recordEvent(at: time, message: "Training paused; trainer release requested")
        return true
    }
    @discardableResult public mutating func resume(at time: Double) -> Bool {
        guard canResume(at: time), let pausedAt, let previous = phaseBeforePause else { return false }
        if trainingStartedAt != nil { pausedSeconds += time - pausedAt; phaseStartedAt += time - pausedAt }
        self.pausedAt = nil; phaseBeforePause = nil; phase = previous; lastTick = time
        targetPower = previous == .riding ? resumeTarget : nil
        recordEvent(at: time, message: "Training resumed")
        return true
    }

    public var currentStep: (index: Int, step: TrainingPlan.Step, remaining: Double)? {
        session.training?.step(at: trainingElapsed)
    }
    @discardableResult public mutating func setIntensity(_ percent: Int, at time: Double, minimum: Int = 1, maximum: Int = 32767) -> Bool {
        guard phase.isActive, let plan = session.training, plan.kind == .workout,
              plan.supports(intensity: percent, minimum: minimum, maximum: maximum) else { return false }
        intensity = percent
        if phase == .riding { targetPower = plan.target(at: trainingElapsed, intensity: percent) }
        recordEvent(at: time, message: "Workout intensity changed to \(percent)%")
        return true
    }
    public mutating func adjustResistance(to level: Int, at time: Double) {
        guard phase.isActive, resistanceLevel != nil, (0...32767).contains(level) else { return }
        resistanceLevel = level; recordEvent(at: time, message: "Resistance target changed to \(Double(level) / 10)")
    }
    public mutating func adjustFreeRide(to watts: Int, at time: Double) {
        guard phase.isActive, session.training?.resistance == nil, session.training?.kind == .freeRide, (1...32767).contains(watts) else { return }
        freeRideTarget = watts
        if phase == .riding { targetPower = watts }
        recordEvent(at: time, message: "ERG target changed to \(watts) W")
    }

    public mutating func finishRamp(at time: Double, outcome: SessionOutcome = .finishedEarly, cooldownStart: Double? = nil) {
        guard phase == .ramp else { return }
        session.outcome = outcome; session.rampEnd = time
        if outcome.allowsEstimate, let start = session.rampStart {
            let samples = session.samples.compactMap { sample in sample.power.map { PowerSample(time: sample.time, watts: $0) } }
            session.result = try? FTPAnalysis.calculate(samples: samples, start: start, end: time,
                                                       weightKG: session.configuration.weightKG, factor: session.configuration.ftpFactor)
            liveBestMinutePower = session.result?.bestMinutePower ?? liveBestMinutePower
        }
        session.cooldownStart = cooldownStart ?? time
        transition(to: .cooldown, at: cooldownStart ?? time)
        targetPower = outcome == .exhaustion ? nil : session.configuration.preset.cooldownPower
        if session.configuration.cooldownSeconds == 0 { endActivity(at: cooldownStart ?? time) }
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

    private mutating func updateLiveBestMinute(at time: Double) {
        guard let start = session.rampStart, time - start >= 60, time - lastLiveAnalysisAt >= 1 else { return }
        // Reuse the scoring rules on a bounded, overlapping recent window once per second.
        // Keep the previous maximum so an earlier best minute never ages out of the display.
        let recentStart = max(start, time - 63)
        let samples = session.samples.compactMap { sample -> PowerSample? in
            guard sample.time >= recentStart - 2, sample.time <= time, let watts = sample.power else { return nil }
            return PowerSample(time: sample.time, watts: watts)
        }
        if let result = try? FTPAnalysis.calculate(samples: samples, start: recentStart, end: time) {
            liveBestMinutePower = max(liveBestMinutePower ?? 0, result.bestMinutePower)
        }
        lastLiveAnalysisAt = time
    }

    private mutating func transition(to phase: WorkoutPhase, at time: Double) {
        self.phase = phase; phaseStartedAt = time
        recordEvent(at: time, message: phase.title)
    }
}

/// Source compatibility for existing ramp test integrations.
public typealias RampEngine = RideEngine
