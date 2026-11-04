import Testing
import FTPunkDomain

private func plan(_ id: String, ftp: Double = 250) throws -> TrainingPlan {
    try #require(WorkoutLibrary.definition(id: id)).plan(ftp: ftp)
}

@Test func previewStepsShowPercentAndWattsForALibraryWorkout() throws {
    let steps = WorkoutPreview.steps(for: try plan("sweet-spot-3x10"))
    #expect(steps.count == 7)
    #expect(steps[0].valueText == "10:00 · 50 % · 125 W")
    #expect(steps[1].valueText == "10:00 · 90 % · 225 W" && steps[1].zone == .sweetSpot)
    #expect(steps[1].start == 600 && steps[2].start == 1200)
}

@Test func previewRampStepsShowArrows() throws {
    let ramp = try TrainingPlan(kind: .workout, name: "Ramp", ftpWatts: 250, steps: [.init("Cool-down", seconds: 300, watts: 150, endWatts: 100)])
    let step = try #require(WorkoutPreview.steps(for: ramp).first)
    #expect(step.valueText == "5:00 · 60→40 % · 150→100 W")
}

@Test func previewWithoutFTPShowsDurationOnly() throws {
    let noFTP = try TrainingPlan(kind: .workout, name: "Fixed", ftpWatts: nil, steps: [.init("Main", seconds: 600, watts: 200)])
    let steps = WorkoutPreview.steps(for: noFTP)
    #expect(steps[0].percent == nil && steps[0].zone == nil && steps[0].valueText == "10:00")
    let hidden = WorkoutPreview.steps(for: try plan("endurance-60"), showValues: false)
    #expect(hidden.allSatisfy { $0.percent == nil && !$0.valueText.contains("W") })
}

@Test func previewIntensityScalesWatts() throws {
    let steps = WorkoutPreview.steps(for: try plan("sweet-spot-3x10"), intensity: 90)
    #expect(steps[1].watts == 203 && steps[1].percent == 81) // 225 W * 0.9 = 202.5 W
    #expect(steps[0].watts == 113)
}

@Test func hitTestingFindsTheStepAtBoundaries() throws {
    let p = try plan("endurance-60") // 10, 45, 5 minutes
    #expect(WorkoutPreview.step(atFraction: 0, in: p) == 0)
    #expect(WorkoutPreview.step(atFraction: 1, in: p) == 2)
    #expect(WorkoutPreview.step(atFraction: 10.0 / 60 - 0.0001, in: p) == 0)
    #expect(WorkoutPreview.step(atFraction: 10.0 / 60, in: p) == 1)
    #expect(WorkoutPreview.step(atFraction: 55.0 / 60 + 0.0001, in: p) == 2)
    #expect(WorkoutPreview.step(atFraction: -0.1, in: p) == nil && WorkoutPreview.step(atFraction: 1.1, in: p) == nil)
    #expect(WorkoutPreview.step(atFraction: .nan, in: p) == nil)
}

@Test func groupsCollapseRepeatBlocks() throws {
    let vo2 = WorkoutPreview.groups(for: try plan("vo2max-5x3"))
    #expect(vo2.count == 3)
    #expect(vo2[1].repeats == 5 && vo2[1].pattern.count == 2 && vo2[1].range == 1..<10)
    #expect(vo2[1].text == "5× VO2max 3:00 @ 115 % (288 W) / Recovery 3:00 @ 50 % (125 W)")
    let endurance = WorkoutPreview.groups(for: try plan("endurance-60"))
    #expect(endurance.count == 3 && endurance.allSatisfy { $0.repeats == 1 && $0.pattern.count == 1 })
}

@Test func everyCatalogWorkoutGroupsCoverAllStepsInOrder() throws {
    for definition in WorkoutLibrary.catalog {
        let p = try definition.plan(ftp: 250)
        var next = 0
        for group in WorkoutPreview.groups(for: p) { #expect(group.range.lowerBound == next); next = group.range.upperBound }
        #expect(next == p.steps.count, "\(definition.id)")
    }
}

@Test func mainSetTextNamesTheHardestRepeatedStep() throws {
    #expect(WorkoutPreview.mainSetText(for: try plan("vo2max-5x3")) == "5 × 3:00 @ 115 % (288 W)")
    #expect(WorkoutPreview.mainSetText(for: try plan("threshold-3x12")) == "3 × 12:00 @ 100 % (250 W)")
}

@Test func aShortSprintDoesNotBecomeTheMainSet() throws {
    // Warm-up, 4 × (3:00 @ 105 % + 2:00 @ 90 %), recovery and one 20 s sprint at 260 %.
    var steps: [TrainingPlan.Step] = [.init("Warm-up", seconds: 600, watts: 125)]
    for _ in 0..<4 { steps += [.init("Over", seconds: 180, watts: 263), .init("Under", seconds: 120, watts: 225)] }
    steps += [.init("Recovery", seconds: 300, watts: 138), .init("Sprint", seconds: 20, watts: 650)]
    let plan = try TrainingPlan(kind: .workout, name: "Over-unders and a sprint", ftpWatts: 250, steps: steps)
    #expect(WorkoutPreview.mainSetText(for: plan) == "4 × 3:00 @ 105 % (263 W)")
}
