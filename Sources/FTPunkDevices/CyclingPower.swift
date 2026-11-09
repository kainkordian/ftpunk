import Foundation

public struct CrankEvent: Equatable, Sendable {
    public let revolutions: UInt16
    public let ticks: UInt16
    public init(revolutions: UInt16, ticks: UInt16) { self.revolutions = revolutions; self.ticks = ticks }
}

public struct CyclingPowerMeasurement: Equatable, Sendable {
    public let watts: Double
    public let leftBalancePercent: Double?
    public let crank: CrankEvent?
    public static func decode(_ data: Data) throws -> Self {
        var cursor = ByteCursor(data)
        let flags = try cursor.u16()
        guard flags & 0xe000 == 0 else { throw PacketError.unsupportedFlags }
        let watts = Double(try cursor.i16())
        var balance: Double?
        if flags & 1 != 0 {
            let raw = try cursor.u8()
            guard raw <= 200 else { throw PacketError.invalidValue }
            if flags & 2 != 0 { balance = Double(raw) / 2 }
        }
        if flags & (1 << 2) != 0 { try cursor.skip(2) }
        if flags & (1 << 4) != 0 { try cursor.skip(6) }
        var crank: CrankEvent?
        if flags & (1 << 5) != 0 { crank = CrankEvent(revolutions: try cursor.u16(), ticks: try cursor.u16()) }
        if flags & (1 << 6) != 0 { try cursor.skip(4) }
        if flags & (1 << 7) != 0 { try cursor.skip(4) }
        if flags & (1 << 8) != 0 { try cursor.skip(3) }
        if flags & (1 << 9) != 0 { try cursor.skip(2) }
        if flags & (1 << 10) != 0 { try cursor.skip(2) }
        if flags & (1 << 11) != 0 { try cursor.skip(2) }
        try cursor.finish()
        return Self(watts: watts, leftBalancePercent: balance, crank: crank)
    }
}

public struct CadenceTracker: Sendable {
    private var previous: CrankEvent?
    private var lastReceipt: Double?
    private var lastMovement: Double?
    public init() {}
    public mutating func reset() { previous = nil; lastReceipt = nil; lastMovement = nil }
    public mutating func receive(_ event: CrankEvent, at time: Double) -> Double? {
        defer { previous = event; lastReceipt = time }
        guard let previous, let lastReceipt, time > lastReceipt, time - lastReceipt <= 5 else {
            lastMovement = time; return nil
        }
        if event == previous {
            return time - (lastMovement ?? time) >= 2 ? 0 : nil
        }
        let revs = event.revolutions &- previous.revolutions
        let ticks = event.ticks &- previous.ticks
        guard ticks > 0, revs > 0 else { lastMovement = time; return nil }
        let rpm = 60 * Double(revs) * 1024 / Double(ticks)
        guard rpm <= 250 else { lastMovement = time; return nil }
        lastMovement = time; return rpm
    }
}

public enum HeartRateMeasurement {
    public struct Reading: Equatable, Sendable {
        public let heartRate: Int
        /// Beat-to-beat intervals in seconds. Nil when the packet carried none.
        public let rrIntervals: [Double]?
    }

    public static func decode(_ data: Data) throws -> Int { try reading(data).heartRate }

    public static func reading(_ data: Data) throws -> Reading {
        var cursor = ByteCursor(data)
        let flags = try cursor.u8()
        guard flags & 0xe0 == 0 else { throw PacketError.unsupportedFlags }
        let value = flags & 1 == 0 ? Int(try cursor.u8()) : Int(try cursor.u16())
        if flags & 8 != 0 { try cursor.skip(2) }
        var intervals: [Double]?
        if flags & 16 != 0 {
            guard cursor.remaining >= 2, cursor.remaining.isMultiple(of: 2) else { throw PacketError.truncated }
            var values: [Double] = []
            while cursor.remaining > 0 { values.append(Double(try cursor.u16()) / 1024) }
            intervals = values
        }
        try cursor.finish(); return Reading(heartRate: value, rrIntervals: intervals)
    }
}
