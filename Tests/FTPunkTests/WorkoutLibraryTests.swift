import Foundation
import Testing
import FTPunkDomain

@Test func libraryHasFourteenClassicsInSixCategories() throws {
    #expect(WorkoutLibrary.catalog.count == 14)
    #expect(Set(WorkoutLibrary.catalog.map(\.id)).count == 14)
    #expect(Set(WorkoutLibrary.catalog.map(\.category)) == Set(WorkoutCategory.allCases))
    #expect(WorkoutLibrary.definitions(in: .endurance).count == 3 && WorkoutLibrary.definitions(in: .tempo).count == 3)
    #expect(WorkoutLibrary.definitions(in: .sweetSpot).count == 2 && WorkoutLibrary.definitions(in: .vo2max).count == 2)
    #expect(try WorkoutLibrary.classics(ftp: 250).allSatisfy { (try? $0.plan.validate()) != nil })
}

@Test func theThreeOriginalStartersKeepTheirExactSteps() throws {
    let starters = try TrainingPlan.starters(ftp: 217)
    let classics = try WorkoutLibrary.classics(ftp: 217)
    for (starter, id) in zip(starters, ["easy-spin", "endurance-30", "tempo-3x5"]) {
        let classic = try #require(classics.first { $0.id == id })
        #expect(classic.plan.steps == starter.steps)
        #expect(classic.plan.duration == starter.duration)
        #expect(classic.plan.version == 1) // no ramps, so the older plan shape
    }
}

@Test func newWorkoutsUseFlatWarmupAndCooldown() throws {
    let plan = try #require(WorkoutLibrary.definition(id: "sweet-spot-3x10")).plan(ftp: 250)
    #expect(plan.steps.first == .init("Warm-up", seconds: 600, watts: 125))
    #expect(plan.steps.last == .init("Cool-down", seconds: 300, watts: 125))
    #expect(plan.steps[1] == .init("Sweet spot 1 of 3", seconds: 600, watts: 225))
    #expect(plan.steps[2] == .init("Recovery", seconds: 300, watts: 125)) // recoveries at 50 %
    #expect(plan.steps.count == 7) // warm-up, 3 efforts, 2 recoveries between, cool-down
    #expect(plan.duration == 3300 && plan.version == 1)
    #expect(plan.ftpWatts == 250)
}

@Test func overUndersAlternateWithinEachSet() throws {
    let plan = try #require(WorkoutLibrary.definition(id: "over-unders-3x9")).plan(ftp: 300)
    let main = plan.steps.dropFirst().dropLast()
    #expect(main.count == 18 + 2)
    #expect(plan.steps[1].watts == 285 && plan.steps[1].seconds == 120) // 95 % for 2 min
    #expect(plan.steps[2].watts == 315 && plan.steps[2].seconds == 60) // 105 % for 1 min
    #expect(plan.steps[7].name == "Recovery" && plan.steps[7].seconds == 300)
    let fast = try #require(WorkoutLibrary.definition(id: "over-unders-4x6")).plan(ftp: 300)
    #expect(fast.steps[1].watts == 270 && fast.steps[2].watts == 330 && fast.steps[1].seconds == 60)
    #expect(fast.steps.filter { $0.name == "Recovery" }.count == 3 && fast.steps.filter { $0.name == "Recovery" }.allSatisfy { $0.seconds == 240 })
}

@Test func catalogDurationsAndTargetsMatchThePlanTable() throws {
    let minutes: [String: Double] = ["endurance-60": 60, "tempo-3x10": 10 + 30 + 6 + 5, "tempo-2x20": 10 + 40 + 5 + 5,
        "sweet-spot-2x20": 10 + 40 + 5 + 5, "threshold-2x20": 10 + 40 + 5 + 5, "threshold-3x12": 10 + 36 + 12 + 5,
        "vo2max-5x3": 10 + 15 + 12 + 5, "vo2max-4x4": 10 + 16 + 12 + 5, "over-unders-3x9": 10 + 27 + 10 + 5, "over-unders-4x6": 10 + 24 + 12 + 5]
    for (id, expected) in minutes { #expect(WorkoutLibrary.definition(id: id)?.duration == expected * 60, "\(id)") }
    let vo2 = try #require(WorkoutLibrary.definition(id: "vo2max-5x3")).plan(ftp: 250)
    #expect(vo2.steps[1].watts == 288) // 115 % of 250 = 287.5, rounded to whole watts
    let endurance = try #require(WorkoutLibrary.definition(id: "endurance-60")).plan(ftp: 200)
    #expect(endurance.steps[1].watts == 136 && endurance.steps[1].seconds == 2700)
}

@Test func definitionsShowDurationWithoutAnFTPAndRejectInvalidOnes() throws {
    let definition = try #require(WorkoutLibrary.definition(id: "tempo-3x10"))
    #expect(definition.duration > 0)
    #expect(throws: (any Error).self) { try definition.plan(ftp: 0) }
    #expect(throws: (any Error).self) { try definition.plan(ftp: .infinity) }
    #expect(WorkoutLibrary.definition(id: "nonexistent") == nil)
}

@Test func retargetExampleMatchesThePlansSweetSpotExample() {
    let example = RetargetExample.make(oldFTP: 250, newFTP: 209)
    #expect(example?.text == "Sweet spot 3×10: 225 → 188 W")
    #expect(RetargetExample.make(oldFTP: nil, newFTP: 209) == nil)
    #expect(RetargetExample.make(oldFTP: 250, newFTP: 0) == nil)
    #expect(RetargetExample.make(oldFTP: 250, newFTP: 209, workoutID: "nope") == nil)
}

@Test func builtInWorkoutsHaveNoRampsAndWarmUpAtHalfFTP() throws {
    for definition in WorkoutLibrary.catalog {
        #expect(definition.steps.allSatisfy { $0.to == nil }, "\(definition.id) has a ramp")
        let first = try #require(definition.steps.first)
        #expect(first.name.hasPrefix("Warm") && first.from == 0.50, "\(definition.id) warm-up")
        #expect(try definition.plan(ftp: 250).steps.allSatisfy { $0.endWatts == nil })
    }
}
