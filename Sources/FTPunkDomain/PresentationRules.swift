import Foundation

// Pure presentation rules. They hold no UI state, so they can be unit tested and mirrored in JavaScript.

/// The kinds of ride the pre-flight can start.
public enum RideKindID: String, Codable, Sendable { case ftpTest, freeERG, resistance, workout }

/// Everything the start button depends on, gathered from the live app state.
public struct StartReadiness: Equatable, Sendable {
    public var kind: RideKindID
    public var isMock = false
    public var isBusy = false
    public var isFinishing = false
    public var trainerConnected = false
    public var trainerControlReady = false
    public var powerRangeKnown = false
    public var matchingChoicePending = false
    public var powerSource: PowerSource = .trainer
    public var freshSelectedPower = false
    public var supportsResistance = false
    public var durationsValid = true
    public var needsFTP = false
    public var targetsInRange = true
    public init(kind: RideKindID) { self.kind = kind }
}

/// Why Start is disabled, in the order a rider can fix things.
public enum StartBlocker: Equatable, Sendable {
    case finishing, busy, matchingChoice, trainerMissing, trainerControl, powerRange
    case resistanceUnsupported, noPower(PowerSource), invalidDurations, needsFTP, targetsOutOfRange

    public var reason: String {
        switch self {
        case .finishing: "Confirming the trainer stop. Wait a moment before starting."
        case .busy: "Another ride is already in progress."
        case .matchingChoice: "Choose how to use your power meter to start."
        case .trainerMissing: "Connect your trainer to start."
        case .trainerControl: "Enable trainer control to start."
        case .powerRange: "Waiting for the trainer’s power range."
        case .resistanceUnsupported: "This trainer does not advertise resistance control."
        case .noPower(let source): source == .trainer ? "Pedal so the trainer reports power." : "Pedal to wake your external power meter."
        case .invalidDurations: "Fix the warm-up and cool-down entries to start."
        case .needsFTP: "Set your FTP so this workout can use your targets."
        case .targetsOutOfRange: "Some targets are outside your trainer’s power range. Lower the intensity."
        }
    }

    public static func blocker(for input: StartReadiness) -> StartBlocker? {
        if input.isFinishing { return .finishing }
        if input.isBusy { return .busy }
        if input.kind == .ftpTest && !input.durationsValid { return .invalidDurations }
        if input.needsFTP { return .needsFTP }
        if input.isMock { return nil }
        if input.matchingChoicePending { return .matchingChoice }
        if !input.trainerConnected { return .trainerMissing }
        if !input.trainerControlReady { return .trainerControl }
        if input.kind == .resistance { if !input.supportsResistance { return .resistanceUnsupported } }
        else if !input.powerRangeKnown { return .powerRange }
        if !input.targetsInRange { return .targetsOutOfRange }
        if !input.freshSelectedPower { return .noPower(input.powerSource) }
        return nil
    }
}

/// The recommended ramp for a rider, with the reason shown in the pre-flight.
public struct ProtocolRecommendation: Equatable, Sendable {
    public let preset: RampPreset
    public let reason: String
    /// The reference guideline: below 60 kg uses 15 W/min, otherwise 25 W/min.
    public static func recommend(weightKG: Double?) -> ProtocolRecommendation {
        guard let weight = weightKG, weight.isFinite, weight > 0 else {
            return ProtocolRecommendation(preset: .standard, reason: "25 W/min is the default. Add your weight for a personal recommendation.")
        }
        let label = weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
        let preset: RampPreset = weight < 60 ? .gentle : .standard
        return ProtocolRecommendation(preset: preset, reason: "\(label) kg → \(preset == .gentle ? "15" : "25") W/min")
    }
}

/// Retest prompts begin after eight weeks.
public enum RetestAdvice: Equatable, Sendable {
    case never
    case recent(weeks: Int)
    case due(weeks: Int)

    public static let dueAfterWeeks = 8

