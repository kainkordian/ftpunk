import Foundation

public struct SupportedPowerRange: Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public let increment: Int
    public init(minimum: Int, maximum: Int, increment: Int) throws {
        guard minimum >= 0, maximum > minimum, increment > 0 else { throw PacketError.invalidValue }
        self.minimum = minimum; self.maximum = maximum; self.increment = increment
    }
    public static func decode(_ data: Data) throws -> Self {
        var c = ByteCursor(data)
        let result = try Self(minimum: Int(c.i16()), maximum: Int(c.i16()), increment: Int(c.u16()))
        try c.finish(); return result
    }
    public func quantized(_ watts: Int) -> Int {
        let clamped = min(maximum, max(minimum, watts))
        let step = Int((Double(clamped - minimum) / Double(increment)).rounded())
        return min(maximum, minimum + step * increment)
    }
}

public struct FitnessMachineFeatures: Sendable {
    public let supportsTargetPower: Bool
    public static func decode(_ data: Data) throws -> Self {
        var c = ByteCursor(data)
        _ = try c.u32()
        let targets = try c.u32()
        try c.finish()
        return Self(supportsTargetPower: targets & (1 << 3) != 0)
    }
}

public enum TrainerCommand: Equatable, Sendable {
    case requestControl, start, targetPower(Int), stop
    public var opcode: UInt8 {
        switch self { case .requestControl: 0; case .start: 7; case .targetPower: 5; case .stop: 8 }
    }
    public func encoded() throws -> Data {
        switch self {
        case .requestControl, .start: return Data([opcode])
        case .stop: return Data([opcode, 1])
        case .targetPower(let watts):
            guard (0...32767).contains(watts) else { throw PacketError.invalidValue }
            return Data([opcode, UInt8(watts & 255), UInt8((watts >> 8) & 255)])
        }
    }
}

public struct ControlResponse: Equatable, Sendable {
    public let requestOpcode: UInt8
    public let result: UInt8
    public var succeeded: Bool { result == 1 }
    public static func decode(_ data: Data) throws -> Self {
        var cursor = ByteCursor(data)
        guard try cursor.u8() == 0x80 else { throw PacketError.unexpectedResponse }
        let response = Self(requestOpcode: try cursor.u8(), result: try cursor.u8())
        try cursor.finish()
        guard (1...5).contains(response.result) else { throw PacketError.invalidValue }
        return response
    }
}
