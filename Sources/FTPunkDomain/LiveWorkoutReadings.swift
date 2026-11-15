import Foundation

/// Append-only presentation readings. Replays history only when the training clock
/// changes (pause/resume/skip), the recording is replaced, or time moves backwards.
public final class LiveWorkoutReadings {
    public private(set) var heartRate: [(time: Double, bpm: Int)] = []
    public private(set) var stepHeartRates: [Double?] = []
    public private(set) var samplesVisited = 0
    public private(set) var recentPowerCount = 0
    private var id: UUID?
    private var events: [SessionEvent] = []
    private var plan: TrainingPlan?
    private var clock: WorkoutClock?
    private var cursor = 0
    private var lastSample: RideSample?
    private var lastTime = -Double.infinity
    private var recentPower: [RideSample] = []
    private var pauses: [RidePause] = []
    private var ends: [Double] = [], sums: [Double] = [], counts: [Int] = []

    public init() {}
    public func update(session: TestSession, at time: Double) {
        guard time.isFinite else { return }
        let replacedLast = cursor == session.samples.count && lastSample != session.samples.last
        if id != session.id || events != session.events || plan != session.training || cursor > session.samples.count || time < lastTime || replacedLast {
            id = session.id; events = session.events; plan = session.training; clock = WorkoutClock(session)
            pauses = RidePause.list(session); cursor = 0; heartRate = []; recentPower = []
            var end = 0.0
            ends = (plan?.steps ?? []).map { end += $0.seconds; return end }
            sums = Array(repeating: 0, count: ends.count); counts = Array(repeating: 0, count: ends.count)
        }
        let cutoff = time - Double(LivePower.windows.max() ?? 60) - 2
        for sample in session.samples.dropFirst(cursor) {
            samplesVisited += 1
            if sample.power?.isFinite == true && sample.time >= cutoff { recentPower.append(sample) }
            guard let bpm = sample.heartRate, bpm > 0, let trainingTime = clock?.trainingTime(at: sample.time) else { continue }
            if heartRate.last.map({ trainingTime >= $0.time && trainingTime - $0.time < 1 }) != true {
                heartRate.append((trainingTime, bpm))
            }
            // Find the step without scanning the recording for every step.
            var lo = 0, hi = ends.count
            while lo < hi { let mid = (lo + hi) / 2; if ends[mid] <= trainingTime { lo = mid + 1 } else { hi = mid } }
            if lo < ends.count { sums[lo] += Double(bpm); counts[lo] += 1 }
        }
        cursor = session.samples.count; lastSample = session.samples.last; lastTime = time
        recentPower.removeAll { $0.time < cutoff }; recentPowerCount = recentPower.count
        let endTime = session.endedAtOffset ?? session.samples.last?.time ?? 0
        let end = clock?.trainingTime(at: endTime) ?? events.last(where: { $0.time <= endTime && $0.message == "Training paused; trainer release requested" }).flatMap { clock?.trainingTime(at: max(0, $0.time - 0.000001)).map { $0 + 0.000001 } } ?? 0
        stepHeartRates = clock == nil ? [] : ends.indices.map { ends[$0] <= end && counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }
    public func power(at time: Double, window: Int) -> Double? {
        LivePower.average(samples: recentPower, at: time, window: window, pauses: pauses)
    }
}
