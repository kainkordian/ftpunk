import Foundation

/// Immutable chart geometry. No mark or axis closure needs to inspect the recording.
public struct SummaryChartData: Sendable {
    public struct Point: Identifiable, Sendable {
        public let id: Int
        public let time: Double
        public let value: Double
        public let segment: Int
    }
    public let id = UUID()
    public let end: Double
    public let ceiling: Double
    public let heartTop: Double
    public let power, heart, trainer, target: [Point]
    public let heartTicks: [Double]

    public init(session: TestSession) {
        end = RideChartDomain.end(session: session)
        let targets = TargetSeries.make(session)
        var power: [Point] = [], heart: [Point] = [], trainer: [Point] = []
        var peak = targets.map(\.watts).max() ?? 0, heartPeak = 0.0
        func append(_ value: Double?, sample: RideSample, index: Int, gap: Double, to points: inout [Point]) {
            guard let value, value.isFinite, sample.time.isFinite else { return }
            let previous = points.last
            let segment = (previous?.segment ?? 0) + (previous.map { sample.time - $0.time > gap } == true ? 1 : 0)
            points.append(Point(id: index, time: sample.time, value: value, segment: segment))
        }
        for (index, sample) in session.samples.enumerated() {
            append(sample.power, sample: sample, index: index, gap: 2, to: &power)
            append(sample.trainerPower, sample: sample, index: index, gap: 2, to: &trainer)
            append(sample.heartRate.map(Double.init), sample: sample, index: index, gap: 5, to: &heart)
            if let value = power.last?.value { peak = max(peak, value) }
            if let value = trainer.last?.value { peak = max(peak, value) }
            if let value = heart.last?.value { heartPeak = max(heartPeak, value) }
        }
        let ceiling = max(100, ResultChartLayout.ceiling(forPeak: peak))
        let heartTop = max(180, heartPeak + 10)
        self.ceiling = ceiling; self.heartTop = heartTop; self.power = power; self.trainer = trainer
        self.heart = heart.map { Point(id: $0.id, time: $0.time, value: ($0.value - 60) / (heartTop - 60) * ceiling, segment: $0.segment) }
        target = targets.enumerated().map { Point(id: $0.offset, time: $0.element.time, value: $0.element.watts, segment: $0.element.segment) }
        heartTicks = [90.0, 120, 150, 180].filter { $0 <= heartTop }.map { ($0 - 60) / (heartTop - 60) * ceiling }
    }

    public func heartBPM(at y: Double) -> Int { Int(60 + y / ceiling * (heartTop - 60)) }
}

/// Finished recordings are immutable for a session ID. Also handles appended live samples
/// and end/event changes without rebuilding geometry on layout or pointer movement.
public final class SummaryChartCache {
    public struct Revision: Equatable {
        let id: UUID
        let count, events: Int
        let last: RideSample?
        let lastEvent: SessionEvent?
        let end, rampStart, rampEnd, cooldownStart, bestStart, bestEnd: Double?
        let externalPower: Bool
        public init(_ session: TestSession) {
            id = session.id; count = session.samples.count; last = session.samples.last
            events = session.events.count; lastEvent = session.events.last
            end = session.endedAtOffset; rampStart = session.rampStart; rampEnd = session.rampEnd; cooldownStart = session.cooldownStart
            bestStart = session.result?.windowStart; bestEnd = session.result?.windowEnd
            externalPower = session.configuration.resolvedPowerSource == .externalPowerMeter
        }
    }
    public private(set) var data: SummaryChartData
    public private(set) var buildCount = 1
    public private(set) var revision: Revision
    public init(session: TestSession) { revision = Revision(session); data = SummaryChartData(session: session) }
    @discardableResult public func update(session: TestSession) -> Bool {
        let next = Revision(session)
        guard next != revision else { return false }
        revision = next; data = SummaryChartData(session: session); buildCount += 1
        return true
    }
}
