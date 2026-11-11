import Testing
import Foundation
@testable import FTPunkDomain

/// Deterministic noise in −0.5…0.5 so the expected exponents don't depend on a random seed.
private struct Noise {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) - 0.5
    }
}

@Test func dfaAlpha1SeparatesUncorrelatedFromStronglyCorrelatedBeats() throws {
    var noise = Noise(state: 7)
    let white = (0..<2000).map { _ in 0.8 + 0.05 * noise.next() }
    var walk: [Double] = [], level = 0.0
    for _ in 0..<2000 { level += 0.002 * noise.next(); walk.append(0.8 + level) }
    let whiteAlpha = try #require(HeartRateVariability.alpha1(white))
    let walkAlpha = try #require(HeartRateVariability.alpha1(walk))
    #expect(abs(whiteAlpha - 0.5) < 0.1)
    #expect(abs(walkAlpha - 1.5) < 0.15)
    #expect(HeartRateVariability.alpha1(Array(white.prefix(49))) == nil)
}

@Test func rmssdIsTheRootMeanSquareOfSuccessiveDifferences() throws {
    let alternating = (0..<40).map { $0 % 2 == 0 ? 0.80 : 0.82 }   // every difference is 20 ms
    #expect(abs(try #require(HeartRateVariability.rmssd(alternating)) - 20) < 1e-9)
    #expect(HeartRateVariability.rmssd(Array(alternating.prefix(29))) == nil)
}

@Test func rideHrvTimesBeatsRejectsArtifactsAndSkipsWindowsWithTooMany() throws {
    var session = TestSession(configuration: try SessionConfiguration(warmupSeconds: 0, riderID: RiderProfile.legacyID))
    var noise = Noise(state: 3), time = 0.0
    // Ten minutes at ~75 bpm, one notification per beat; minutes 6–8 have every fifth beat missed (a doubled interval).
    var beat = 0
    while time < 600 {
        var interval = 0.8 + 0.04 * noise.next()
        if time > 360, time < 480, beat % 5 == 0 { interval *= 2 }
        time += interval; beat += 1
        session.samples.append(RideSample(time: time, heartRate: 75, rrIntervals: [interval]))
    }
    session.endedAtOffset = time
    let beats = HeartRateVariability.beats(session)
    #expect(beats.count == session.samples.count)
    #expect(abs(beats[10].time - session.samples[10].time) < 1e-9)
    let result = try #require(HeartRateVariability.make(session))
    #expect(result.artifactShare > 0.02 && result.artifactShare < 0.06)
    let rmssd = try #require(result.rmssd)
    #expect(rmssd > 10 && rmssd < 30)   // the doubled beats are not in it
    #expect(!result.alpha1.isEmpty)
    #expect(!result.alpha1.contains { $0.time > 400 && $0.time < 480 })   // windows overlapping the artifacts are left out
    #expect(result.alpha1.allSatisfy { $0.alpha1 > 0.2 && $0.alpha1 < 0.9 })

    // A notification with two intervals places the earlier beat before the later one.
    var two = TestSession(configuration: session.configuration)
    two.samples = [RideSample(time: 10, heartRate: 70, rrIntervals: [0.9, 0.8])]
    #expect(HeartRateVariability.beats(two).map(\.time) == [9.2, 10])
}
