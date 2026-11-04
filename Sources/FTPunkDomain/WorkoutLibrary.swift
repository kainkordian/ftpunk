import Foundation

public enum WorkoutCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case endurance, tempo, sweetSpot, overUnders, threshold, vo2max
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .endurance: "Endurance"
        case .tempo: "Tempo"
        case .sweetSpot: "Sweet spot"
        case .overUnders: "Over-unders"
        case .threshold: "Threshold"
        case .vo2max: "VO2max"
        }
    }
}

/// A built-in structure, expressed as percentages of FTP. The category belongs to the catalog entry,
/// not to `TrainingPlan`, so recordings and archives never change schema.
public struct WorkoutDefinition: Identifiable, Sendable {
    public struct Step: Sendable {
        public let name: String
        public let minutes: Double
        public let from: Double
        public let to: Double?
        init(_ name: String, _ minutes: Double, _ from: Double, to: Double? = nil) {
            self.name = name; self.minutes = minutes; self.from = from; self.to = to
        }
    }
    public let id: String
    public let name: String
    public let category: WorkoutCategory
    public let steps: [Step]
    /// Duration does not depend on FTP, so cards can show it before the rider has one.
    public var duration: Double { steps.reduce(0) { $0 + $1.minutes * 60 } }

    /// Whole-watt targets at the rider's FTP. Resolved again each time the workout is shown and
    /// snapshotted when a ride starts.
    public func plan(ftp: Double) throws -> TrainingPlan {
        guard ftp.isFinite, ftp > 0, ftp <= 32767 else { throw ArchiveError.invalid("Set your FTP before choosing a workout.") }
        func watts(_ fraction: Double) -> Int { max(1, Int((ftp * fraction).rounded())) }
        return try TrainingPlan(kind: .workout, name: name, ftpWatts: ftp, steps: steps.map {
            .init($0.name, seconds: $0.minutes * 60, watts: watts($0.from), endWatts: $0.to.map(watts))
        })
    }
}

public struct ClassicWorkout: Identifiable, Sendable {
    public let definition: WorkoutDefinition
    public let plan: TrainingPlan
    public var id: String { definition.id }
    public var category: WorkoutCategory { definition.category }
}

/// Offline catalog of classic workouts (UX plan §5). Every step is constant power: a warm-up at
/// 50 % (10 min, or 3-5 min in the three original starters), a 5 min cool-down at 50 % and recoveries at 50 %.
/// Imported and Intervals.icu workouts can still contain ramps; the catalog does not.
public enum WorkoutLibrary {
    public static let catalog: [WorkoutDefinition] = endurance + tempo + sweetSpot + overUnders + threshold + vo2max

    public static func classics(ftp: Double) throws -> [ClassicWorkout] {
        try catalog.map { ClassicWorkout(definition: $0, plan: try $0.plan(ftp: ftp)) }
    }
    public static func definition(id: String) -> WorkoutDefinition? { catalog.first { $0.id == id } }
    public static func definitions(in category: WorkoutCategory) -> [WorkoutDefinition] { catalog.filter { $0.category == category } }

    typealias Step = WorkoutDefinition.Step
    private static let warmup = Step("Warm-up", 10, 0.50)
    private static let cooldown = Step("Cool-down", 5, 0.50)
    private static func recovery(_ minutes: Double) -> Step { Step("Recovery", minutes, 0.50) }

    /// `count` efforts with recoveries between them (none after the last).
    private static func repeats(_ label: String, count: Int, minutes: Double, at fraction: Double, recovery minutes2: Double) -> [Step] {
        (1...count).flatMap { index in
            [Step("\(label) \(index) of \(count)", minutes, fraction)] + (index < count ? [recovery(minutes2)] : [])
        }
    }
    private static func definition(_ id: String, _ name: String, _ category: WorkoutCategory, _ steps: [Step]) -> WorkoutDefinition {
        WorkoutDefinition(id: id, name: name, category: category, steps: steps)
    }

