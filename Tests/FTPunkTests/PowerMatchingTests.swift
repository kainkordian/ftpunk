import Foundation
import Testing
import FTPunkDomain
import FTPunkDevices
import FTPunkStorage
@testable import FTPunkApp

private let wideRange = try! SupportedPowerRange(minimum: 0, maximum: 1000, increment: 1)
private let warmTrainer = TrainerWarmth(kilojoules: 200)

/// One second of a perfect ERG trainer whose own reading is `reported` and a meter that reads `meter`.
private func ask(_ matcher: inout PowerMatcher, target: Int, meter: Double, reported: Double, cadence: Double? = 90, at second: Double,
                 range: SupportedPowerRange = wideRange, warmth: TrainerWarmth = TrainerWarmth()) -> Int {
    matcher.command(target: target, meter: PowerSample(time: second, watts: meter), trainer: PowerSample(time: second, watts: reported),
                    cadence: cadence, at: second, range: range, warmth: warmth)
}

@Test func powerMatchingConvergesWithEitherMeterOffset() throws {
    for bias in [-20.0, 20.0] {
        var matcher = PowerMatcher()
        var command = 250
        for second in 0...100 {
            let previous = command
            // The trainer holds its own reading at the command; the meter disagrees by a constant.
            command = ask(&matcher, target: 250, meter: Double(command) + bias, reported: Double(command), at: Double(second))
            #expect(abs(command - previous) <= 6)
            #expect((200...300).contains(command))
            if second < 4 { #expect(command == 250) }   // nothing is learned until the target has settled
        }
        #expect(abs(Double(command) + bias - 250) <= 3)
    }
}

@Test func matchingWaitsForFreshSamplesAndSettlingAndDoesNotLearnFromExhaustion() throws {
    var matcher = PowerMatcher()
    for second in 0...10 { _ = ask(&matcher, target: 250, meter: 235, reported: 250, at: Double(second), warmth: warmTrainer) }
    let count = matcher.measurementCount, gain = matcher.gain
    #expect(count > 0 && gain < 1)
    // A meter sample that stops arriving teaches nothing.
    for second in 11...20 {
        _ = matcher.command(target: 250, meter: PowerSample(time: 10, watts: 150), trainer: PowerSample(time: Double(second), watts: 250),
                            cadence: 90, at: Double(second), range: wideRange, warmth: warmTrainer)
    }
    #expect(matcher.measurementCount == count && matcher.gain == gain)
    // Standing still and a collapsing cadence suspend learning, and the settle restarts afterwards.
    for second in 21...40 {
        _ = ask(&matcher, target: 250, meter: second < 30 ? 0 : 50, reported: second < 30 ? 0 : 60, cadence: second < 30 ? 90 : 30, at: Double(second), warmth: warmTrainer)
    }
    #expect(matcher.measurementCount == count && matcher.gain == gain)
    // A new target is not learned from until the trainer has had 4 s to settle.
    _ = ask(&matcher, target: 275, meter: 200, reported: 275, at: 41, warmth: warmTrainer)
    for second in 42...44 { _ = ask(&matcher, target: 275, meter: 200, reported: 275, at: Double(second), warmth: warmTrainer) }
    #expect(matcher.measurementCount == count)
}

@Test func aNewTargetGetsItsCorrectedCommandInTheSameTick() throws {
    var matcher = PowerMatcher()
    // The trainer reads 5 % high (meter = reported / 1.05); learn that at 150 W ...
    for second in 0...120 { _ = ask(&matcher, target: 150, meter: Double(matcher.correction + 150) / 1.05, reported: matcher.correction + 150, at: Double(second), warmth: warmTrainer) }
    // ... then the ramp steps up: the very first command of the new step is already corrected.
    let command = ask(&matcher, target: 200, meter: 150, reported: 150, at: 121, warmth: warmTrainer)
    #expect(command >= 205 && command <= 215, "command \(command)")
}

@Test func commandsAreLimitedToTheTrainerRangeAndTwentyPercent() throws {
    let range = try SupportedPowerRange(minimum: 50, maximum: 260, increment: 5)
    var matcher = PowerMatcher()
    for second in 0...300 {
        // A meter that reads far too low (or high) asks for more than is allowed.
        let command = ask(&matcher, target: 250, meter: 100, reported: 250, at: Double(second), range: range, warmth: warmTrainer)
        #expect(command <= 260 && command.isMultiple(of: 5))
    }
    var low = PowerMatcher()
    for second in 0...300 {
        let command = ask(&low, target: 200, meter: 300, reported: 200, at: Double(second), range: range, warmth: warmTrainer)
        #expect(command >= 160)
    }
}

@Test func theFadeGuardFreezesTheEstimateAndNeverRaisesTheCorrection() throws {
    var matcher = PowerMatcher()
    var command = 200
    for second in 0...60 { command = ask(&matcher, target: 200, meter: 190 * Double(command) / 200, reported: Double(command), at: Double(second), warmth: warmTrainer) }
    #expect(matcher.correction > 0 && matcher.status != .fadeHold)
    // The trainer can no longer hold its own command; the meter keeps reading low (as it would for a fading rider).
    for second in 61...70 { _ = ask(&matcher, target: 200, meter: 150, reported: 150, at: Double(second), warmth: warmTrainer) }
    #expect(matcher.status == .fadeHold && matcher.isFading)
    let frozenGain = matcher.gain, frozenCorrection = matcher.correction
    for second in 71...80 { _ = ask(&matcher, target: 200, meter: 150, reported: 150, at: Double(second), warmth: warmTrainer) }
    #expect(matcher.gain == frozenGain && matcher.correction <= frozenCorrection)
    // A higher target while fading keeps the correction from growing.
    _ = ask(&matcher, target: 225, meter: 150, reported: 150, at: 81, warmth: warmTrainer)
    #expect(matcher.correction <= frozenCorrection)
    // After 5 s of the trainer holding again the guard lifts.
    for second in 82...92 { _ = ask(&matcher, target: 225, meter: 215, reported: Double(matcher.correction + 225), at: Double(second), warmth: warmTrainer) }
    #expect(!matcher.isFading)
}

@Test func pausingAndResumingKeepsTheEstimate() throws {
    var matcher = PowerMatcher()
    for second in 0...90 { _ = ask(&matcher, target: 180 + (second / 30) * 20, meter: 0.96 * Double(matcher.correction) + 170, reported: 180 + Double(second / 30 * 20), at: Double(second), warmth: warmTrainer) }
    let before = (matcher.gain, matcher.offset, matcher.covariance.gain, matcher.covariance.cross, matcher.covariance.offset)
    matcher.restartSettle(at: 91)
    _ = ask(&matcher, target: 240, meter: 230, reported: 240, at: 400, warmth: warmTrainer)  // resumes much later
    let after = (matcher.gain, matcher.offset, matcher.covariance.gain, matcher.covariance.cross, matcher.covariance.offset)
    #expect(before.0 == after.0 && before.1 == after.1 && before.2 == after.2 && before.3 == after.3 && before.4 == after.4)
}

@Test func warmthCountsTrainerKilojoulesAndSurvivesNewSessionsOnly() {
    var warmth = TrainerWarmth()
    #expect(warmth.isWarming && warmth.coldness == 1 && warmth.percentOfWarmup == 0)
    for second in 0...300 { warmth.add(PowerSample(time: Double(second), watts: 200)) }
    #expect(abs(warmth.kilojoules - 60) < 0.5, "300 s at 200 W is 60 kJ, got \(warmth.kilojoules)")
    #expect(!warmth.isWarming && warmth.coldness > 0.95)
    for second in 301...900 { warmth.add(PowerSample(time: Double(second), watts: 200)) }
    #expect(warmth.coldness == 0)
    warmth.beginSession()
    let kJ = warmth.kilojoules
    warmth.add(PowerSample(time: 0, watts: 300)); warmth.add(PowerSample(time: 1, watts: 300))
    #expect(abs(warmth.kilojoules - kJ - 0.3) < 1e-9)   // a new session's clock restarts without counting the gap
}

@Test func engineKeepsTheTrainersOwnReadingWhenTheMeterIsTheSource() throws {
    // Check from the plan: with an external meter each Bluetooth notification becomes ONE sample, so trainerPower is on the
    // trainer's samples and power on the meter's. The engine keeps both.
    var engine = RideEngine(configuration: try SessionConfiguration(powerSource: .externalPowerMeter, cadenceSource: .externalPowerMeter, powerMatchingEnabled: true))
    engine.receive(RideSample(time: 1, power: 210, cadence: 88))
    engine.receive(RideSample(time: 1.2, trainerPower: 224))
    #expect(engine.lastPower?.watts == 210 && engine.lastTrainerPower?.watts == 224)
    #expect(engine.session.samples.filter { $0.trainerPower != nil && $0.power != nil }.isEmpty)
}

@Test func matchingMetadataRoundTripsAndLegacySessionsRemainUnmatched() throws {
    let config = try SessionConfiguration(powerSource: .externalPowerMeter, powerMatchingEnabled: true)
    #expect(try JSONDecoder().decode(SessionConfiguration.self, from: JSONEncoder().encode(config)).usesPowerMatching)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
    json.removeValue(forKey: "powerMatchingEnabled")
    #expect(try !JSONDecoder().decode(SessionConfiguration.self, from: JSONSerialization.data(withJSONObject: json)).usesPowerMatching)
    #expect(try !SessionConfiguration(powerSource: .trainer, powerMatchingEnabled: true).usesPowerMatching)
}

@Test @MainActor func pairingChoiceAndSettingsAreSnapshottedForEachTest() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    #expect(model.powerMatchingEnabled)
    model.externalMeterReady(name: "Test meter")
    #expect(model.powerMatchingPrompt == "Test meter")
    #expect(model.powerSource == .externalPowerMeter)
    model.choosePowerMatching(false)
    #expect(!model.powerMatchingEnabled && model.powerMatchingPrompt == nil)
    model.externalMeterReady(name: "Test meter")
    model.choosePowerMatching(true)
    await model.start()
    #expect(model.engine?.session.configuration.usesPowerMatching == true)
    model.powerMatchingEnabled = false
    #expect(model.engine?.session.configuration.usesPowerMatching == true)
    model.externalMeterReady(name: "Another meter")
    #expect(model.powerMatchingPrompt == nil)
    model.stop()
}

@Test func matchingTracksRampStepsWithDelayedTrainerResponse() throws {
    var matcher = PowerMatcher()
    var command = 200
    var delivered = 180.0
    for halfSecond in 0...1200 {
        let time = Double(halfSecond) / 2
        let target = 200 + Int(time / 60) * 20
        // Four-second trainer response; the trainer holds its own reading at the command and reads 8 % high.
        delivered += (Double(command) / 1.08 - delivered) * (1 - exp(-0.5 / 4))
        command = matcher.command(target: target, meter: PowerSample(time: time, watts: delivered), trainer: PowerSample(time: time, watts: delivered * 1.08),
                                  cadence: 90, at: time, range: wideRange, warmth: warmTrainer)
        if time > 240, Int(time) % 60 >= 45 { #expect(abs(delivered - Double(target)) < 5, "t \(time): \(delivered) against \(target)") }
    }
}
