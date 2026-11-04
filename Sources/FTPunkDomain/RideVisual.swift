import Foundation

/// The rider-facing name of the night-city strip, in one place. The App target uses this constant too, so a rename
/// is a one-line change here. Preference keys and accessibility identifiers deliberately keep their old names.
public enum RideVisualBranding {
    public static let name = "Chaindance"
}

/// The proportions of the Large view. The hero raster is the strip with extra sky above it; the readout lives in that sky,
/// so it can never cover the rider.
public enum HeroLayout {
    public static let stripRows = 60, heroRows = 96
    public static var skyRows: Int { heroRows - stripRows }
    /// The share of the Large view's height the readout may use, from the top.
    public static var readoutFraction: Double { Double(skyRows) / Double(heroRows) }
}

/// The kind of ride the strip is drawing.
public enum RideVisualMode: Equatable, Sendable { case ftpTest, workout, freeERG, resistance }

/// Where the rider is. Only the FTP test leaves the flat boulevard: it climbs the Spire during the ramp.
public enum RideVisualWorld: Equatable, Sendable { case boulevard, skyway, rooftop, descent }

/// How the rider sits, from the zone of their smoothed power. The rider is seated, except in a sprint: at about
/// 7 W/kg (see `RideVisualState.standingWattsPerKG`) they stand on the pedals.
public enum RidePosture: Int, Comparable, Sendable {
    case upright, hoods, low, drops, standing
    public static func < (lhs: RidePosture, rhs: RidePosture) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum RideMotion: Equatable, Sendable {
    case pedalling, coasting
    /// Paused: the rider has stopped with one foot on the road.
    case footDown
}

/// The neighbourhood behind a workout step. Recoveries are calm teal blocks; work steps are a bright market
/// district in the step's zone colour (neutral cyan without an FTP).
public struct RideVisualDistrict: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case residential, market }
    public var kind: Kind
    public var zone: IntensityZone?
    public init(kind: Kind, zone: IntensityZone?) { self.kind = kind; self.zone = zone }
}

/// Text on a sign. `.finish` and `.paused` are fixed signs; `.gate` and `.step` name what the rider just passed or
/// can still pass, and `.level` is the ramp's step number.
public struct RideVisualSign: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case level, finish, paused, step, gate }
    public var kind: Kind
    public var text: String
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
}

/// A boundary that is close enough to preview: the next ramp level, or the next workout step.
public struct RideVisualUpcoming: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case level, step }
    /// Grows with every boundary (the next level number, or the next step index), so each is previewed once.
    public var key: Int
    public var kind: Kind
    public var text: String
    public var secondsUntil: Double
    /// The district that starts at the boundary, for workouts.
    public var district: RideVisualDistrict?
}

/// Everything the strip reads from a ride. It only reads: nothing here ever reaches the trainer.
public struct RideVisualInput: Equatable, Sendable {
    /// FTP test timing.
    public struct Ramp: Equatable, Sendable {
        public var phaseSeconds: Double
        public var warmupSeconds: Double
        public var cooldownSeconds: Double
        public var stepSeconds: Double
        /// Scored ramp time so far; once the ramp has ended, its length.
        public var rampSeconds: Double
        public var bestMinuteWatts: Double?
        public init(phaseSeconds: Double, warmupSeconds: Double, cooldownSeconds: Double, stepSeconds: Double,
                    rampSeconds: Double, bestMinuteWatts: Double? = nil) {
            self.phaseSeconds = phaseSeconds; self.warmupSeconds = warmupSeconds; self.cooldownSeconds = cooldownSeconds
            self.stepSeconds = stepSeconds; self.rampSeconds = rampSeconds; self.bestMinuteWatts = bestMinuteWatts
        }
    }
    /// The workout step being ridden, with targets already scaled by the ride's intensity.
    public struct Step: Equatable, Sendable {
        public struct Next: Equatable, Sendable {
            public var seconds: Double, startWatts: Double, endWatts: Double
            public init(seconds: Double, startWatts: Double, endWatts: Double) {
                self.seconds = seconds; self.startWatts = startWatts; self.endWatts = endWatts
            }
        }
        public var index: Int, count: Int
        public var startWatts: Double, endWatts: Double
        public var seconds: Double, remaining: Double
        public var next: Next?
        public init(index: Int, count: Int, startWatts: Double, endWatts: Double, seconds: Double, remaining: Double, next: Next? = nil) {
            self.index = index; self.count = count; self.startWatts = startWatts; self.endWatts = endWatts
            self.seconds = seconds; self.remaining = remaining; self.next = next
        }
    }