    public static func evaluate(lastTest: Date?, now: Date = Date(), calendar: Calendar = .current) -> RetestAdvice {
        guard let lastTest else { return .never }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastTest), to: calendar.startOfDay(for: now)).day ?? 0
        let weeks = max(0, days) / 7
        return weeks >= dueAfterWeeks ? .due(weeks: weeks) : .recent(weeks: weeks)
    }
    public var isDue: Bool { if case .due = self { true } else { false } }

    /// "this week", "3 weeks ago": the age alone, for lines that already say when the test happened.
    public var ageText: String? {
        switch self {
        case .never: nil
        case .recent(let weeks), .due(let weeks): weeks == 0 ? "this week" : "\(weeks) \(weeks == 1 ? "week" : "weeks") ago"
        }
    }

    /// `verb` is "Last test" for a ramp result and "FTP set" for a manual entry.
    public func message(verb: String = "Last test") -> String? {
        switch self {
        case .never: nil
        case .recent(let weeks): weeks == 0 ? "\(verb) this week" : "\(verb) \(weeks) \(weeks == 1 ? "week" : "weeks") ago"
        case .due(let weeks): "\(verb) \(weeks) weeks ago, time to retest?"
        }
    }
}

/// Change from the current FTP to a new estimate.
public struct ResultDelta: Equatable, Sendable {
    public let watts: Int
    public let text: String
    public init(newFTP: Double, currentFTP: Double?) {
        guard let currentFTP, currentFTP.isFinite, currentFTP > 0 else { watts = 0; text = "First FTP for this rider"; return }
        let change = Int(newFTP.rounded()) - Int(currentFTP.rounded())
        watts = change
        let current = Int(currentFTP.rounded())
        text = change == 0 ? "Same as your current \(current) W" : "\(change > 0 ? "+" : "−")\(abs(change)) W vs \(current) W"
    }
}

/// Amber warning before the automatic finish at 45 rpm. The finish rule itself is unchanged.
public enum CadenceGuard {
    public static let warningBelow = 60.0
    public static let finishBelow = 45.0
    public enum State: Equatable, Sendable { case ok, unknown, low }
    public static func state(cadence: Double?, phase: WorkoutPhase, cadenceAvailable: Bool = true) -> State {
        guard phase == .ramp, cadenceAvailable else { return .ok }
        guard let cadence else { return .unknown }
        return cadence < warningBelow ? .low : .ok
    }
    public static let message = "Ramp ends below 45 rpm"
}

/// Hold-to-confirm gesture arithmetic, shared by the button and its tests.
public enum HoldProgress {
    public static let duration = 1.5
    public static func fraction(held seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(1, max(0, seconds / duration))
    }
    public static func isComplete(held seconds: Double) -> Bool { fraction(held: seconds) >= 1 }
}

/// Fractions of the phase timeline: warm-up, ramp, cool-down. The ramp is open-ended, so it is
/// drawn at a nominal length until the end of the scored ramp is known.
public struct PhaseTimeline: Equatable, Sendable {
    public struct Segment: Equatable, Sendable { public let phase: WorkoutPhase; public let start: Double; public let end: Double }
    public let segments: [Segment]
    public let progress: Double
    public static func make(phase: WorkoutPhase, warmup: Double, cooldown: Double, nominalRamp: Double = 600,
                            elapsedInPhase: Double, rampElapsed: Double? = nil) -> PhaseTimeline {
        let ramp = max(nominalRamp, (rampElapsed ?? 0) + 60)
        let total = max(1, warmup + ramp + cooldown)
        var segments: [Segment] = []
        var cursor = 0.0
        for (kind, length) in [(WorkoutPhase.warmup, warmup), (.ramp, ramp), (.cooldown, cooldown)] where length > 0 {
            segments.append(Segment(phase: kind, start: cursor / total, end: (cursor + length) / total)); cursor += length
        }
        let position: Double
        switch phase {
        case .waiting: position = 0
        case .warmup: position = min(elapsedInPhase, warmup)
        case .ramp: position = warmup + min(elapsedInPhase, ramp)
        case .cooldown: position = warmup + ramp + min(elapsedInPhase, cooldown)
        case .completed, .interrupted: position = total
        default: position = 0
        }
        return PhaseTimeline(segments: segments, progress: min(1, max(0, position / total)))
    }
}

