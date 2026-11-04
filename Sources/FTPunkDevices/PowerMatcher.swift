import Foundation
import FTPunkDomain

/// How much work the trainer has done since the app connected to it. A cold trainer misreports; the error fades as it
/// warms, and it warms faster under higher power, so warmth is counted in kilojoules rather than minutes. It lives
/// outside `PowerMatcher` so a second ride right after the first starts warm. Only a new trainer connection resets it.
public struct TrainerWarmth: Sendable {
    /// The "cold" model error is assumed over by here...
    public static let warmKilojoules = 60.0
    /// ...and the estimator has fully relaxed to its base noise by here.
    public static let relaxedKilojoules = 120.0
    public private(set) var kilojoules: Double
    private var lastTime: Double?
    public init(kilojoules: Double = 0) { self.kilojoules = kilojoules }
    /// A new ride's clock starts at zero again; the energy stays.
    public mutating func beginSession() { lastTime = nil }
    /// Feed every new trainer-reported sample once. Gaps longer than 3 s count as 3 s.
    public mutating func add(_ sample: PowerSample) {
        guard sample.time.isFinite, sample.watts.isFinite else { return }
        defer { lastTime = sample.time }
        guard let lastTime, sample.time > lastTime, sample.watts > 0 else { return }
        kilojoules += sample.watts * min(3, sample.time - lastTime) / 1000
    }
    /// 1 while cold, falling linearly to 0 between 60 and 120 kJ. Scales the estimator's process noise.
    public var coldness: Double {
        kilojoules <= Self.warmKilojoules ? 1 : max(0, 1 - (kilojoules - Self.warmKilojoules) / (Self.relaxedKilojoules - Self.warmKilojoules))
    }
    public var isWarming: Bool { kilojoules < Self.warmKilojoules }
    public var percentOfWarmup: Int { Int(min(100, kilojoules / Self.warmKilojoules * 100)) }
}

/// Power matching: estimate the trainer's error against the pedals while riding, and command the trainer so the meter
/// reads the target. One instance per ride. Nothing persists across rides except the trainer's warmth.
///
/// The estimator relates the two readings, not the target:  `meter ≈ gain × trainerReported + offset`.
/// A fading rider does not change that relationship (the trainer's own reading drops with the flywheel), so the
/// estimator is not fooled; the trainer falling below its own command is the fade signal.
public struct PowerMatcher: Sendable {
    public enum Status: Equatable, Sendable {
        case off, warming(percent: Int), matching(gain: Double, offset: Double), fadeHold
    }

    // Measurement
    static let smoothingSeconds = 2.0
    static let settleSeconds = 4.0
    static let minimumCadence = 45.0
    static let outlierFraction = 0.2
    /// A cold trainer can read 20 % low or more, so until it has warmed the surprise allowed per measurement is larger.
    static let coldOutlierFraction = 0.45
    static let measurementSigma = 4.0
    // Prior and process noise (variance per second).
    static let priorGainSigma = 0.05, priorOffsetSigma = 5.0
    static let baseGainNoise = 1.7e-7, baseOffsetNoise = 2e-3     // about 1 % per 10 minutes
    static let warmGainNoise = 2e-5, warmOffsetNoise = 0.05
    static let boostFactor = 4.0, boostSeconds = 60.0
    // Controller
    static let correctionLimit = 0.2
    /// A cold trainer can read 20 % low or more (plus a calibration offset), which needs more than the usual sanity cap.
    static let coldCorrectionLimit = 0.35
    static let moveInterval = 3.0
    static let stepWatts = 3.0, warmingStepWatts = 6.0
    // Fade guard
    static let fadeShortfall = 0.03, fadeAfter = 3.0, fadeRelease = 5.0

    public private(set) var gain = 1.0
    public private(set) var offset = 0.0
    /// What the last command added to the target (commanded minus target), unquantized.
    public private(set) var correction = 0.0
    public private(set) var isFading = false
    /// Total seconds the fade guard held, for the ride's event log.
    public private(set) var fadeSeconds = 0.0
    public private(set) var measurementCount = 0
    /// The last accepted measurement's surprise in watts (observed minus predicted), before it was applied.
    public private(set) var lastInnovation: Double?
    public private(set) var status = Status.off