    public var mode: RideVisualMode
    public var phase: WorkoutPhase
    /// Measured power smoothed over three seconds; nil when it is stale.
    public var power: Double?
    /// Fresh cadence in rpm; nil when stale.
    public var cadence: Double?
    /// False when the ride has no cadence source; power then stands in for cadence.
    public var cadenceAvailable: Bool
    /// The FTP the ride uses, nil without one.
    public var ftp: Double?
    /// The debug mock playback speed (1 on real rides).
    public var playbackSpeed: Double
    public var ramp: Ramp?
    public var step: Step?
    /// Free ERG target in watts, or the resistance level in tenths.
    public var target: Int?
    /// The rider's weight, for the standing threshold. Nil when unknown.
    public var weightKG: Double?
    /// Power averaged over the last second; nil when stale. A sprint is too short for the three-second average.
    public var sprintPower: Double?
    /// The highest one-second average within the last three seconds, so a rider hovering at the threshold stays up.
    public var sprintPeak: Double?

    public init(mode: RideVisualMode, phase: WorkoutPhase, power: Double? = nil, cadence: Double? = nil, cadenceAvailable: Bool = true,
                ftp: Double? = nil, playbackSpeed: Double = 1, ramp: Ramp? = nil, step: Step? = nil, target: Int? = nil,
                weightKG: Double? = nil, sprintPower: Double? = nil, sprintPeak: Double? = nil) {
        self.weightKG = weightKG; self.sprintPower = sprintPower; self.sprintPeak = sprintPeak
        self.mode = mode; self.phase = phase; self.power = power; self.cadence = cadence; self.cadenceAvailable = cadenceAvailable
        self.ftp = ftp; self.playbackSpeed = playbackSpeed; self.ramp = ramp; self.step = step; self.target = target
    }
}

/// The strip's state, derived purely from a ride's mode, phase, step, smoothed power, FTP, cadence, pause and
/// playback speed. Intensity uses the zones of the workout profile charts (`IntensityZone`), so the avatar and the
/// charts always agree. Nothing here predicts where a ramp will end: the climb is endless and only shows the step
/// being ridden and the next one.
public struct RideVisualState: Equatable, Sendable {
    public let mode: RideVisualMode
    public let world: RideVisualWorld
    /// The zone of the smoothed power; nil without an FTP or fresh power (neutral cyan, endurance pose).
    public let zone: IntensityZone?
    public let posture: RidePosture
    public let motion: RideMotion
    /// Seconds per crank turn, nil unless pedalling. Measured cadence, kept to what 12 frames a second can show.
    public let pedalPeriod: Double?
    /// Road pixels per second.
    public let worldSpeed: Double
    /// How much faster than real time the scenery animates: the debug playback speed, kept within what stays readable.
    public let animationRate: Double
    /// Horizontal drift of the rain, 0 (nearly vertical) to 1.
    public let rainSlant: Double
    public let district: RideVisualDistrict
    /// 0...1 brightness of the district; warm-up ramps brighten gradually.
    public let glow: Double
    /// Ramp step being ridden (or reached, at the finish) in the FTP test; the workout step number in workouts.
    public let level: Int?
    public let sign: RideVisualSign?
    public let upcoming: RideVisualUpcoming?
    /// How far the Spire has grown on the horizon (warm-up) or fills the view (ramp onwards), 0...1.
    public let spire: Double
    /// Seconds of scored ramp; how far the skyline has sunk.
    public let climbSeconds: Double
    /// Progress through the descent, 0...1.
    public let descent: Double
    public let accessibilitySummary: String

    // MARK: Constants

    /// Cadence assumed when the ride has no cadence source.
    public static let nominalCadence = 85.0
    /// Below this the rider is not pedalling.
    public static let pedallingCadence = 10.0
    public static let maximumAnimationRate = 4.0
    /// How long before a boundary its sign comes into view.
    public static let levelPreviewSeconds = 6.0
    public static let stepPreviewSeconds = 10.0
    /// The rider stands from this many watts per kilogram. Seven, not eight: eight is out of reach for many amateurs,
    /// and seven is still well above any steady effort.
    public static let standingWattsPerKG = 7.0
    /// Without a weight: this multiple of FTP, above the end of a ramp test (about FTP / 0.72, or 1.39 x FTP).
    public static let standingFTPFactor = 1.6
    /// Smoothed power must stay above this share of the threshold to keep standing after a one-second dip.
    public static let standingHoldFraction = 0.85

