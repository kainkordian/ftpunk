import Foundation
import Testing
import FTPunkDomain
import FTPunkDevices

// Acceptance harness for docs/archive/2026-11-04-roadmap/2-power-matching.md. A simulated trainer with a cold/warm error model
// and a perfect power meter, driven through a real RideEngine and the real PowerMatcher at 1 Hz, the way AppModel.update() does.
// `LegacyMatcher` is the integral matcher this replaced, kept only so the report can print old against new.

private struct LegacyMatcher {
    var correction = 0.0
    private var target: Int?
    private var settledAt = 0.0
    private var lastAdjustment = -Double.infinity
    private var lastSampleTime = -Double.infinity
    private var smoothedPower: Double?
    mutating func command(target watts: Int, sample: PowerSample?, cadence: Double?, at time: Double, range: SupportedPowerRange) -> Int {
        let limit = min(60, Double(watts) * 0.2)
        if target != watts { target = watts; settledAt = time + 5; smoothedPower = nil }
        let lower = max(-limit, Double(range.minimum - watts)), upper = min(limit, Double(range.maximum - watts))
        correction = min(upper, max(lower, correction))
        if let sample, sample.time.isFinite, sample.watts.isFinite, time >= sample.time, time - sample.time <= 2, sample.time > lastSampleTime {
            lastSampleTime = sample.time
            if sample.watts <= 0 || cadence.map({ !$0.isFinite || $0 < 45 }) == true { smoothedPower = nil; settledAt = time + 5 }
            else if time >= settledAt {
                smoothedPower = smoothedPower.map { $0 * 0.7 + sample.watts * 0.3 } ?? sample.watts
                if time - lastAdjustment >= 3, let measured = smoothedPower {
                    let error = Double(watts) - measured
                    if abs(error) > 2 { correction = min(upper, max(lower, correction + min(3, max(-3, error * 0.25)))) }
                    lastAdjustment = time
                }
            }
        }
        return range.quantized(Int((Double(watts) + correction).rounded()))
    }
}

/// Deterministic noise in -amplitude...amplitude.
private struct Noise {
    private var state: UInt64 = 0x9E3779B97F4A7C15
    mutating func next(_ amplitude: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Double(state >> 11) / Double(1 << 53) * 2 - 1) * amplitude
    }
}

/// trainerReported = delivered × g(E, t) + offset, with g(E, t) = gWarm × (1 + drift × t / 10 min) + gCold × exp(−E / E0).
/// The trainer's ERG loop regulates its *reported* power, so the meter (the truth) sees (command − offset) ÷ g.
private struct TrainerModel {
    var gWarm = 1.0, gCold = -0.15, e0 = 80.0, offset = 0.0, drift = 0.01
    func gain(energy: Double, time: Double) -> Double { gWarm * (1 + drift * time / 600) + gCold * exp(-energy / e0) }
    var label: String { String(format: "o %+.0f W, E0 %.0f kJ, gWarm %.2f, gCold %.2f", offset, e0, gWarm, gCold) }
}

private enum Matching { case new, legacy, off }

private struct Scenario {
    var name: String
    var trainer = TrainerModel()
    var preset: RampPreset = .standard
    var warmup = 600.0
    var matching = Matching.new
    var rampSeconds = 600.0
    /// Torque limit: below this cadence the trainer delivers its demand × cadence / c0.
    var torqueLimitCadence: Double?
    var cadence: @Sendable (Double) -> Double = { _ in 90 }
    /// Multiplies delivered power (and so both readings) for a stretch of the warm-up, to stand in for a sprint.
    var burst: (@Sendable (Double) -> Double)?
    var warmth = TrainerWarmth()
}

private struct Row {
    var time: Double, rampTime: Double
    var target: Int, commanded: Int, delivered: Double, meter: Double, reported: Double, correction: Double
}

private struct Outcome { var rows: [Row]; var matcher: PowerMatcher; var warmth: TrainerWarmth; var gainAt: [Double: Double] }

