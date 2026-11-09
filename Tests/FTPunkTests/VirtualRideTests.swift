import Foundation
import Testing
import FTPunkDomain
import FTPunkDevices

private func samples(_ range: ClosedRange<Int>, watts: Double, left: Double? = nil) -> [RideSample] {
    range.map { RideSample(time: Double($0), power: watts, leftBalance: left) }
}
private func track(_ samples: [RideSample], pauses: [RidePause] = [], riderKG: Double? = 75) -> RideTrack {
    RideTrack.make(samples: samples, pauses: pauses, end: samples.last?.time ?? 0, riderKG: riderKG)
}

@Test func twoHundredWattsOnAGravelBikeIsAboutThirtyKilometresAnHour() throws {
    let result = track(samples(0...599, watts: 200))
    let speed = try #require(result.points.last?.speed)
    #expect(speed * 3.6 > 29 && speed * 3.6 < 32)
    #expect(abs(VirtualBike.dragArea(riderKG: 75) - 0.42) < 1e-12)
    #expect(result.distance > 4_500 && result.distance < 5_300)
}

@Test func aHeavierRiderOfAverageProportionsIsSlowerAtTheSamePowerAndAnUnknownWeightUsesTheDefault() throws {
    let light = track(samples(0...599, watts: 200), riderKG: 60), heavy = track(samples(0...599, watts: 200), riderKG: 100)
    #expect(light.distance > heavy.distance)
    #expect(track(samples(0...599, watts: 200), riderKG: nil).distance == track(samples(0...599, watts: 200), riderKG: 75).distance)
}

@Test func workIsPowerOverTimeAndCaloriesAssumeTwentyFourPercentEfficiency() {
    let result = track(samples(0...599, watts: 200))
    #expect(result.kilojoules == 120)
    #expect(abs(result.kilocalories - 119.5) < 0.1)
    #expect(result.averagePower == 200)
}

@Test func coastingSlowsGraduallyAndDistanceKeepsGrowing() throws {
    let result = track(samples(0...299, watts: 200) + samples(300...360, watts: 0))
    let before = try #require(result.points.first { $0.second == 299 }), after = try #require(result.points.first { $0.second == 300 })
    let last = try #require(result.points.last)
    #expect(after.speed > before.speed * 0.9 && after.speed < before.speed)
    #expect(last.speed < after.speed && last.distance > after.distance)
    #expect(after.joules == before.joules)
}

@Test func pausedTimeAddsNothingAndTheBikeRestartsFromAStandstill() throws {
    let pause = RidePause(stop: 100, resume: 160)
    let result = track(samples(0...199, watts: 200), pauses: [pause])
    #expect(!result.points.contains { $0.second >= 100 && $0.second < 160 })
    #expect(result.kilojoules == 28) // 140 s at 200 W
    let restart = try #require(result.points.first { $0.second == 160 })
    #expect(restart.speed < 3)
    #expect(result.speed(at: 199.5) > 0 && result.speed(at: 210) == 0)
}

@Test func aShortDropoutHoldsThePowerAndALongOneCoasts() throws {
    let short = track(samples(0...9, watts: 100) + samples(12...20, watts: 100))
    #expect(short.kilojoules == 2.1) // every second from 0 to 20 at 100 W
    let long = track(samples(0...9, watts: 100) + samples(20...25, watts: 100))
    #expect(long.points.first { $0.second == 15 }?.power == 0)
}

@Test func lapSpansAddUpToTheWholeRide() {
    let result = track(samples(0...299, watts: 180))
    let first = result.span(from: 0, to: 100), second = result.span(from: 100, to: .infinity)
    #expect(first.seconds == 100 && second.seconds == 200)
    #expect(abs(first.distance + second.distance - result.distance) < 1e-9)
    #expect(first.joules == 18_000)
    #expect(second.maximumSpeed == result.whole.maximumSpeed)
}

@Test func noPowerMeansNoTrack() {
    #expect(track([RideSample(time: 0, heartRate: 120), RideSample(time: 5, heartRate: 121)]).points.isEmpty)
}

@Test func balanceIsWeightedByPowerAndIgnoresSecondsWithoutPower() throws {
    let recorded = samples(0...9, watts: 300, left: 40) + samples(10...19, watts: 100, left: 60) + samples(20...29, watts: 0, left: 90)
    let ride = track(recorded)
    let balance = try #require(RideBalance.make(samples: recorded, pauses: [], end: 29, track: ride))
    #expect(balance.seconds.count == 20)
    #expect(abs(balance.left - 45) < 1e-9)
    #expect(RideBalance.make(samples: samples(0...9, watts: 300), pauses: [], end: 9, track: track(samples(0...9, watts: 300))) == nil)
}

@Test func balanceSeriesSmoothsSplitsAtGapsAndKeepsTheAxisSymmetric() throws {
    let recorded = samples(0...99, watts: 200, left: 46) + samples(120...219, watts: 200, left: 53)
    let ride = track(recorded)
    let balance = try #require(RideBalance.make(samples: recorded, pauses: [], end: 219, track: ride))
    let points = balance.series()
    #expect(Set(points.map(\.segment)) == [0, 1])
    #expect(abs(try #require(points.last).left - 53) < 1e-9)
    #expect(points.count <= 301)
    #expect(RideBalance.axisReach(points) == 6)
    #expect(RideBalance.axisReach([RideBalance.Point(time: 0, left: 49.5, segment: 0)]) == 4)
}

@Test func liveBalanceAveragesTheLastTenSeconds() {
    let recorded = samples(0...50, watts: 200, left: 40) + samples(51...60, watts: 200, left: 52)
    #expect(RideBalance.live(recorded) == 560.0 / 11)
    #expect(RideBalance.live(samples(0...5, watts: 200)) == nil)
}

@Test func aPowerMetersBalanceWinsOverATrainersWhileItReportsOne() {
    var measurements = DeviceMeasurements()
    #expect(measurements.takesBalance(from: .trainer, at: 10))
    measurements.receive(DeviceReading(role: .pedals, uptime: 10, power: 200, leftBalance: 48))
    #expect(!measurements.takesBalance(from: .trainer, at: 11))
    #expect(measurements.takesBalance(from: .pedals, at: 11))
    #expect(measurements.takesBalance(from: .trainer, at: 13))
}
