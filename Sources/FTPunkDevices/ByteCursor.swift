import Foundation

public enum PacketError: Error, Equatable, LocalizedError {
    case truncated, unsupportedFlags, trailingBytes, invalidValue, unexpectedResponse
    public var errorDescription: String? { "Invalid Bluetooth packet: \(self)." }
}

struct ByteCursor {
    private let bytes: [UInt8]
    private(set) var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    var remaining: Int { bytes.count - offset }
    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw PacketError.truncated }
        defer { offset += 1 }; return bytes[offset]
    }
    mutating func u16() throws -> UInt16 {
        let low = try u8(); return UInt16(low) | (UInt16(try u8()) << 8)
    }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func u24() throws -> UInt32 {
        let low = try u16(); return UInt32(low) | (UInt32(try u8()) << 16)
    }
    mutating func u32() throws -> UInt32 {
        let low = try u16(); return UInt32(low) | (UInt32(try u16()) << 16)
    }
    mutating func skip(_ count: Int) throws {
        guard remaining >= count else { throw PacketError.truncated }; offset += count
    }
    func finish() throws { if remaining != 0 { throw PacketError.trailingBytes } }
}