private func simulate(_ scenario: Scenario, gainTimes: [Double] = []) throws -> Outcome {
    let range = try SupportedPowerRange(minimum: 0, maximum: 1000, increment: 1)
    let configuration = try SessionConfiguration(preset: scenario.preset, priorFTP: FTPEntry(watts: 250), warmupSeconds: scenario.warmup,
                                                 powerSource: .externalPowerMeter, cadenceSource: .externalPowerMeter, powerMatchingEnabled: scenario.matching == .new)
    var engine = RideEngine(configuration: configuration)
    var matcher = PowerMatcher(), legacy = LegacyMatcher(), warmth = scenario.warmth
    warmth.beginSession()
    var noise = Noise()
    let lag = 1 - exp(-1 / 1.5)
    var commanded = 0, delivered = 0.0, energy = scenario.warmth.kilojoules
    var rows: [Row] = [], gains: [Double: Double] = [:]
    var time = 0.0
    while time < 3000 {
        let rampTime = engine.phase == .ramp ? time - engine.phaseStartedAt : 0
        let cadence = engine.phase == .ramp ? scenario.cadence(rampTime) : 90
        let model = scenario.trainer
        let g = model.gain(energy: energy, time: time)
        var demand = max(0, (Double(commanded) - model.offset) / g)
        if let c0 = scenario.torqueLimitCadence, cadence < c0 { demand *= cadence / c0 }
        delivered += (demand * (scenario.burst?(time) ?? 1) - delivered) * lag
        energy += delivered / 1000
        let reported = max(0, delivered * g + model.offset + noise.next(1)), meter = max(0, delivered + noise.next(4))
        engine.receive(RideSample(time: time, power: meter, cadence: cadence))
        engine.receive(RideSample(time: time, trainerPower: reported))
        engine.tick(at: time)
        warmth.add(PowerSample(time: time, watts: reported))
        guard engine.phase.isActive else { break }
        if let target = engine.targetPower {
            switch scenario.matching {
            case .new:
                commanded = matcher.command(target: target, meter: engine.lastPower, trainer: engine.lastTrainerPower, cadence: cadence, at: time, range: range, warmth: warmth)
            case .legacy:
                commanded = legacy.command(target: target, sample: engine.lastPower, cadence: cadence, at: time, range: range)
            case .off: commanded = range.quantized(target)
            }
            if gainTimes.contains(time) { gains[time] = matcher.gain }
            if engine.phase == .ramp {
                rows.append(Row(time: time, rampTime: time - engine.phaseStartedAt, target: target, commanded: commanded, delivered: delivered, meter: meter,
                                reported: reported, correction: scenario.matching == .legacy ? legacy.correction : Double(commanded - target)))
            }
        }
        if engine.phase == .ramp, time - engine.phaseStartedAt >= scenario.rampSeconds { break }
        time += 1
    }
    return Outcome(rows: rows, matcher: matcher, warmth: warmth, gainAt: gains)
}

/// Mean |meter − target| over the last 5 s of every complete ramp step in `steps`, as a share of the target.
private func stepEndErrors(_ rows: [Row], stepSeconds: Double, steps: ClosedRange<Int>) -> [Double] {
    steps.compactMap { step in
        let end = Double(step) * stepSeconds
        let window = rows.filter { $0.rampTime >= end - 5 && $0.rampTime < end }
        guard !window.isEmpty else { return nil }
        return window.map { abs($0.meter - Double($0.target)) }.reduce(0, +) / Double(window.count) / Double(window[0].target)
    }
}
private func mean(_ values: [Double]) -> Double { values.isEmpty ? .nan : values.reduce(0, +) / Double(values.count) }
private func pct(_ value: Double) -> String { String(format: "%5.2f", value * 100) }

private func gridCells() -> [TrainerModel] {
    var cells: [TrainerModel] = []
    for offset in [-10.0, 0, 10] { for (e0, cold) in [(40.0, -0.10), (80, -0.15), (120, -0.20)] { for warm in [1.0, 1.04] {
        cells.append(TrainerModel(gWarm: warm, gCold: cold, e0: e0, offset: offset))
    } } }
    return cells
}

// MARK: Acceptance