    /// Watts at which the rider stands; nil with neither a weight nor an FTP (never stand).
    public static func standingThreshold(weightKG: Double?, ftp: Double?) -> Double? {
        if let weightKG, weightKG.isFinite, weightKG > 0 { return standingWattsPerKG * weightKG }
        if let ftp, ftp.isFinite, ftp > 0 { return standingFTPFactor * ftp }
        return nil
    }

    // MARK: Intensity

    public static func zone(power: Double?, ftp: Double?) -> IntensityZone? {
        guard let power, power.isFinite, power >= 0, let ftp, ftp.isFinite, ftp > 0 else { return nil }
        return IntensityZone.zone(forFraction: power / ftp)
    }
    public static func posture(for zone: IntensityZone?) -> RidePosture {
        switch zone {
        case .none, .endurance: .hoods
        case .recovery: .upright
        case .tempo, .sweetSpot: .low
        case .threshold, .vo2max: .drops
        }
    }
    /// Length in pixels of the light trail behind the bike, and whether it is dim.
    public var trail: (length: Int, dim: Bool) {
        if posture == .standing { return (36, false) }
        return switch zone {
        case .recovery: (6, true)
        case .none, .endurance: (9, false)
        case .tempo: (15, false)
        case .sweetSpot: (24, false)
        case .threshold: (30, false)
        case .vo2max: (36, false)
        }
    }
    public var showsSweat: Bool { zone == .threshold || zone == .vo2max || posture == .standing }
    public var showsSpeedLines: Bool { zone == .threshold || zone == .vo2max || posture == .standing }
    public var showsSparks: Bool { zone == .vo2max || posture == .standing }

    // MARK: Derivation

