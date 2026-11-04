import Foundation
import Testing
import FTPunkDomain
import FTPunkDevices

// Replays a real FTPunk CSV export (seconds,power_watts,cadence_rpm,heart_rate_bpm,trainer_watts,...) through the estimator and
// reports how well `meter ≈ gain × trainer + offset` predicted the meter, minute by minute. Skipped unless
// FTPUNK_REPLAY_CSV=<path> is set, so it runs on the owner's files without committing them:
//   FTPUNK_REPLAY_CSV=<file> swift test --filter replay

private struct ReplayMinute { var count = 0, absoluteError = 0.0, meter = 0.0, gain = 1.0, offset = 0.0 }

/// Exports hold one row per Bluetooth notification: a meter row has `power_watts`, a trainer row has `trainer_watts`.
/// The latest value of each is carried forward, exactly as the app's engine does.
private func replay(csv: String) -> [Int: ReplayMinute] {
    var matcher = PowerMatcher(), warmth = TrainerWarmth()
    var meter: PowerSample?, trainer: PowerSample?, cadence: (time: Double, rpm: Double)?
    var minutes: [Int: ReplayMinute] = [:]
    for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
        let columns = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 5, let time = Double(columns[0]) else { continue }
        if let watts = Double(columns[1]) { meter = PowerSample(time: time, watts: watts) }
        if let rpm = Double(columns[2]) { cadence = (time, rpm) }
        if let watts = Double(columns[4]) { trainer = PowerSample(time: time, watts: watts); warmth.add(trainer!) }
        let freshCadence = cadence.flatMap { time - $0.time <= 2 ? $0.rpm : nil }
        if let meter, let trainer, time - meter.time <= 2, time - trainer.time <= 2, meter.watts > 0, trainer.watts > 0, (freshCadence ?? 90) >= 45 {
            let predicted = matcher.meterEstimate(forReported: trainer.watts)
            var bucket = minutes[Int(time / 60)] ?? ReplayMinute()
            bucket.count += 1; bucket.absoluteError += abs(meter.watts - predicted); bucket.meter += meter.watts
            minutes[Int(time / 60)] = bucket
        }
        matcher.observe(meter: meter, trainer: trainer, cadence: freshCadence, at: time, warmth: warmth)
        minutes[Int(time / 60), default: ReplayMinute()].gain = matcher.gain
        minutes[Int(time / 60), default: ReplayMinute()].offset = matcher.offset
    }
    return minutes
}

@Test func replayParsesSparseRowsAndLearnsAConstantRelationship() {
    // A trainer that reads 5 % high with 3 W of offset, meter and trainer on alternating rows, varying power.
    var rows = ["seconds,power_watts,cadence_rpm,heart_rate_bpm,trainer_watts,power_source,cadence_source"]
    for second in 0..<600 {
        let truth = 150 + 100 * sin(Double(second) / 40)
        rows.append("\(second),\(truth),90,,,externalPowerMeter,externalPowerMeter")
        rows.append("\(Double(second) + 0.4),,,,\((truth - 3) * 1.05 / 1.0),externalPowerMeter,externalPowerMeter")
    }
    let minutes = replay(csv: rows.joined(separator: "\n"))
    let late = (5...9).compactMap { minutes[$0] }
    #expect(late.count == 5)
    let error = late.map { $0.absoluteError / Double($0.count) }.max() ?? .nan
    #expect(error < 3, "mean prediction error \(error) W")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FTPUNK_REPLAY_CSV"] != nil))
func replayRealRideFromEnvironment() throws {
    let path = try #require(ProcessInfo.processInfo.environment["FTPUNK_REPLAY_CSV"])
    let minutes = replay(csv: try String(contentsOfFile: path, encoding: .utf8))
    #expect(!minutes.isEmpty)
    print("[power-replay] \(path)")
    print("[power-replay] minute | samples | mean meter W | mean |meter - (gain x trainer + offset)| W (%) | gain | offset W")
    for minute in minutes.keys.sorted() {
        let value = minutes[minute]!
        guard value.count > 0 else { continue }
        let meter = value.meter / Double(value.count), error = value.absoluteError / Double(value.count)
        print(String(format: "[power-replay] %3d | %4d | %6.1f | %5.1f W (%4.1f %%) | %.3f | %+.1f", minute, value.count, meter, error, error / meter * 100, value.gain, value.offset))
    }
}