    private var pGain = priorGainSigma * priorGainSigma, pCross = 0.0, pOffset = priorOffsetSigma * priorOffsetSigma
    private var noiseTime: Double?
    private var meterAverage: Double?, trainerAverage: Double?, averageTime: Double?
    private var lastMeterTime = -Double.infinity
    private var target: Int?
    private var settledAt = 0.0
    private var commanded: Double?
    private var lastMove = -Double.infinity
    private var fadeSince: Double?, holdSince: Double?, fadeTick: Double?
    private var innovations: [(time: Double, z: Double)] = []
    private var boostUntil = -Double.infinity

    public init() {}

    /// The estimate's uncertainty, for tests and diagnostics.
    public var covariance: (gain: Double, cross: Double, offset: Double) { (pGain, pCross, pOffset) }
    /// The meter reading to expect for a trainer-reported value.
    public func meterEstimate(forReported watts: Double) -> Double { gain * watts + offset }
    /// How far the trainer's own reading is from the meter at `watts` reported, as a signed share (+0.04 reads 4 % high).
    public func trainerError(atReported watts: Double) -> Double? {
        let meter = meterEstimate(forReported: watts)
        return watts > 0 && meter > 0 ? (watts - meter) / meter : nil
    }

    /// The pedals stopped, the target changed in a way that stops the load (pause, resume, intensity or free-ride change):
    /// forget the smoothed readings and wait for the trainer to settle. The gain and offset estimate is kept.
    public mutating func restartSettle(at time: Double) {
        meterAverage = nil; trainerAverage = nil; averageTime = nil; noiseTime = nil
        fadeSince = nil; holdSince = nil; fadeTick = nil; isFading = false
        commanded = nil; target = nil
        settledAt = time + Self.settleSeconds
    }

    // MARK: Estimator

    /// Feeds one meter/trainer pair to the estimator. `command` calls this; the replay test calls it directly.
    public mutating func observe(meter: PowerSample?, trainer: PowerSample?, cadence: Double?, at time: Double, warmth: TrainerWarmth) {
        guard time.isFinite else { return }
        func fresh(_ sample: PowerSample?) -> PowerSample? {
            guard let sample, sample.time.isFinite, sample.watts.isFinite, time >= sample.time, time - sample.time <= 2 else { return nil }
            return sample
        }
        guard let meter = fresh(meter), meter.time > lastMeterTime else { return }
        lastMeterTime = meter.time
        guard let trainer = fresh(trainer) else { return }
        if meter.watts <= 0 || trainer.watts <= 0 || cadence.map({ !$0.isFinite || $0 < Self.minimumCadence }) == true {
            // Stopped or approaching exhaustion: nothing to learn, and the smoothing is stale afterwards.
            meterAverage = nil; trainerAverage = nil; averageTime = nil; settledAt = max(settledAt, time + Self.settleSeconds)
            return
        }
        // Both readings get the same smoothing so the meter's and the trainer's lags line up.
        let alpha = averageTime.map { 1 - exp(-min(5, max(0, meter.time - $0)) / Self.smoothingSeconds) } ?? 1
        averageTime = meter.time
        meterAverage = meterAverage.map { $0 + (meter.watts - $0) * alpha } ?? meter.watts
        trainerAverage = trainerAverage.map { $0 + (trainer.watts - $0) * alpha } ?? trainer.watts
        guard time >= settledAt, !isFading, let observed = meterAverage, let regressor = trainerAverage else { return }
        spreadNoise(to: meter.time, warmth: warmth)
        let predicted = gain * regressor + offset
        let allowed = warmth.isWarming ? Self.coldOutlierFraction : Self.outlierFraction
        guard abs(observed - predicted) <= allowed * observed else { return } // sprints, coasting, dropouts
        let innovation = observed - predicted
        // P·Hᵀ for H = [regressor, 1].
        let pgx = pGain * regressor + pCross, pox = pCross * regressor + pOffset
        let variance = regressor * pgx + pox + Self.measurementSigma * Self.measurementSigma
        let kGain = pgx / variance, kOffset = pox / variance
        gain = min(1.6, max(0.6, gain + kGain * innovation))
        offset = min(50, max(-50, offset + kOffset * innovation))
        pGain = max(1e-12, pGain - kGain * pgx)
        pCross -= kGain * pox
        pOffset = max(1e-9, pOffset - kOffset * pox)
        measurementCount += 1; lastInnovation = innovation
        trackInnovation(innovation / variance.squareRoot(), at: meter.time)
    }

