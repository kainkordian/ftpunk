import Foundation
import Testing
@testable import FTPunkDomain

@Test func setupSnapshotsAndWarmup() throws {
    var ftp = FTPEntry(watts: 250)
    let config = try SessionConfiguration(priorFTP: ftp, weightKG: 75)
    ftp.watts = 300
    #expect(config.warmupPower == 125); #expect(config.priorFTP?.watts == 250)
    #expect(try SessionConfiguration(priorFTP: ftp, manualWarmupPower: 110).warmupPower == 110)
    #expect(throws: ConfigurationError.invalidWeight) { try SessionConfiguration(weightKG: 0) }
    #expect(throws: ConfigurationError.invalidFTP) { try SessionConfiguration(priorFTP: FTPEntry(watts: .infinity)) }
    #expect(try SessionConfiguration(preset: .gentle).warmupPower == 75)
}

@Test func bestMinuteUsesTimeAndKeepsZeros() throws {
    let samples = stride(from: 0.0, through: 120, by: 0.8).map { PowerSample(time: $0, watts: $0 < 60 ? 200 : 300) }
    let result = try FTPAnalysis.calculate(samples: samples, start: 0, end: 120, weightKG: 75, factor: 0.8)
    #expect(abs(result.bestMinutePower - 300) < 0.001)
    #expect(abs(try #require(result.wattsPerKG) - 3.2) < 0.001)
    let zero = (0..<60).map { PowerSample(time: Double($0), watts: $0 < 30 ? 0 : 200) }
    #expect(try FTPAnalysis.calculate(samples: zero, start: 0, end: 60).bestMinutePower == 100)
}

@Test func gapsAndIncompleteWindowsAreRejected() {
    let gap = (0..<60).filter { $0 != 30 && $0 != 31 }.map { PowerSample(time: Double($0), watts: 300) }
    #expect(throws: AnalysisError.insufficientCoverage) { try FTPAnalysis.calculate(samples: gap, start: 0, end: 60) }
    #expect(throws: AnalysisError.insufficientCoverage) { try FTPAnalysis.calculate(samples: [PowerSample(time: 0, watts: 300)], start: 0, end: 59) }
    #expect(throws: AnalysisError.invalidSamples) { try FTPAnalysis.calculate(samples: [PowerSample(time: 1, watts: 200), PowerSample(time: 0, watts: 300)], start: 0, end: 60) }
}

@Test func rampPresetsAndDelayedClock() throws {
    let standard = try SessionConfiguration()
    #expect(standard.rampPower(at: 11.99) == 100); #expect(standard.rampPower(at: 12) == 105)
    #expect(try SessionConfiguration(preset: .gentle).rampPower(at: 20) == 55)
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    engine.receive(RideSample(time: 0, power: 100, cadence: 90)); engine.tick(at: 0)
    engine.receive(RideSample(time: 1, power: 100, cadence: 90)); engine.tick(at: 1)
    #expect(engine.phase == .ramp)
    engine.tick(at: 10)
    #expect(engine.phase == .interrupted); #expect(engine.session.result == nil)
}

@Test func exhaustionNeedsSustainedFreshCadence() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    for second in 0...75 {
        engine.receive(RideSample(time: Double(second), power: 300, cadence: second >= 70 ? 30 : 90))
        engine.tick(at: Double(second))
    }
    #expect(engine.phase == .cooldown); #expect(engine.session.rampEnd == 70)
    #expect(engine.session.result?.windowEnd == 60)
    #expect(engine.session.outcome == .exhaustion)
    engine.endActivity(at: 76)
    #expect(engine.phase == .completed)
}

@Test func stalePowerCannotMasqueradeAsFailure() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    engine.receive(RideSample(time: 0, power: 200, cadence: 90)); engine.tick(at: 0)
    engine.tick(at: 1); engine.tick(at: 2)
    engine.receive(RideSample(time: 3, cadence: 0)); engine.tick(at: 3)
    #expect(engine.phase == .interrupted); #expect(engine.session.outcome == .interrupted)
}
