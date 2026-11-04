import Foundation

/// Ownership includes preparation and release, not just the active workout.
/// Every asynchronous callback must carry the generation it was issued under.
public struct SessionOwnership: Sendable {
    public enum Phase: String, Sendable { case idle, starting, running, finishing }
    public private(set) var phase: Phase = .idle
    public private(set) var generation: UUID?
    public private(set) var cancellationReason: String?
    public var isBusy: Bool { phase != .idle }
    public init() {}

    public mutating func begin() -> UUID? {
        guard !isBusy else { return nil }
        let id = UUID(); generation = id; phase = .starting; cancellationReason = nil
        return id
    }
    public func owns(_ id: UUID) -> Bool { generation == id && isBusy }
    public func canControl(_ id: UUID) -> Bool { owns(id) && phase == .running }
    public mutating func cancelStart(_ reason: String) {
        if phase == .starting { cancellationReason = reason }
    }
    @discardableResult public mutating func started(_ id: UUID) -> Bool {
        guard owns(id), phase == .starting, cancellationReason == nil else { return false }
        phase = .running; return true
    }
    @discardableResult public mutating func beginFinishing(_ id: UUID) -> Bool {
        guard owns(id), phase != .finishing else { return false }
        phase = .finishing; return true
    }
    public mutating func released(_ id: UUID) {
        guard owns(id), phase == .finishing else { return }
        phase = .idle; generation = nil; cancellationReason = nil
    }
}