    public static func make(_ input: RideVisualInput) -> RideVisualState {
        let rate = input.playbackSpeed.isFinite ? min(maximumAnimationRate, max(1, input.playbackSpeed)) : 1
        let power = input.power.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let zone = Self.zone(power: power, ftp: input.ftp)

        let motion: RideMotion
        if input.phase == .paused { motion = .footDown }
        else if input.cadenceAvailable { motion = (input.cadence ?? 0) >= pedallingCadence ? .pedalling : .coasting }
        else { motion = (power ?? 0) > 5 ? .pedalling : .coasting }

        // Standing: a sprint at the threshold, or smoothed power still near it right after a one-second window reached it.
        // The FTP test's warm-up and ramp say "stay seated", so the rider never stands there.
        let seatedPhase = input.mode == .ftpTest && [.waiting, .warmup, .ramp].contains(input.phase)
        var standing = false
        if motion == .pedalling, !seatedPhase,
           let threshold = Self.standingThreshold(weightKG: input.weightKG, ftp: input.ftp) {
            let sprint = input.sprintPower.flatMap { $0.isFinite ? $0 : nil }
            let peak = input.sprintPeak.flatMap { $0.isFinite ? $0 : nil }
            standing = (sprint ?? 0) >= threshold
                || ((power ?? 0) >= standingHoldFraction * threshold && max(peak ?? 0, sprint ?? 0) >= threshold)
        }

        var pedalPeriod: Double?
        if motion == .pedalling {
            let rpm = input.cadenceAvailable ? (input.cadence ?? nominalCadence) : nominalCadence
            pedalPeriod = 60 / min(150, max(20, rpm * rate))
        }
        let speed: Double
        switch motion {
        case .footDown: speed = 0
        case .coasting: speed = 6 * rate
        case .pedalling: speed = min(90, (14 + 28 * min(500, max(0, power ?? 120)) / 500) * rate)
        }

        var world = RideVisualWorld.boulevard
        var district = RideVisualDistrict(kind: .market, zone: nil)
        var glow = 0.85
        var level: Int?
        var sign: RideVisualSign?
        var upcoming: RideVisualUpcoming?
        var spire = 0.0, climb = 0.0, descent = 0.0
        var summary = ""

        switch input.mode {
        case .ftpTest:
            if let ramp = input.ramp {
                let stepSeconds = max(1, ramp.stepSeconds)
                func levelNumber(_ seconds: Double) -> Int { Int(max(0, seconds) / stepSeconds) + 1 }
                switch input.phase {
                case .waiting, .warmup, .riding, .paused:
                    let progress = input.phase == .warmup && ramp.warmupSeconds > 0 ? min(1, max(0, ramp.phaseSeconds / ramp.warmupSeconds)) : 0
                    spire = 0.2 + 0.8 * progress
                    let remaining = ramp.warmupSeconds - ramp.phaseSeconds
                    if input.phase == .warmup, remaining <= levelPreviewSeconds {
                        upcoming = RideVisualUpcoming(key: 1, kind: .level, text: "LVL 1", secondsUntil: max(0, remaining), district: nil)
                    }
                    summary = input.phase == .warmup ? "warming up" : ""
                case .ramp:
                    world = .skyway; spire = 1; climb = max(0, ramp.rampSeconds)
                    let current = levelNumber(ramp.rampSeconds)
                    level = current
                    sign = RideVisualSign(kind: .level, text: "LVL \(current)")
                    let untilNext = stepSeconds - ramp.rampSeconds.truncatingRemainder(dividingBy: stepSeconds)
                    if untilNext <= levelPreviewSeconds {
                        upcoming = RideVisualUpcoming(key: current + 1, kind: .level, text: "LVL \(current + 1)", secondsUntil: untilNext, district: nil)
                    }
                    summary = "level \(current)"
                case .cooldown, .completed, .interrupted:
                    spire = 1; climb = max(0, ramp.rampSeconds)
                    let reached = ramp.rampSeconds > 0 ? levelNumber(ramp.rampSeconds) : nil
                    let finish = min(6, ramp.cooldownSeconds * 0.3)
                    let atSummit = input.phase == .completed || input.phase == .interrupted || ramp.phaseSeconds < finish
                    if reached == nil { world = .boulevard; spire = 0.2 }
                    else if atSummit {
                        world = .rooftop; level = reached
                        let best = ramp.bestMinuteWatts.flatMap { $0.isFinite && $0 > 0 ? Int($0.rounded()) : nil }
                        sign = RideVisualSign(kind: .finish, text: best.map { "LVL \(reached!) · \($0) W" } ?? "LVL \(reached!)")
                        summary = "ramp finished at level \(reached!)"
                    } else {
                        world = .descent; level = reached
                        let span = max(1, ramp.cooldownSeconds - finish)
                        descent = min(1, max(0, (ramp.phaseSeconds - finish) / span))
                        summary = "cooling down"
                    }
                }
            }
        case .workout:
            if let step = input.step {
                level = step.index + 1
                let zoneOfStep = Self.zone(power: (step.startWatts + step.endWatts) / 2, ftp: input.ftp)
                district = Self.district(zone: zoneOfStep)
                let ramped = step.endWatts != step.startWatts
                let progress = step.seconds > 0 ? min(1, max(0, 1 - step.remaining / step.seconds)) : 1
                if ramped { glow = 0.4 + 0.6 * (step.endWatts > step.startWatts ? progress : 1 - progress) }
                else { glow = district.kind == .residential ? 0.6 : 1 }
                sign = RideVisualSign(kind: .step, text: "STEP \(step.index + 1)/\(step.count)")
                if let next = step.next, step.remaining <= stepPreviewSeconds {
                    let nextZone = Self.zone(power: (next.startWatts + next.endWatts) / 2, ftp: input.ftp)
                    upcoming = RideVisualUpcoming(key: step.index + 1, kind: .step,
                                                  text: "NEXT \(clock(next.seconds)) · \(Int(next.startWatts.rounded())) W",
                                                  secondsUntil: max(0, step.remaining), district: Self.district(zone: nextZone))
                }
                summary = "step \(step.index + 1) of \(step.count)"
            }
        case .freeERG:
            if let target = input.target { sign = RideVisualSign(kind: .gate, text: "\(target) W") }
        case .resistance:
            if let tenths = input.target { sign = RideVisualSign(kind: .gate, text: "RES \(String(format: "%.1f", Double(tenths) / 10))") }
        }
        if input.phase == .paused { sign = RideVisualSign(kind: .paused, text: "PAUSED") }

        let effort = standing ? "sprinting out of the saddle" : zone.map { "\($0.title.lowercased()) effort" } ?? "steady effort"
        let accessibility: String
        if input.phase == .paused { accessibility = "\(RideVisualBranding.name): paused" }
        else if world == .rooftop { accessibility = "\(RideVisualBranding.name): \(summary)" }
        else if world == .descent { accessibility = "\(RideVisualBranding.name): cooling down" }
        else if input.mode == .ftpTest && summary == "warming up" { accessibility = "\(RideVisualBranding.name): warming up, \(effort)" }
        else if summary.isEmpty { accessibility = "\(RideVisualBranding.name): \(effort)" }
        else { accessibility = "\(RideVisualBranding.name): \(effort), \(summary)" }

        return RideVisualState(mode: input.mode, world: world, zone: zone, posture: standing ? .standing : posture(for: zone), motion: motion,
                               pedalPeriod: pedalPeriod, worldSpeed: speed, animationRate: rate, rainSlant: 0.1 + 0.9 * min(1, speed / 60),
                               district: district, glow: glow, level: level, sign: sign, upcoming: upcoming,
                               spire: spire, climbSeconds: climb, descent: descent, accessibilitySummary: accessibility)
    }