/// Device status lights for the Home pill.
public enum DeviceLight: String, Equatable, Sendable { case ready, attention, off }

public struct DeviceSummary: Equatable, Sendable {
    public let trainer: DeviceLight
    public let power: DeviceLight
    public let heartRate: DeviceLight
    public let description: String

    public static func make(mock: Bool, trainerConnected: Bool, trainerReady: Bool, powerSource: PowerSource,
                            externalMeterConnected: Bool, heartRateConnected: Bool) -> DeviceSummary {
        if mock {
            return DeviceSummary(trainer: .ready, power: .ready, heartRate: .ready, description: "Mock sensors: trainer, power and heart rate simulated")
        }
        let trainerLight: DeviceLight = trainerConnected ? (trainerReady ? .ready : .attention) : .off
        let powerLight: DeviceLight = powerSource == .trainer ? trainerLight : (externalMeterConnected ? .ready : .attention)
        let heartLight: DeviceLight = heartRateConnected ? .ready : .off
        func word(_ light: DeviceLight) -> String { light == .ready ? "ready" : light == .attention ? "needs attention" : "not connected" }
        return DeviceSummary(trainer: trainerLight, power: powerLight, heartRate: heartLight,
                             description: "Trainer \(word(trainerLight)). Power from \(powerSource == .trainer ? "trainer" : "external meter") \(word(powerLight)). Heart rate \(word(heartLight)).")
    }
}

/// Initials for the rider chip.
public enum RiderInitials {
    public static func make(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }
}

/// Rider chip text: long names are cut so the chip never crowds the toolbar. The full name stays in the accessibility label.
public enum RiderChipName {
    public static let maximumCharacters = 14
    public static func display(_ name: String, limit: Int = maximumCharacters) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 1, trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// The single status line of Home's FTP card: when the FTP was set and how long ago, or the retest prompt.
public struct FTPStatusLine: Equatable, Sendable {
    public let text: String
    /// True once the 8-week retest is due; the line is then the retest prompt and uses the warning colour.
    public let isRetestPrompt: Bool
    public init(text: String, isRetestPrompt: Bool) { self.text = text; self.isRetestPrompt = isRetestPrompt }

    /// `date` is nil for an FTP entered for one ride, which has no age.
    public static func make(date: Date?, isRamp: Bool, source: String, now: Date = Date(), calendar: Calendar = .current) -> FTPStatusLine {
        guard let date else { return FTPStatusLine(text: source, isRetestPrompt: false) }
        let advice = RetestAdvice.evaluate(lastTest: date, now: now, calendar: calendar)
        var parts = ["\(isRamp ? "Tested" : "Set") \(dayAndMonth(date, calendar: calendar))"]
        if let age = advice.ageText { parts.append(age) }
        if !isRamp { parts.append(source) }
        var text = parts.joined(separator: " · ")
        if advice.isDue { text += " · time to retest?" }
        return FTPStatusLine(text: text, isRetestPrompt: advice.isDue)
    }

