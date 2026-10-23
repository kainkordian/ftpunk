import Foundation
import Testing
@testable import FTPunkDevices

@Test func indoorBikeFlagsAndSignedPower() throws {
    let value = try IndoorBikeData.decode(Data([0x44, 0, 0xc4, 9, 0xb4, 0, 0xc8, 0]))
    #expect(value.powerWatts == 200); #expect(value.cadenceRPM == 90); #expect(value.speedKPH == 25)
    let negative = try IndoorBikeData.decode(Data([0x40, 0, 0, 0, 0xf6, 0xff]))
    #expect(negative.powerWatts == -10); #expect(negative.cadenceRPM == nil)
    let noSpeed = try IndoorBikeData.decode(Data([0x41, 0, 0xc8, 0]))
    #expect(noSpeed.speedKPH == nil); #expect(noSpeed.powerWatts == 200)
}

@Test func truncatedFieldsNeverBecomeZero() {
    let full = Data([0x44, 0, 0xc4, 9, 0xb4, 0, 0xc8, 0])
    for count in 0..<full.count {
        #expect(throws: (any Error).self) { try IndoorBikeData.decode(full.prefix(count)) }
    }
}

@Test func dataSlicesAndExplicitResistanceLayouts() throws {
    let backing = Data([0xaa, 0xaa, 0x60, 0, 0, 0, 5, 0xc8, 0])
    #expect(try IndoorBikeData.decode(backing.dropFirst(2)).powerWatts == 200)
    let legacy = Data([0x60, 0, 0, 0, 5, 0, 0xc8, 0])
    #expect(throws: PacketError.trailingBytes) { try IndoorBikeData.decode(legacy) }
    #expect(try IndoorBikeData.decode(legacy, resistanceLayout: .legacyTwoBytes).powerWatts == 200)
}

@Test func allOptionalFieldsBeforePower() throws {
    // speed, average speed, cadence, average cadence, UInt24 distance, resistance, signed power
    let packet = Data([0x7e, 0, 0xc4, 9, 0, 0, 0xb4, 0, 0, 0, 1, 2, 3, 5, 0xc8, 0])
    let value = try IndoorBikeData.decode(packet)
    #expect(value.powerWatts == 200); #expect(value.cadenceRPM == 90)
}

@Test func multiNotificationRecordsExpire() throws {
    var assembler = IndoorBikeRecordAssembler()
    let first = try IndoorBikeData.decode(Data([0x41, 0, 0xc8, 0]))
    let last = try IndoorBikeData.decode(Data([0x04, 0, 0xc4, 9, 0xb4, 0]))
    #expect(assembler.receive(first, at: 0) == nil)
    let combined = assembler.receive(last, at: 0.1)
    #expect(combined?.powerWatts == 200); #expect(combined?.cadenceRPM == 90)
    _ = assembler.receive(first, at: 1)
    #expect(assembler.receive(last, at: 4)?.powerWatts == nil)
}

@Test func pedalOptionalFieldsAndCrankRollover() throws {
    let value = try CyclingPowerMeasurement.decode(Data([
        0x37, 0, 0xc8, 0, 100, 0, 0, // power, left balance, torque
        0, 0, 0, 0, 0, 0, // wheel data
        0xff, 0xff, 0, 0xfc // crank at revolution 65535, tick 64512
    ]))
    #expect(value.watts == 200); #expect(value.leftBalancePercent == 50)
    var tracker = CadenceTracker()
    #expect(tracker.receive(try #require(value.crank), at: 0) == nil)
    #expect(tracker.receive(CrankEvent(revolutions: 0, ticks: 0), at: 1) == 60)
    #expect(tracker.receive(CrankEvent(revolutions: 0, ticks: 0), at: 2) == nil)
    #expect(tracker.receive(CrankEvent(revolutions: 0, ticks: 0), at: 3) == 0)
    tracker.reset()
    #expect(tracker.receive(CrankEvent(revolutions: 100, ticks: 10), at: 4) == nil)
}

@Test func commandsAndApplicationAcknowledgements() throws {
    #expect(try TrainerCommand.targetPower(200).encoded() == Data([5, 0xc8, 0]))
    #expect(try TrainerCommand.stop.encoded() == Data([8, 1]))
    #expect(throws: PacketError.invalidValue) { try TrainerCommand.targetPower(-1).encoded() }
    #expect(try ControlResponse.decode(Data([0x80, 5, 1])).succeeded)
    #expect(try !ControlResponse.decode(Data([0x80, 5, 5])).succeeded)
    #expect(throws: (any Error).self) { try ControlResponse.decode(Data([0x80, 5])) }
    let range = try SupportedPowerRange.decode(Data([50, 0, 0xf4, 1, 5, 0]))
    #expect(range.quantized(123) == 125); #expect(range.quantized(1000) == 500)
}

@Test func heartRateFormats() throws {
    #expect(try HeartRateMeasurement.decode(Data([0, 155])) == 155)
    #expect(try HeartRateMeasurement.decode(Data([1, 0, 1])) == 256)
    #expect(throws: (any Error).self) { try HeartRateMeasurement.decode(Data([1, 0])) }
}
