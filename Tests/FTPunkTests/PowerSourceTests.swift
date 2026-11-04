import Foundation
import Testing
import FTPunkDomain
import FTPunkDevices
import FTPunkStorage
@testable import FTPunkApp

@Test func trainerOnlyPacketsCompleteATestWithoutExternalMeter() throws {
    let configuration = try SessionConfiguration(warmupSeconds: 0, powerSource: .trainer, cadenceSource: .trainer)
    var engine = RampEngine(configuration: configuration)
    for second in 0...75 {
        // FTMS instantaneous cadence and power. 300 W; 90 rpm, then 30 rpm at exhaustion.
        let cadence: UInt8 = second >= 70 ? 60 : 180
        let value = try IndoorBikeData.decode(Data([0x44, 0, 0, 0, cadence, 0, 0x2c, 1]))
        let reading = DeviceReading(role: .trainer, uptime: Double(second), power: value.powerWatts, cadence: value.cadenceRPM)
        engine.receive(try #require(MeasurementRouting.sample(reading, configuration: configuration, origin: 0)))
        engine.tick(at: Double(second))
    }
    #expect(engine.session.outcome == .exhaustion)
    #expect(engine.session.result?.bestMinutePower == 300)
    #expect(engine.session.result?.estimatedFTP == 216)
    #expect(engine.session.configuration.resolvedPowerSource == .trainer)
}

@Test func externalMeterPowerCanUseTrainerCadenceWithoutMixingWatts() throws {
    let configuration = try SessionConfiguration(warmupSeconds: 0, powerSource: .externalPowerMeter, cadenceSource: .trainer)
    var engine = RampEngine(configuration: configuration)
    for second in 0...70 {
        let trainer = DeviceReading(role: .trainer, uptime: Double(second), power: 500, cadence: 90)
        let meter = DeviceReading(role: .pedals, uptime: Double(second) + 0.1, power: 300)
        let diagnostic = try #require(MeasurementRouting.sample(trainer, configuration: configuration, origin: 0))
        #expect(diagnostic.power == nil)
        #expect(diagnostic.trainerPower == 500)
        #expect(diagnostic.cadence == 90)
        engine.receive(diagnostic)
        engine.receive(try #require(MeasurementRouting.sample(meter, configuration: configuration, origin: 0)))
        engine.tick(at: Double(second) + 0.1)
    }
    engine.finishRamp(at: 70.1)
    #expect(engine.session.result?.bestMinutePower == 300)
    #expect(!MeasurementRouting.isEssential(.heartRate, configuration: configuration))
    #expect(MeasurementRouting.isEssential(.trainer, configuration: configuration))
    #expect(MeasurementRouting.isEssential(.pedals, configuration: configuration))
    let trainerOnly = try SessionConfiguration()
    #expect(!MeasurementRouting.isEssential(.pedals, configuration: trainerOnly))
}

@Test func trainerPacketsCannotHideSelectedMeterFailure() throws {
    let configuration = try SessionConfiguration(warmupSeconds: 0, powerSource: .externalPowerMeter, cadenceSource: .trainer)
    var engine = RampEngine(configuration: configuration)
    for second in 0...75 where engine.phase.isActive {
        let trainer = DeviceReading(role: .trainer, uptime: Double(second), power: 500, cadence: 90)
        engine.receive(try #require(MeasurementRouting.sample(trainer, configuration: configuration, origin: 0)))
        if second <= 70 {
            let meter = DeviceReading(role: .pedals, uptime: Double(second), power: 300)
            engine.receive(try #require(MeasurementRouting.sample(meter, configuration: configuration, origin: 0)))
        }
        engine.tick(at: Double(second))
    }
    #expect(engine.phase == .interrupted)
    #expect(engine.session.result == nil)
    #expect(engine.session.configuration.resolvedPowerSource == .externalPowerMeter)
}

@Test func cadenceIsOptionalButMissingCadenceNeverBecomesExhaustion() throws {
    let configuration = try SessionConfiguration(warmupSeconds: 0, powerSource: .trainer, cadenceSource: .unavailable)
    var engine = RampEngine(configuration: configuration)
    engine.receive(RideSample(time: 0, power: 0)); engine.tick(at: 0)
    #expect(engine.phase == .waiting)
    for second in 1...75 {
        engine.receive(RideSample(time: Double(second), power: second < 70 ? 300 : 0))
        engine.tick(at: Double(second))
    }
    #expect(engine.phase == .ramp)
    #expect(engine.session.outcome == nil)
    engine.finishRamp(at: 75); engine.endActivity(at: 76)
    #expect(engine.phase == .completed)
    #expect(engine.session.outcome == .finishedEarly)
    #expect(engine.session.result?.bestMinutePower == 300)
}

@Test func readinessTracksPowerAndCadenceFreshnessIndependently() {
    var values = DeviceMeasurements()
    values.receive(DeviceReading(role: .trainer, uptime: 10, power: 200, cadence: 90))
    #expect(values.hasFreshPower(from: .trainer, at: 10))
    #expect(!values.hasFreshPower(from: .externalPowerMeter, at: 10))
    #expect(values.preferredCadence(for: .trainer, at: 10) == .trainer)
    values.receive(DeviceReading(role: .pedals, uptime: 10, power: 220))
    #expect(values.preferredCadence(for: .externalPowerMeter, at: 10) == .trainer)
    values.receive(DeviceReading(role: .pedals, uptime: 11, cadence: 88))
    #expect(values.preferredCadence(for: .externalPowerMeter, at: 11) == .externalPowerMeter)
    // Later cadence-only packets must not keep old power fresh.
    values.receive(DeviceReading(role: .pedals, uptime: 13, cadence: 89))
    #expect(!values.hasFreshPower(from: .externalPowerMeter, at: 13))
    values.reset(.pedals)
    #expect(values.preferredCadence(for: .externalPowerMeter, at: 13) == .unavailable)
}

@Test func oldSourceMetadataStaysExternalAndExportsNameTheSelectedSource() throws {
    let configuration = try SessionConfiguration()
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any])
    object.removeValue(forKey: "powerSource"); object.removeValue(forKey: "cadenceSource"); object["protocolVersion"] = 2
    let legacy = try JSONDecoder().decode(SessionConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(legacy.resolvedPowerSource == .externalPowerMeter)
    #expect(legacy.resolvedCadenceSource == .externalPowerMeter)
    var session = TestSession(configuration: configuration)
    session.endedAtOffset = 1; session.samples = [RideSample(time: 0, power: 200)]
    let csv = String(decoding: ActivityExport.csv(session), as: UTF8.self)
    #expect(csv.contains("power_watts")); #expect(!csv.contains("pedal_watts"))
    #expect(csv.contains("power_source,cadence_source"))
    let tcx = String(decoding: try ActivityExport.tcx(session), as: UTF8.self)
    #expect(tcx.contains("Power source: Trainer"))
}

@Test @MainActor func newTestsDefaultToTrainerPowerAndRetainTheirSourceSnapshot() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    #expect(model.powerSource == .trainer)
    await model.start(); model.mockPaused = true
    let original = try #require(model.engine?.session.configuration)
    model.powerSource = .externalPowerMeter // A later preference cannot rewrite the active session.
    #expect(original.resolvedPowerSource == .trainer)
    #expect(model.engine?.session.configuration.resolvedPowerSource == .trainer)
    model.advanceMock(seconds: 1)
    let sample = try #require(model.engine?.session.samples.last)
    #expect(sample.power == sample.trainerPower)
    model.stop()
}

@Test func powerModeMapsToAndFromModelValues() {
    #expect(PowerMode.resolve(powerSource: .externalPowerMeter, matchingEnabled: true, meterConnected: true) == .meterMatched)
    #expect(PowerMode.resolve(powerSource: .externalPowerMeter, matchingEnabled: false, meterConnected: true) == .meterRecordOnly)
    #expect(PowerMode.resolve(powerSource: .trainer, matchingEnabled: true, meterConnected: true) == .trainer)
    // Meter disconnected: always the trainer, whatever is stored.
    #expect(PowerMode.resolve(powerSource: .externalPowerMeter, matchingEnabled: true, meterConnected: false) == .trainer)
    #expect(PowerMode.meterMatched.settings(currentMatching: false) == (.externalPowerMeter, true))
    #expect(PowerMode.meterRecordOnly.settings(currentMatching: true) == (.externalPowerMeter, false))
    #expect(PowerMode.trainer.settings(currentMatching: false) == (.trainer, false))
    for mode in PowerMode.allCases {
        let values = mode.settings(currentMatching: true)
        #expect(PowerMode.resolve(powerSource: values.powerSource, matchingEnabled: values.matchingEnabled, meterConnected: true) == mode)
    }
}