    static func district(zone: IntensityZone?) -> RideVisualDistrict {
        RideVisualDistrict(kind: zone == .recovery ? .residential : .market, zone: zone)
    }
    private static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }
}

public enum RideVisualSmoothing {
    /// Mean of the power readings in the last `window` seconds. Nil when the newest reading is older than
    /// `staleAfter` seconds, matching how the cockpit treats a power reading as stale.
    public static func power(_ samples: [RideSample], now: Double, window: Double = 3, staleAfter: Double = 2) -> Double? {
        var sum = 0.0, count = 0.0, newest: Double?
        for sample in samples.reversed() {
            if sample.time > now + 0.001 { continue }
            if sample.time < now - window { break }
            guard let power = sample.power, power.isFinite else { continue }
            newest = newest ?? sample.time
            sum += power; count += 1
        }
        guard count > 0, let newest, now - newest <= staleAfter else { return nil }
        return sum / count
    }
}

extension RideVisualSmoothing {
    /// Power averaged over the last second (nil when stale), for sprint detection.
    public static func sprintPower(_ samples: [RideSample], now: Double) -> Double? {
        power(samples, now: now, window: 1)
    }
    /// The highest one-second average ending within the last `lookback` seconds. Nil when nothing is fresh.
    public static func sprintPeak(_ samples: [RideSample], now: Double, lookback: Double = 3) -> Double? {
        var best: Double?
        for sample in samples.reversed() {
            if sample.time > now + 0.001 { continue }
            if sample.time < now - lookback { break }
            if let value = power(samples, now: sample.time, window: 1, staleAfter: 0) { best = max(best ?? value, value) }
        }
        return best
    }
}

/// The strip's on/off choice (kept under its old keys). It replaces the earlier `showStelvioASCII`: absent means on, a stored value is kept.
public enum RideVisualPreference {
    public static let key = "rideVisualEnabled"
    public static let legacyKey = "showStelvioASCII"

    public static func resolve(stored: Bool?, legacy: Bool?) -> Bool { stored ?? legacy ?? true }

    /// Reads the preference, carrying an explicit value of the old toggle over to the new key once.
    public static func load(from defaults: UserDefaults = .standard) -> Bool {
        let stored = defaults.object(forKey: key) as? Bool
        let legacy = defaults.object(forKey: legacyKey) as? Bool
        let value = resolve(stored: stored, legacy: legacy)
        if stored == nil, legacy != nil { defaults.set(value, forKey: key) }
        if legacy != nil { defaults.removeObject(forKey: legacyKey) }
        return value
    }
    public static func save(_ value: Bool, to defaults: UserDefaults = .standard) { defaults.set(value, forKey: key) }

    // MARK: Placement

    public static let placementKey = "rideVisualPlacement"

    /// A stored placement wins; otherwise the earlier on/off choice maps `true` to the strip and `false` to off.
    public static func resolvePlacement(stored: String?, enabled: Bool?, legacy: Bool?) -> RideVisualPlacement {
        if let stored, let placement = RideVisualPlacement(rawValue: stored) { return placement }
        return resolve(stored: enabled, legacy: legacy) ? .strip : .off
    }
    public static func loadPlacement(from defaults: UserDefaults = .standard) -> RideVisualPlacement {
        let stored = defaults.string(forKey: placementKey)
        let placement = resolvePlacement(stored: stored, enabled: defaults.object(forKey: key) as? Bool, legacy: defaults.object(forKey: legacyKey) as? Bool)
        if stored == nil { _ = load(from: defaults) } // carries the oldest toggle over to its current key
        return placement
    }
    /// Writes the placement and keeps the old on/off key in step, so the stored choice stays readable by older builds.
    public static func savePlacement(_ placement: RideVisualPlacement, to defaults: UserDefaults = .standard) {
        defaults.set(placement.rawValue, forKey: placementKey)
        defaults.set(placement != .off, forKey: key)
    }
}

/// How the strip is shown in the cockpits: not at all, a strip between the readings, or a hero scene filling the top.
public enum RideVisualPlacement: String, CaseIterable, Identifiable, Sendable {
    case off, strip, hero
    public var id: String { rawValue }
    public var title: String {
        switch self { case .off: "Off"; case .strip: "Strip"; case .hero: "Large" }
    }
    /// The next placement when a single control cycles through them.
    public var next: RideVisualPlacement {
        switch self { case .off: .strip; case .strip: .hero; case .hero: .off }
    }
}
