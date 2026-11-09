import Foundation

/// A span where the timer was stopped. Pause requests, confirmed release and resume are stored as timestamped events
/// (contracts/README.md): the timer stops at the confirmed release (the request when no confirmation was recorded) and starts at resume.
public struct RidePause: Equatable, Sendable {
    public let stop: Double
    public let resume: Double?
    public init(stop: Double, resume: Double?) { self.stop = stop; self.resume = resume }

    public func contains(_ time: Double) -> Bool { time >= stop && time < (resume ?? .infinity) }

    public static func list(_ session: TestSession) -> [RidePause] {
        var result: [RidePause] = [], requested: Double?, confirmed: Double?
        for event in session.events.sorted(by: { $0.time < $1.time }) {
            switch event.message {
            case "Training paused; trainer release requested": requested = event.time; confirmed = nil
            case "Trainer release confirmed for pause": if requested != nil, confirmed == nil { confirmed = event.time }
            case "Training resumed":
                if let requested { result.append(RidePause(stop: confirmed ?? requested, resume: event.time)) }
                requested = nil; confirmed = nil
            default: break
            }
        }
        if let requested { result.append(RidePause(stop: confirmed ?? requested, resume: nil)) }
        return result
    }
}

/// The simulated bike: a gravel bike ridden on the hoods along a flat road in still air.
///
/// Only + − × ÷ and square roots are used, which every IEEE platform computes identically: the FIT files written by the app and by the web
/// app must match byte for byte. Mirrored in ftpunk_web/src/rules/virtual-ride.mjs.
public enum VirtualBike {
    public static let defaultRiderKG = 75.0
    public static let bikeKG = 10.0
    public static let airDensity = 1.225
    public static let rollingResistance = 0.0055
    public static let drivetrainEfficiency = 0.97
    public static let gravity = 9.81
    /// Gross efficiency of a rider: the share of food energy that reaches the pedals.
    public static let humanEfficiency = 0.24
    public static let joulesPerKilocalorie = 4184.0

    /// CdA in m². 0.42 m² for a 75 kg rider: 0.07 for the bike, 0.35 for the rider. A rider of average proportions has a frontal area
    /// that grows with mass^(2/3); (75 + 2m) / 225 is that curve's tangent at 75 kg, within 2 % from 45 to 120 kg.
    public static func dragArea(riderKG: Double) -> Double { 0.07 + 0.35 * (75 + 2 * riderKG) / 225 }

    /// The rider's weight used by the simulation: their own when known, kept within a plausible range.
    public static func riderKG(_ weight: Double?) -> Double {
        guard let weight, weight.isFinite, weight > 0 else { return defaultRiderKG }
        return min(150, max(40, weight))
    }

    /// The speed in m/s after one second at `watts`, from the energy balance of the rider and bike: kinetic energy gains what reaches
    /// the wheel and loses what air and tyres take. Coasting therefore slows down gradually instead of stopping at once.
    public static func step(speed: Double, watts: Double, riderKG: Double) -> Double {
        let mass = riderKG + bikeKG
        let resisting = 0.5 * airDensity * dragArea(riderKG: riderKG) * speed * speed * speed + rollingResistance * mass * gravity * speed
        let energy = 0.5 * mass * speed * speed + watts * drivetrainEfficiency - resisting
        return energy > 0 ? (2 * energy / mass).squareRoot() : 0
    }
}

/// Second-by-second simulated speed, distance and work for a recording. Derived from recorded power, so it needs no extra stored data and
/// also works for rides recorded before this existed. Paused time adds nothing and the bike restarts from a standstill after it.
public struct RideTrack: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let second: Int
        public let power: Double
        public let speed: Double
        /// Totals up to and including this second.
        public let distance: Double
        public let joules: Double
    }
    public struct Span: Equatable, Sendable {
        public let distance: Double
        public let joules: Double
        public let seconds: Int
        public let maximumSpeed: Double
        public var kilocalories: Double { RideTrack.kilocalories(joules: joules) }
        public var averageSpeed: Double { seconds > 0 ? distance / Double(seconds) : 0 }
    }

    public var points: [Point]

    public static func kilocalories(joules: Double) -> Double {
        joules / VirtualBike.humanEfficiency / VirtualBike.joulesPerKilocalorie
    }

    public static func make(_ session: TestSession) -> RideTrack {
        make(samples: session.samples, pauses: RidePause.list(session), end: session.endedAtOffset ?? session.samples.last?.time ?? 0,
             riderKG: session.configuration.weightKG)
    }

    public static func make(samples: [RideSample], pauses: [RidePause], end: Double, riderKG: Double?) -> RideTrack {
        guard end.isFinite, end >= 0 else { return RideTrack(points: []) }
        var sums = [Double](repeating: 0, count: Int(end) + 1), counts = [Int](repeating: 0, count: Int(end) + 1)
        var last = -1
        for sample in samples where sample.time.isFinite && sample.time >= 0 && sample.time <= end {
            guard let power = sample.power, power.isFinite, !pauses.contains(where: { $0.contains(sample.time) }) else { continue }
            let second = Int(sample.time)
            sums[second] += max(0, power); counts[second] += 1; last = max(last, second)
        }
        guard last >= 0 else { return RideTrack(points: []) }

        let weight = VirtualBike.riderKG(riderKG)
        var points: [Point] = []
        var held: Double?, heldAt = 0, speed = 0.0, distance = 0.0, joules = 0.0, started = false
        for second in 0...last {
            var watts = 0.0
            if counts[second] > 0 {
                watts = sums[second] / Double(counts[second]); held = watts; heldAt = second; started = true
            } else if pauses.contains(where: { $0.contains(Double(second)) }) {
                speed = 0; held = nil; continue
            } else if !started {
                continue
            } else if let held, second - heldAt <= 2 {
                watts = held // A dropped notification or two is not the rider stopping.
            }
            let next = VirtualBike.step(speed: speed, watts: watts, riderKG: weight)
            distance += (speed + next) / 2
            joules += watts
            speed = next
            points.append(Point(second: second, power: watts, speed: speed, distance: distance, joules: joules))
        }
        return RideTrack(points: points)
    }

    public var distance: Double { points.last?.distance ?? 0 }
    public var joules: Double { points.last?.joules ?? 0 }
    public var kilojoules: Double { joules / 1000 }
    public var kilocalories: Double { Self.kilocalories(joules: joules) }
    public var averagePower: Double? { points.isEmpty ? nil : joules / Double(points.count) }
    public var whole: Span {
        Span(distance: distance, joules: joules, seconds: points.count, maximumSpeed: points.map(\.speed).max() ?? 0)
    }

    /// What the rider is doing now: nothing once the last riding second is more than three seconds old (a pause or a dropout).
    public func speed(at time: Double) -> Double {
        guard let last = points.last, time - Double(last.second) <= 3 else { return 0 }
        return last.speed
    }

    /// The seconds from `begin` up to, but not including, `finish`.
    public func span(from begin: Double, to finish: Double) -> Span {
        var before: Point?, after: Point?, seconds = 0, maximum = 0.0
        for point in points {
            let time = Double(point.second)
            if time < begin { before = point; continue }
            if time >= finish { break }
            after = point; seconds += 1; maximum = max(maximum, point.speed)
        }
        guard let after else { return Span(distance: 0, joules: 0, seconds: 0, maximumSpeed: 0) }
        return Span(distance: after.distance - (before?.distance ?? 0), joules: after.joules - (before?.joules ?? 0), seconds: seconds, maximumSpeed: maximum)
    }
}

