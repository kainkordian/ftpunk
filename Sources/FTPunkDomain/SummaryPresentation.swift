import Foundation

public struct StepRideAverage: Equatable, Sendable {
    public let name: String
    public let seconds: Double
    public let target: String
    public let power: Double?
    public let heartRate: Double?
}
public enum StepRideAverages {
    /// Values ridden in each step on the training clock. Paused samples are excluded;
    /// skips preserve the elapsed portion rather than manufacturing unrecorded samples.
    public static func make(session: TestSession) -> [StepRideAverage] {
        guard let plan = session.training, let clock = WorkoutClock(session) else { return [] }
        var start = 0.0
        return plan.steps.map { step in
            defer { start += step.seconds }
            let values = session.samples.filter { sample in
                guard let time = clock.trainingTime(at: sample.time) else { return false }
                return time >= start && time < start + step.seconds
            }
            func mean(_ numbers: [Double]) -> Double? {
                let valid = numbers.filter(\.isFinite)
                return valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
            }
            return StepRideAverage(name: step.name, seconds: step.seconds,
                                   target: "\(step.watts)" + (step.endWatts.map { " → \($0)" } ?? "") + " W",
                                   power: RideSummary.Series(values) { $0.power }.average(), heartRate: mean(values.compactMap(\.heartRate).filter { $0 > 0 }.map(Double.init)))
        }
    }
}

public struct FTPTrendReading: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let watts: Double
    public let source: String
}
public enum FTPTrendReadings {
    /// Ramp results already have filled markers. Manual/synced settings use hollow markers.
    public static func settings(profile: RiderProfile) -> [FTPTrendReading] {
        profile.ftpHistory.filter { $0.source != "Ramp test" }.sorted { $0.date < $1.date }.map {
            FTPTrendReading(id: $0.id, date: $0.date, watts: $0.watts, source: $0.source)
        }
    }

}

public enum RideChartDomain {
    public static func end(session: TestSession) -> Double { max(1, session.endedAtOffset ?? session.samples.last?.time ?? 0) }
}

public struct FTPTrendPoint: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case ramp, debug, setting }
    public let id: UUID
    public let date: Date
    public let value: Double
    public let source: String
    public let kind: Kind
}
public extension FTPTrendReadings {
    static func series(profile: RiderProfile, sessions: [TestSession], metric: TrendMetric, includeDebug: Bool) -> [FTPTrendPoint] {
        var values = sessions.filter { $0.riderID == profile.id && (includeDebug || !$0.isDemo) }.compactMap { session -> FTPTrendPoint? in
            guard let amount = metric.value(session) else { return nil }
            return FTPTrendPoint(id: session.id, date: session.startedAt, value: amount, source: session.isDemo ? "Debug ramp" : "Ramp test", kind: session.isDemo ? .debug : .ramp)
        }
        values += settings(profile: profile).compactMap { reading -> FTPTrendPoint? in
            let amount: Double
            if metric == .watts { amount = reading.watts }
            else { guard let weight = profile.weightKG, weight.isFinite, weight > 0 else { return nil }; amount = reading.watts / weight }
            return FTPTrendPoint(id: reading.id, date: reading.date, value: amount, source: reading.source, kind: .setting)
        }
        return values.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    }
}
