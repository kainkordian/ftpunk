import Foundation
import Testing
import FTPunkDomain
import FTPunkDevices

// The shared parity fixture for the web port of PowerMatcher (ftpunk_web/src/matching.mjs). Synthetic rides in the style of
// PowerMatchingReplayTests and PowerMatchingRampSimulationTests are run closed-loop through the real matcher at 1 Hz; the fixture
// stores, per second, the inputs the matcher saw and what it answered. The JavaScript test replays the inputs open-loop and must
// get the same commands and statuses. Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter powerMatchingReplayMatchesTheSharedFixture

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private struct Noise {
    private var state: UInt64 = 0x9E3779B97F4A7C15
    mutating func next(_ amplitude: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return (Double(state >> 11) / Double(1 << 53) * 2 - 1) * amplitude
    }
}

private struct Ride {
    var name: String
    /// reported = delivered x g + offset, g = gWarm x (1 + drift x t / 600) + gCold x exp(-E / e0)
    var gWarm = 1.0, gCold = -0.15, e0 = 80.0, offset = 0.0, drift = 0.01
    var warmthKJ = 0.0
    var seconds = 600
    var target: @Sendable (Int) -> Int
    var cadence: @Sendable (Int) -> Double? = { _ in 90 }
    /// The meter reports nothing in this window (the last sample goes stale).
    var meterDropout: Range<Int>?
    /// A coast: both readings drop to zero.
    var coast: Range<Int>?
    /// Torque limit: below this cadence the trainer delivers its demand x cadence / c0.
    var torqueLimitCadence: Double?
    var restartAt: [Int] = []
    var range: (min: Int, max: Int, increment: Int) = (0, 1000, 1)
}

private func round2(_ value: Double) -> Double { (value * 100).rounded() / 100 }
private func round9(_ value: Double) -> Double { (value * 1e9).rounded() / 1e9 }

private func run(_ ride: Ride) throws -> [String: Any] {
    let range = try SupportedPowerRange(minimum: ride.range.min, maximum: ride.range.max, increment: ride.range.increment)
    var matcher = PowerMatcher(), warmth = TrainerWarmth(kilojoules: ride.warmthKJ)
    warmth.beginSession()
    var noise = Noise()
    let lag = 1 - exp(-1 / 1.5)
    var commanded = 0, delivered = 0.0, energy = ride.warmthKJ
    var meterSample: PowerSample?
    var rows: [[Any]] = [], outputs: [[Any]] = []
    for second in 0..<ride.seconds {
        let time = Double(second)
        let cadence = ride.cadence(second)
        let g = ride.gWarm * (1 + ride.drift * time / 600) + ride.gCold * exp(-energy / ride.e0)
        var demand = max(0, (Double(commanded) - ride.offset) / g)
        if let c0 = ride.torqueLimitCadence, let cadence, cadence < c0 { demand *= cadence / c0 }
        if let coast = ride.coast, coast.contains(second) { demand = 0 }
        delivered += (demand - delivered) * lag
        energy += delivered / 1000
        let reported = round2(max(0, delivered * g + ride.offset + noise.next(1))), meter = round2(max(0, delivered + noise.next(4)))
        let dropped = ride.meterDropout?.contains(second) == true
        if !dropped { meterSample = PowerSample(time: time, watts: meter) }
        let trainer = PowerSample(time: time, watts: reported)
        warmth.add(trainer)
        let restart = ride.restartAt.contains(second)
        if restart { matcher.restartSettle(at: time) }
        let target = ride.target(second)
        commanded = matcher.command(target: target, meter: meterSample, trainer: trainer, cadence: cadence, at: time, range: range, warmth: warmth)
        rows.append([second, target, meterSample.map { $0.time as Any } ?? NSNull(), meterSample.map { $0.watts as Any } ?? NSNull(), reported,
                     cadence.map { $0 as Any } ?? NSNull(), restart ? 1 : 0])
        var kind = "off", percent: Any = NSNull(), gain = 1.0, offset = 0.0
        switch matcher.status {
        case .off: kind = "off"
        case .warming(let p): kind = "warming"; percent = p
        case .matching(let gn, let off): kind = "matching"; gain = gn; offset = off
        case .fadeHold: kind = "fadeHold"; gain = matcher.gain; offset = matcher.offset
        }
        outputs.append([commanded, kind, percent, round9(gain), round9(offset), round9(warmth.kilojoules)])
    }
    return ["name": ride.name, "warmthKJ": ride.warmthKJ, "range": ["minimum": ride.range.min, "maximum": ride.range.max, "increment": ride.range.increment],
            "rows": rows, "outputs": outputs]
}

private func rides() -> [Ride] {
    // 120 s of warm-up at 125 W, then +5 W every 12 s.
    let ramp: @Sendable (Int) -> Int = { $0 < 120 ? 125 : 150 + 5 * (($0 - 120) / 12) }
    let fade: @Sendable (Int) -> Double? = { $0 < 540 ? 90 : 90 - 40 * Double($0 - 540) / 60 }
    return [
        Ride(name: "cold-start-ramp", target: ramp),
        Ride(name: "cold-start-offset-minus-10", gWarm: 1.04, e0: 120, offset: -10, target: ramp),
        Ride(name: "warm-start", gWarm: 1.02, offset: 8, warmthKJ: 200, target: ramp),
        Ride(name: "fading-rider", target: { 100 + 250 * $0 / 600 }, cadence: fade, torqueLimitCadence: 70),
        Ride(name: "meter-dropout-and-coast", gWarm: 1.03, offset: 4, warmthKJ: 150, seconds: 420, target: { $0 < 240 ? 200 : 230 },
             cadence: { (310..<318).contains($0) ? nil : 90 }, meterDropout: 150..<160, coast: 300..<312),
        Ride(name: "pause-resume-and-small-range", gCold: -0.10, offset: -5, seconds: 360, target: { $0 < 200 ? 180 : 205 },
             restartAt: [100, 230], range: (50, 400, 5))
    ]
}

private func fixture() throws -> [String: Any] {
    ["format": "ftpunk-power-matching-replay", "version": 1,
     "columns": ["rows": ["second", "target", "meterTime", "meterWatts", "trainerWatts", "cadence", "restartSettle"],
                 "outputs": ["command", "status", "warmingPercent", "gain", "offset", "warmthKJ"]],
     "rides": try rides().map(run)]
}

@Test func powerMatchingReplayMatchesTheSharedFixture() throws {
    let url = root.appendingPathComponent("contracts/fixtures/power-matching-replay.json")
    let expected = try JSONSerialization.data(withJSONObject: fixture(), options: [.sortedKeys])
    if ProcessInfo.processInfo.environment["FTPUNK_WRITE_FIXTURES"] == "1" { try expected.write(to: url, options: .atomic) }
    // Byte comparison: the serialisation is deterministic, and decoded decimals would not compare equal to doubles.
    let data = try Data(contentsOf: url)
    #expect(data == expected, "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter powerMatchingReplayMatchesTheSharedFixture")
    let rides = try #require((JSONSerialization.jsonObject(with: data) as? [String: Any])?["rides"] as? [[String: Any]])
    #expect(rides.count == 6)
    // The scenarios must actually exercise every status, or the fixture proves little.
    let kinds = Set(rides.flatMap { ($0["outputs"] as? [[Any]] ?? []).compactMap { $0[1] as? String } })
    #expect(kinds == ["warming", "matching", "fadeHold"], "statuses seen: \(kinds)")
}