@Test func gridStandardRampHoldsThreePercentFromStepFour() throws {
    var failures: [String] = []
    print("[power-matching-sim] standard ramp, 10 min warm-up: mean step-end error from step 4 (% of target), matching off / old matcher / new matcher")
    for cell in gridCells() {
        let off = try simulate(Scenario(name: "off", trainer: cell, matching: .off)), old = try simulate(Scenario(name: "old", trainer: cell, matching: .legacy))
        let new = try simulate(Scenario(name: "new", trainer: cell))
        let errors = { (o: Outcome) in stepEndErrors(o.rows, stepSeconds: 12, steps: 4...49) }
        let (a, b, c) = (mean(errors(off)), mean(errors(old)), mean(errors(new)))
        print("[power-matching-sim] \(cell.label): off \(pct(a)) | old \(pct(b)) | new \(pct(c)) (worst step \(pct(errors(new).max() ?? .nan)))")
        if !(c <= 0.03) { failures.append("\(cell.label): \(pct(c)) %") }
    }
    #expect(failures.isEmpty, "cells over 3 %: \(failures)")
}

@Test func coldRampStartIsWithinSixPercentEarlyAndThreeAfter() throws {
    var early: [String] = [], late: [String] = []
    print("[power-matching-sim] warm-up 0 s (cold ramp start): mean step-end error, steps 1-20 / after step 20 (% of target), off | old | new")
    for cell in gridCells() {
        func run(_ matching: Matching) throws -> (Double, Double) {
            let outcome = try simulate(Scenario(name: "cold", trainer: cell, warmup: 0, matching: matching, rampSeconds: 600))
            return (mean(stepEndErrors(outcome.rows, stepSeconds: 12, steps: 1...20)), mean(stepEndErrors(outcome.rows, stepSeconds: 12, steps: 21...49)))
        }
        let off = try run(.off), old = try run(.legacy), new = try run(.new)
        print("[power-matching-sim] \(cell.label): off \(pct(off.0))/\(pct(off.1)) | old \(pct(old.0))/\(pct(old.1)) | new \(pct(new.0))/\(pct(new.1))")
        if !(new.0 <= 0.06) { early.append("\(cell.label): \(pct(new.0)) %") }
        if !(new.1 <= 0.03) { late.append("\(cell.label): \(pct(new.1)) %") }
    }
    #expect(early.isEmpty, "cells over 6 % in steps 1-20: \(early)")
    #expect(late.isEmpty, "cells over 3 % after step 20: \(late)")
}

@Test(arguments: [RampPreset.gentle, .zwift]) func gentleAndZwiftPresetsHoldThreePercentFromStepFour(preset: RampPreset) throws {
    var failures: [String] = []
    for cell in [TrainerModel(gWarm: 1.0, gCold: -0.15, e0: 80, offset: 0), TrainerModel(gWarm: 1.04, gCold: -0.15, e0: 80, offset: 10)] {
        let off = try simulate(Scenario(name: "off", trainer: cell, preset: preset, matching: .off, rampSeconds: 900))
        let old = try simulate(Scenario(name: "old", trainer: cell, preset: preset, matching: .legacy, rampSeconds: 900))
        let new = try simulate(Scenario(name: "new", trainer: cell, preset: preset, rampSeconds: 900))
        let steps = 4...Int(900 / preset.stepSeconds) - 1 // e.g. 44 steps of 20 s
        let e = { (o: Outcome) in stepEndErrors(o.rows, stepSeconds: preset.stepSeconds, steps: steps) }
        print("[power-matching-sim] \(preset.title) preset, \(cell.label): off \(pct(mean(e(off)))) | old \(pct(mean(e(old)))) | new \(pct(mean(e(new)))) (worst step \(pct(e(new).max() ?? .nan)))")
        if !(mean(e(new)) <= 0.03) { failures.append("\(cell.label): \(pct(mean(e(new)))) %") }
    }
    #expect(failures.isEmpty, "\(preset.title): \(failures)")
}