    private mutating func spreadNoise(to time: Double, warmth: TrainerWarmth) {
        defer { noiseTime = time }
        guard let last = noiseTime, time > last else { return }
        let seconds = min(10, time - last), cold = warmth.coldness
        let boost = time < boostUntil ? Self.boostFactor : 1
        pGain += (Self.baseGainNoise + cold * (Self.warmGainNoise - Self.baseGainNoise)) * seconds * boost
        pOffset += (Self.baseOffsetNoise + cold * (Self.warmOffsetNoise - Self.baseOffsetNoise)) * seconds * boost
    }

    /// When the last minute of residuals leans consistently to one side, the error is moving faster than the noise
    /// allows for (a cold room, a fan, a skipped calibration): let the estimate move 4 times faster for a minute.
    private mutating func trackInnovation(_ z: Double, at time: Double) {
        innovations.append((time, z))
        innovations.removeAll { time - $0.time > 60 }
        let count = Double(innovations.count)
        guard count >= 15 else { return }
        let mean = innovations.reduce(0) { $0 + $1.z } / count
        // Smoothed samples are correlated: count only a quarter of them as independent.
        if abs(mean) * (count / 4).squareRoot() > 2 { boostUntil = time + Self.boostSeconds; innovations.removeAll() }
    }

    // MARK: Controller

    public mutating func command(target watts: Int, meter: PowerSample?, trainer: PowerSample?, cadence: Double?,
                                 at time: Double, range: SupportedPowerRange, warmth: TrainerWarmth) -> Int {
        guard time.isFinite else { return range.quantized(watts) }
        let newTarget = target != watts
        if newTarget { target = watts; settledAt = time + Self.settleSeconds }
        updateFadeGuard(trainer: trainer, at: time)
        observe(meter: meter, trainer: trainer, cadence: cadence, at: time, warmth: warmth)

        let goal = Double(watts)
        let limit = warmth.isWarming ? Self.coldCorrectionLimit : Self.correctionLimit
        let low = max(goal * (1 - limit), Double(range.minimum)), high = min(goal * (1 + limit), Double(range.maximum))
        var wanted = min(high, max(low, (goal - offset) / gain))
        // A fading rider never makes the load harder: the correction may shrink, not grow.
        if isFading, commanded != nil { wanted = min(wanted, goal + correction) }
        if newTarget || commanded == nil {
            commanded = wanted; lastMove = time        // feed-forward: a new step gets its corrected command at once
        } else if let current = commanded, time - lastMove >= Self.moveInterval, abs(wanted - current) >= 1 {
            let limit = warmth.isWarming ? Self.warmingStepWatts : Self.stepWatts
            commanded = current + min(limit, max(-limit, wanted - current)); lastMove = time
        }
        let value = commanded ?? goal
        correction = value - goal
        let issued = range.quantized(Int(value.rounded()))
        lastIssued = issued
        status = isFading ? .fadeHold : warmth.isWarming ? .warming(percent: warmth.percentOfWarmup) : .matching(gain: gain, offset: offset)
        return issued
    }
    private var lastIssued: Int?

    /// The trainer falling below its own command is the fade signal: it cannot hold the load it was asked for.
    /// Judged only once the trainer has had time to settle after a target change.
    private mutating func updateFadeGuard(trainer: PowerSample?, at time: Double) {
        if let tick = fadeTick, isFading, time > tick { fadeSeconds += min(2, time - tick) }
        fadeTick = time
        guard let trainer, let issued = lastIssued, time >= settledAt, time >= trainer.time, time - trainer.time <= 2 else { return }
        if trainer.watts < Double(issued) * (1 - Self.fadeShortfall) {
            holdSince = nil
            fadeSince = fadeSince ?? time
            if let since = fadeSince, time - since >= Self.fadeAfter { isFading = true }
        } else {
            fadeSince = nil
            if isFading {
                holdSince = holdSince ?? time
                if let since = holdSince, time - since >= Self.fadeRelease { isFading = false; holdSince = nil }
            }
        }
    }
}