/// Left/right pedal balance. Readings count only in seconds when the rider was producing power: a meter's balance at zero watts means nothing.
public struct RideBalance: Equatable, Sendable {
    public struct Second: Equatable, Sendable { public let second: Int; public let left: Double; public let power: Double }
    public struct Point: Equatable, Sendable {
        public let time: Double, left: Double, segment: Int
        public init(time: Double, left: Double, segment: Int) { self.time = time; self.left = left; self.segment = segment }
    }

    public var seconds: [Second]

    public static func make(_ session: TestSession, track: RideTrack? = nil) -> RideBalance? {
        let pauses = RidePause.list(session), end = session.endedAtOffset ?? session.samples.last?.time ?? 0
        return make(samples: session.samples, pauses: pauses, end: end, track: track ?? RideTrack.make(session))
    }

    public static func make(samples: [RideSample], pauses: [RidePause], end: Double, track: RideTrack) -> RideBalance? {
        guard end.isFinite, end >= 0 else { return nil }
        var sums = [Double](repeating: 0, count: Int(end) + 1), counts = [Int](repeating: 0, count: Int(end) + 1)
        for sample in samples where sample.time.isFinite && sample.time >= 0 && sample.time <= end {
            guard let left = sample.leftBalance, left.isFinite, left >= 0, left <= 100, !pauses.contains(where: { $0.contains(sample.time) }) else { continue }
            sums[Int(sample.time)] += left; counts[Int(sample.time)] += 1
        }
        let seconds = track.points.compactMap { point -> Second? in
            guard point.power > 0, counts[point.second] > 0 else { return nil }
            return Second(second: point.second, left: sums[point.second] / Double(counts[point.second]), power: point.power)
        }
        return seconds.isEmpty ? nil : RideBalance(seconds: seconds)
    }

    /// The share of the ride's work done by the left leg, in percent.
    public var left: Double {
        let work = seconds.reduce(0.0) { $0 + $1.power }
        return seconds.reduce(0.0) { $0 + $1.left * $1.power } / work
    }

    /// The last ten seconds of readings, or nil when there are none.
    public static func live(_ samples: [RideSample]) -> Double? {
        guard let now = samples.last?.time else { return nil }
        var total = 0.0, count = 0
        for sample in samples.reversed() {
            if now - sample.time > 10 { break }
            if let left = sample.leftBalance, left.isFinite, sample.power.map({ $0 > 0 }) ?? true { total += left; count += 1 }
        }
        return count > 0 ? total / Double(count) : nil
    }

    /// How far the chart's axis reaches either side of 50 %: at least 4 points, in steps of 2, with some room above the largest swing.
    public static func axisReach(_ points: [Point]) -> Double {
        let swing = points.map { abs($0.left - 50) }.max() ?? 0
        return min(50, max(4, (swing / 2).rounded(.up) * 2 + 2))
    }

    /// A 30-second power-weighted trailing mean, thinned to at most about 300 points. A gap of more than five seconds starts a new segment.
    public func series(maximumPoints: Int = 300) -> [Point] {
        let stride = max(1, seconds.count / max(1, maximumPoints))
        var result: [Point] = [], first = 0, weighted = 0.0, work = 0.0, segment = 0
        for (index, entry) in seconds.enumerated() {
            if index > 0, entry.second - seconds[index - 1].second > 5 {
                segment += 1; first = index; weighted = 0; work = 0
            }
            weighted += entry.left * entry.power; work += entry.power
            while entry.second - seconds[first].second >= 30 {
                weighted -= seconds[first].left * seconds[first].power; work -= seconds[first].power; first += 1
            }
            if index - first >= 4, index % stride == 0 || index == seconds.count - 1 {
                result.append(Point(time: Double(entry.second), left: weighted / work, segment: segment))
            }
        }
        return result
    }
}