    private static let endurance: [WorkoutDefinition] = [
        definition("easy-spin", "Easy spin", .endurance, [Step("Warm-up", 3, 0.50), Step("Easy spin", 14, 0.55), Step("Cooldown", 3, 0.40)]),
        definition("endurance-30", "Endurance 30", .endurance, [Step("Warm-up", 5, 0.50), Step("Endurance", 20, 0.65), Step("Cooldown", 5, 0.40)]),
        definition("endurance-60", "Endurance 60", .endurance, [warmup, Step("Endurance", 45, 0.68), cooldown])
    ]
    private static let tempo: [WorkoutDefinition] = [
        definition("tempo-3x5", "Tempo 3×5", .tempo,
                   [Step("Warm-up", 5, 0.50)] + (1...3).flatMap { [Step("Tempo \($0) of 3", 5, 0.80), Step("Recovery", 2, 0.45)] } + [Step("Cooldown", 4, 0.40)]),
        definition("tempo-3x10", "Tempo 3×10", .tempo, [warmup] + repeats("Tempo", count: 3, minutes: 10, at: 0.83, recovery: 3) + [cooldown]),
        definition("tempo-2x20", "Tempo 2×20", .tempo, [warmup] + repeats("Tempo", count: 2, minutes: 20, at: 0.82, recovery: 5) + [cooldown])
    ]
    private static let sweetSpot: [WorkoutDefinition] = [
        definition("sweet-spot-3x10", "Sweet spot 3×10", .sweetSpot, [warmup] + repeats("Sweet spot", count: 3, minutes: 10, at: 0.90, recovery: 5) + [cooldown]),
        definition("sweet-spot-2x20", "Sweet spot 2×20", .sweetSpot, [warmup] + repeats("Sweet spot", count: 2, minutes: 20, at: 0.90, recovery: 5) + [cooldown])
    ]
    private static func overUnderSets(sets: Int, under: Double, over: Double, underFraction: Double, overFraction: Double, recovery minutes: Double) -> [Step] {
        (1...sets).flatMap { set in
            (1...3).flatMap { rep in
                [Step("Set \(set) · under \(rep)", under, underFraction), Step("Set \(set) · over \(rep)", over, overFraction)]
            } + (set < sets ? [recovery(minutes)] : [])
        }
    }
    private static let overUnders: [WorkoutDefinition] = [
        definition("over-unders-3x9", "Over-unders 3×9", .overUnders,
                   [warmup] + overUnderSets(sets: 3, under: 2, over: 1, underFraction: 0.95, overFraction: 1.05, recovery: 5) + [cooldown]),
        definition("over-unders-4x6", "Over-unders 4×6", .overUnders,
                   [warmup] + overUnderSets(sets: 4, under: 1, over: 1, underFraction: 0.90, overFraction: 1.10, recovery: 4) + [cooldown])
    ]
    private static let threshold: [WorkoutDefinition] = [
        definition("threshold-2x20", "Threshold 2×20", .threshold, [warmup] + repeats("Threshold", count: 2, minutes: 20, at: 0.97, recovery: 5) + [cooldown]),
        definition("threshold-3x12", "Threshold 3×12", .threshold, [warmup] + repeats("Threshold", count: 3, minutes: 12, at: 1.00, recovery: 6) + [cooldown])
    ]
    private static let vo2max: [WorkoutDefinition] = [
        definition("vo2max-5x3", "VO2max 5×3", .vo2max, [warmup] + repeats("VO2max", count: 5, minutes: 3, at: 1.15, recovery: 3) + [cooldown]),
        definition("vo2max-4x4", "VO2max 4×4", .vo2max, [warmup] + repeats("VO2max", count: 4, minutes: 4, at: 1.10, recovery: 4) + [cooldown])
    ]
}

/// "Sweet spot 3×10: 225 → 188 W": how a new FTP changes one library workout's main set.
public struct RetargetExample: Equatable, Sendable {
    public let workoutName: String
    public let oldWatts: Int
    public let newWatts: Int
    public var text: String { "\(workoutName): \(oldWatts) → \(newWatts) W" }

    public static func make(oldFTP: Double?, newFTP: Double, workoutID: String = "sweet-spot-3x10") -> RetargetExample? {
        guard let oldFTP, oldFTP.isFinite, oldFTP > 0, newFTP.isFinite, newFTP > 0,
              let definition = WorkoutLibrary.definition(id: workoutID),
              let old = try? definition.plan(ftp: oldFTP), let new = try? definition.plan(ftp: newFTP) else { return nil }
        // The hardest step is the main set; built-in warm-ups and cool-downs are flat at 50 %.
        // (The ramp filter stays for plans that contain ramps.)
        guard let index = old.steps.indices.filter({ old.steps[$0].endWatts == nil }).max(by: { old.steps[$0].watts < old.steps[$1].watts }) else { return nil }
        return RetargetExample(workoutName: definition.name, oldWatts: old.steps[index].watts, newWatts: new.steps[index].watts)
    }
}
