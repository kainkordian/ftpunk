import Foundation

public enum ResistanceLayout: String, CaseIterable, Sendable {
    case standardOneByte, legacyTwoBytes
}

public struct IndoorBikeData: Equatable, Sendable {
    public var moreData: Bool = false
    public var speedKPH: Double?
    public var cadenceRPM: Double?
    public var powerWatts: Double?
    public var heartRate: Int?

    public static func decode(_ data: Data, resistanceLayout: ResistanceLayout = .standardOneByte) throws -> Self {
        var cursor = ByteCursor(data)
        let flags = try cursor.u16()
        guard flags & 0xe000 == 0 else { throw PacketError.unsupportedFlags }
        var result = Self(); result.moreData = flags & 1 != 0
        if !result.moreData { result.speedKPH = Double(try cursor.u16()) / 100 }
        if flags & (1 << 1) != 0 { try cursor.skip(2) }
        if flags & (1 << 2) != 0 { result.cadenceRPM = Double(try cursor.u16()) / 2 }
        if flags & (1 << 3) != 0 { try cursor.skip(2) }
        if flags & (1 << 4) != 0 { _ = try cursor.u24() }
        if flags & (1 << 5) != 0 { try cursor.skip(resistanceLayout == .standardOneByte ? 1 : 2) }
        if flags & (1 << 6) != 0 { result.powerWatts = Double(try cursor.i16()) }
        if flags & (1 << 7) != 0 { try cursor.skip(2) }
        if flags & (1 << 8) != 0 { try cursor.skip(5) }
        if flags & (1 << 9) != 0 { result.heartRate = Int(try cursor.u8()) }
        if flags & (1 << 10) != 0 { try cursor.skip(1) }
        if flags & (1 << 11) != 0 { try cursor.skip(2) }
        if flags & (1 << 12) != 0 { try cursor.skip(2) }
        try cursor.finish(); return result
    }
}

/// Assemble decoded fields, never concatenated byte buffers with repeated flags.
public struct IndoorBikeRecordAssembler: Sendable {
    private var pending: IndoorBikeData?
    private var beganAt: Double?
    public init() {}
    public mutating func reset() { pending = nil; beganAt = nil }
    public mutating func receive(_ value: IndoorBikeData, at time: Double) -> IndoorBikeData? {
        if let beganAt, time < beganAt || time - beganAt > 2 { reset() }
        if value.moreData {
            if pending == nil { pending = value; beganAt = time }
            else { merge(value) }
            return nil
        }
        guard pending != nil else { return value }
        merge(value)
        let completed = pending
        reset(); return completed
    }
    private mutating func merge(_ value: IndoorBikeData) {
        pending?.moreData = value.moreData
        if let v = value.speedKPH { pending?.speedKPH = v }
        if let v = value.powerWatts { pending?.powerWatts = v }
        if let v = value.cadenceRPM { pending?.cadenceRPM = v }
        if let v = value.heartRate { pending?.heartRate = v }
    }
}