    /// "12 Oct": day first, no punctuation, whatever the region setting is.
    public static func dayAndMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB"); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

/// One-line devices summary for the pre-flight. Every part is labelled so it cannot read as a contradiction.
public enum DevicesLine {
    /// "Trainer: not connected · Power: from trainer · Heart rate: none".
    public static func make(trainerName: String?, powerSource: PowerSource, meterName: String?, heartRateName: String?) -> String {
        let trainer = trainerName ?? "not connected"
        let power = powerSource == .trainer ? "from trainer" : "from \(meterName ?? "external meter")"
        return "Trainer: \(trainer) · Power: \(power) · Heart rate: \(heartRateName ?? "none")"
    }
}

/// Cadence row of the pre-flight. It is a problem only once devices are connected and cadence is still missing.
public struct CadenceStatus: Equatable, Sendable {
    public let text: String
    public let isProblem: Bool
    public init(text: String, isProblem: Bool) { self.text = text; self.isProblem = isProblem }
    public static func make(source: CadenceSource, devicesConnected: Bool) -> CadenceStatus {
        switch source {
        case .trainer: CadenceStatus(text: "From trainer", isProblem: false)
        case .externalPowerMeter: CadenceStatus(text: "From power meter", isProblem: false)
        case .unavailable:
            devicesConnected
                ? CadenceStatus(text: "Not available. You will finish the ramp by hand.", isProblem: true)
                : CadenceStatus(text: "No cadence yet: connect and pedal", isProblem: false)
        }
    }
}

public enum DurationFormat {
    /// "55 min", "1 h 05 min", "45 s".
    public static func compact(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return total % 60 == 0 ? "\(minutes) min" : "\(minutes) min \(total % 60) s" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }
    /// Workout length for cards: minutes below two hours ("60 min", "95 min"), then "2 h 15 min" ("2 h" when exact).
    public static func workout(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return compact(seconds) }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 120 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))"
    }
}

/// Whether a ramp result's FTP is already in the rider's history.
public enum FTPAdoption {
    public static func isAdopted(rider: RiderProfile?, result: FTPResult, sessionStart: Date) -> Bool {
        rider?.ftpHistory.contains { $0.source == "Ramp test" && abs($0.watts - result.estimatedFTP) < 0.001 && $0.date >= sessionStart } == true
    }
}

public enum ResultSection: String, Equatable, Sendable { case headline, chart, decision, trainingHandoff, upload }

/// Result screen order: the training result, what it means for training, then sharing.
public enum ResultLayout {
    public static func sections(isFTPResult: Bool, adopted: Bool, canUpload: Bool) -> [ResultSection] {
        var sections: [ResultSection] = [.headline, .chart]
        if isFTPResult && adopted { sections += [.decision, .trainingHandoff] }
        if canUpload { sections.append(.upload) }
        return sections
    }
}

/// Plain-words account of an ended activity that did not finish normally.
public struct InterruptionSummary: Equatable, Sendable {
    public let headline: String
    public let reason: String
    public let saved: String
    public let hasResult: Bool

    public static func make(_ session: TestSession) -> InterruptionSummary {
        let length = DurationFormat.compact(session.endedAtOffset ?? session.samples.last?.time ?? 0)
        let reason = session.endReason ?? "The ride stopped unexpectedly."
        if session.result != nil {
            return InterruptionSummary(headline: "Cool-down interrupted", reason: reason,
                                       saved: "Saved on this device: \(length) of recording. Your scored ramp result was kept.", hasResult: true)
        }
        let what = session.training == nil ? "No FTP estimate, because a complete ramp was not scored." : "Your ride up to that point is kept."
        return InterruptionSummary(headline: session.training == nil ? "Test interrupted" : "Ride interrupted", reason: reason,
                                   saved: "Saved on this device: \(length) of recording. \(what)", hasResult: false)
    }
}

public enum RideStats {
    /// Time-weighted average of fresh power samples, with gaps over two seconds ignored.
    public static func averagePower(_ samples: [RideSample]) -> Double? {
        var energy = 0.0, seconds = 0.0
        for (previous, next) in zip(samples, samples.dropFirst()) {
            guard let power = previous.power, power.isFinite else { continue }
            let span = min(2, max(0, next.time - previous.time))
            energy += power * span; seconds += span
        }
        return seconds > 0 ? energy / seconds : nil
    }
}

public enum ResultPresentation {
    /// A ride that ends while the cockpit is minimised brings its result back on screen.
    public static func shouldPresent(previous: WorkoutPhase?, current: WorkoutPhase?, cockpitPresented: Bool) -> Bool {
        guard let current, !current.isActive, previous?.isActive == true else { return false }
        return !cockpitPresented
    }
}

/// The parts of a cockpit, for deciding which column of the wide Large layout each one goes in.
public enum CockpitBlock: Hashable, Sendable {
    /// The Chaindance scene with its readout.
    case scene
    /// What is coming: the workout profile and step, or the ramp's step countdown.
    case progress
    /// Heart rate, cadence and the other metric tiles.
    case tiles
    /// Intensity, ERG or resistance adjustments.
    case controls
    /// Coaching and footnotes.
    case notes
}