@Test func aFadingRiderNeverMakesTheLoadHarder() throws {
    // Cadence falls 90 -> 50 rpm over the last 60 s of a 600 s ramp (100 -> 350 W); the trainer cannot hold ERG below 70 rpm.
    let fade: @Sendable (Double) -> Double = { $0 < 540 ? 90 : 90 - 40 * ($0 - 540) / 60 }
    var worstMean = 0.0, worstMax = 0.0
    print("[power-matching-sim] fading rider, final 60 s: extra commanded W vs matching off (mean / max), and growth of the correction since 540 s (mean / max)")
    for cell in gridCells() {
        let on = try simulate(Scenario(name: "on", trainer: cell, torqueLimitCadence: 70, cadence: fade))
        let old = try simulate(Scenario(name: "old", trainer: cell, matching: .legacy, torqueLimitCadence: 70, cadence: fade))
        let off = try simulate(Scenario(name: "off", trainer: cell, matching: .off, torqueLimitCadence: 70, cadence: fade))
        let final = { (o: Outcome) in o.rows.filter { $0.rampTime >= 540 } }
        #expect(final(on).count == final(off).count && final(on).count >= 59)
        let extra = { (o: Outcome) in final(o).map { Double($0.commanded - $0.target) } }
        let at540 = on.rows.last { $0.rampTime < 540 }?.correction ?? 0
        let growth = final(on).map { Double($0.commanded - $0.target) - at540 }
        let oldAt540 = old.rows.last { $0.rampTime < 540 }?.correction ?? 0
        let oldGrowth = final(old).map { Double($0.commanded - $0.target) - oldAt540 }
        print(String(format: "[power-matching-sim] %@: new extra %.1f / %.1f W, growth %.1f / %.1f W | old extra %.1f / %.1f W, growth %.1f / %.1f W",
                     cell.label, mean(extra(on)), extra(on).max() ?? .nan, mean(growth), growth.max() ?? .nan,
                     mean(extra(old)), extra(old).max() ?? .nan, mean(oldGrowth), oldGrowth.max() ?? .nan))
        worstMean = max(worstMean, mean(growth)); worstMax = max(worstMax, growth.max() ?? .nan)
    }
    #expect(worstMean <= 3, "mean growth \(worstMean) W")
    #expect(worstMax <= 6, "max growth \(worstMax) W")
    // The literal reading of the plan's table, on a trainer that reads true: extra commanded load mean <= 3 W, max <= 6 W.
    let exact = TrainerModel(gWarm: 1.0, gCold: 0, e0: 80, offset: 0, drift: 0)
    let on = try simulate(Scenario(name: "exact", trainer: exact, torqueLimitCadence: 70, cadence: fade))
    let extra = on.rows.filter { $0.rampTime >= 540 }.map { Double($0.commanded - $0.target) }
    #expect(mean(extra) <= 3 && (extra.max() ?? 0) <= 6, "mean \(mean(extra)) max \(extra.max() ?? .nan)")
}

@Test func aSprintInTheWarmupDoesNotMoveTheGain() throws {
    // A trainer that is already warm; 5 s at twice the power in the constant warm-up (both readings see it).
    let warm = TrainerModel(gWarm: 1.02, gCold: 0, e0: 80, offset: 0, drift: 0)
    let burst: @Sendable (Double) -> Double = { (300..<305).contains($0) ? 2 : 1 }
    let outcome = try simulate(Scenario(name: "sprint", trainer: warm, burst: burst, warmth: TrainerWarmth(kilojoules: 200)), gainTimes: [299, 330])
    let before = try #require(outcome.gainAt[299]), after = try #require(outcome.gainAt[330])
    print(String(format: "[power-matching-sim] sprint in warm-up: gain %.4f before, %.4f 25 s after (%.2f %%)", before, after, abs(after / before - 1) * 100))
    #expect(abs(after / before - 1) < 0.005)
}

@Test func aSecondRideStartsWarm() throws {
    let cell = TrainerModel(gWarm: 1.02, gCold: -0.15, e0: 80, offset: 0)
    let first = try simulate(Scenario(name: "first", trainer: cell, warmup: 300, rampSeconds: 600))
    #expect(first.warmth.kilojoules > TrainerWarmth.relaxedKilojoules)
    var warmth = first.warmth; warmth.beginSession()
    var second = PowerMatcher()
    let range = try SupportedPowerRange(minimum: 0, maximum: 1000, increment: 1)
    _ = second.command(target: 125, meter: nil, trainer: nil, cadence: nil, at: 0, range: range, warmth: warmth)
    #expect(second.status == .matching(gain: 1, offset: 0))     // not .warming
    #expect(warmth.coldness == 0)
    var firstRide = PowerMatcher()
    _ = firstRide.command(target: 125, meter: nil, trainer: nil, cadence: nil, at: 0, range: range, warmth: TrainerWarmth())
    #expect(firstRide.status == .warming(percent: 0))
}
