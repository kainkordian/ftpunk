import Foundation

/// What the strip has accumulated while it animates: how far the road has scrolled, how many times the cranks
/// have turned, and the signs and districts that were announced ahead of the rider. It is advanced by the strip from
/// the current `RideVisualState`; nothing flows back to the ride.
public struct RideVisualMotion: Equatable, Sendable {
    /// The scenery repeats exactly after this many road pixels and this many seconds, so it never counts towards
    /// a finish.
    public static let loopDistance = 1536.0
    public static let loopTime = 3.0
    /// Road pixels between the rider and the right edge of the view.
    public static let viewDistance = 128.0

    public struct Marker: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case level, gantry, billboard, gate }
        public var kind: Kind
        public var text: String
        public var worldX: Double
    }
    public struct Segment: Equatable, Sendable {
        public var startX: Double
        public var district: RideVisualDistrict
    }

    public private(set) var distance = 0.0
    public private(set) var time = 0.0
    public private(set) var crankTurns = 0.0
    public private(set) var markers: [Marker] = []
    public private(set) var segments: [Segment] = []
    private var lastUpcoming: Int?
    private var lastGate: String?
    private var lastDistrict: RideVisualDistrict?

    public init(distance: Double = 0, time: Double = 0, crankTurns: Double = 0) {
        self.distance = distance; self.time = time; self.crankTurns = crankTurns
    }

    public mutating func advance(by seconds: Double, state: RideVisualState) {
        let dt = seconds.isFinite ? min(0.25, max(0, seconds)) : 0
        time += dt * state.animationRate
        distance += state.worldSpeed * dt
        if let period = state.pedalPeriod { crankTurns += dt / period }
        observe(state)
        markers.removeAll { $0.worldX < distance - 90 }
        while segments.count > 1, segments[1].startX < distance - 220 { segments.removeFirst() }
    }

    /// The district at a road coordinate, as the scenery sees it.
    public func district(atWorldX x: Double) -> RideVisualDistrict? {
        segments.last { $0.startX <= x }?.district ?? segments.first?.district
    }

    private mutating func observe(_ state: RideVisualState) {
        if segments.isEmpty { segments = [Segment(startX: -1e12, district: state.district)] }
        if let upcoming = state.upcoming, upcoming.key != lastUpcoming {
            lastUpcoming = upcoming.key
            let x = distance + max(24, upcoming.secondsUntil * max(state.worldSpeed, 18))
            switch upcoming.kind {
            case .level: markers.append(Marker(kind: .level, text: upcoming.text, worldX: x))
            case .step:
                markers.append(Marker(kind: .billboard, text: upcoming.text, worldX: x - 30))
                markers.append(Marker(kind: .gantry, text: "", worldX: x))
                if let next = upcoming.district, segments.last?.district != next { segments.append(Segment(startX: x, district: next)) }
            }
        }
        if let sign = state.sign, sign.kind == .gate {
            if let lastGate, lastGate != sign.text {
                markers.append(Marker(kind: .gate, text: sign.text, worldX: distance + Self.viewDistance + 10))
            }
            lastGate = sign.text
        }
        // A district change nobody announced (a different intensity moved the next step across a zone boundary).
        if let lastDistrict, lastDistrict != state.district, segments.last?.district != state.district {
            segments.append(Segment(startX: distance + 40, district: state.district))
        }
        lastDistrict = state.district
    }
}