public enum CockpitKind: Equatable, Sendable { case ftpTest, workout, freeRide }

/// What the FTP cockpit shows at the current text size and phase. At accessibility sizes the header keeps only the
/// phase and time and the readings become compact rows, so target and actual both stay above the bottom bar.
public struct CockpitLayout: Equatable, Sendable {
    public let compactHeader: Bool
    public let showsHeaderSubtitle: Bool
    public let showsTimelineLabels: Bool
    public let metricRows: Bool
    public let showsCoachingLine: Bool
    /// Where the strip actually goes. `.hero` falls back to `.strip` at accessibility text sizes, so the numbers stay first.
    public let visual: RideVisualPlacement
    /// Hero scene on the left and the readings in a right column (wide Mac windows and iPads).
    public let sideBySide: Bool
    /// The window width from which the hero scene sits beside the readings.
    public static let sideBySideMinimumWidth = 900.0
    /// Side by side: the scene with what is coming under it on the left, the metric tiles on the right, so neither column
    /// is left with a tall empty area. Empty in the single column. Rides with nothing coming up (free ERG, resistance)
    /// put their adjustments under the scene instead.
    public let leftColumn: [CockpitBlock]
    public let rightColumn: [CockpitBlock]
    /// The widest the content gets. The Large scene takes the whole width of a phone or a small window.
    public let maximumContentWidth: Double

    public static func make(phase: WorkoutPhase, accessibilitySize: Bool, rideVisual: RideVisualPlacement = .off,
                            containerWidth: Double = 0, regularWidthClass: Bool = true, kind: CockpitKind = .ftpTest) -> CockpitLayout {
        let visual: RideVisualPlacement = rideVisual == .hero && accessibilitySize ? .strip : rideVisual
        let sideBySide = visual == .hero && regularWidthClass && containerWidth >= sideBySideMinimumWidth
        let left: [CockpitBlock], right: [CockpitBlock]
        switch (sideBySide, kind) {
        case (false, _): (left, right) = ([], [])
        case (true, .ftpTest): (left, right) = ([.scene, .progress], [.tiles, .notes])
        case (true, .workout): (left, right) = ([.scene, .progress], [.tiles, .controls, .notes])
        case (true, .freeRide): (left, right) = ([.scene, .controls], [.tiles, .notes])
        }
        return CockpitLayout(compactHeader: accessibilitySize, showsHeaderSubtitle: !accessibilitySize, showsTimelineLabels: !accessibilitySize,
                      metricRows: accessibilitySize,
                      // The coaching line is dropped mid-ramp (the bottom bar would clip it), at large text sizes and while the
                      // strip takes its place (the pre-flight already says to stay seated).
                      showsCoachingLine: phase != .ramp && !accessibilitySize && visual == .off,
                      visual: visual,
                      sideBySide: sideBySide, leftColumn: left, rightColumn: right,
                      maximumContentWidth: visual == .hero ? 1400 : 760)
    }
    /// The remaining-time shown beside the phase in the compact header, e.g. "8:20 left".
    public static func compactClock(_ clock: String, phase: WorkoutPhase) -> String {
        phase == .warmup || phase == .cooldown ? "\(clock) left" : clock
    }
}


/// The one line of coaching under the readings. Only the FTP test says "stay seated": a workout, free ERG or a resistance
/// ride lets the rider stand, and when Chaindance shows the rider out of the saddle the text agrees with it.
public enum CoachingText {
    public static let seated = "Stay seated. Keep a steady, comfortable cadence."
    public static let steady = "Keep a steady, comfortable cadence."
    public static let sprint = "Sprint — out of the saddle is fine."
    public static func line(for state: RideVisualState, phase: WorkoutPhase) -> String {
        if state.mode == .ftpTest { return phase == .cooldown ? "Ramp scored. Spin gently to cool down." : seated }
        return state.posture == .standing ? sprint : steady
    }
}
