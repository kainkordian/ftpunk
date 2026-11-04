import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

private let rider = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
private func pct(_ value: Double) -> CustomWorkout.Target { .percentFTP(value) }
private func step(_ name: String = "", _ seconds: Double, _ start: CustomWorkout.Target, to end: CustomWorkout.Target? = nil) -> CustomWorkout.Step {
    .init(name: name, seconds: seconds, start: start, end: end)
}
private func workout(_ name: String = "Test", _ blocks: [CustomWorkout.Block]) -> CustomWorkout {
    CustomWorkout(id: UUID(), riderID: rider, name: name, blocks: blocks, updatedAt: Date(timeIntervalSince1970: 1_793_700_000))
}

// MARK: CustomWorkout

@Test func repeatsFlattenAndPlansResolvePercentOnceAndNeverRescaleWatts() throws {
    let w = workout("Mixed", [.step(step("Warm-up", 300, pct(0.5))),
                              .repeats(count: 2, steps: [step("Hard", 60, pct(1.2)), step("Easy", 60, .watts(100))]),
                              .step(step("", 120, .watts(100), to: .watts(250)))])
    #expect(w.flattened.count == 6 && w.duration == 300 + 240 + 120)
    #expect(w.needsFTP)
    let plan = try w.plan(ftp: 250)
    #expect(plan.name == "Mixed" && plan.ftpWatts == 250 && plan.kind == .workout)
    #expect(plan.steps.map(\.watts) == [125, 300, 100, 300, 100, 100])
    #expect(plan.steps.last?.endWatts == 250 && plan.version == 2)                  // a ramp becomes watts/endWatts
    #expect(plan.steps.map(\.name) == ["Warm-up", "Hard", "Easy", "Hard", "Easy", "Step 6"])
    // Watt steps never rescale with another FTP; percent steps do.
    #expect(try w.plan(ftp: 300).steps.map(\.watts) == [150, 360, 100, 360, 100, 100])
    #expect(throws: CustomWorkout.BuildError.needsFTP) { try w.plan(ftp: nil) }
    #expect(throws: CustomWorkout.BuildError.needsFTP) { try w.plan(ftp: 0) }
    // Watts only: no FTP needed.
    let wattsOnly = workout("Watts", [.step(step("a", 60, .watts(200)))])
    let unscaled = try wattsOnly.plan(ftp: nil)
    #expect(!wattsOnly.needsFTP && unscaled.steps[0].watts == 200 && unscaled.ftpWatts == nil)
}

@Test func validationEnforcesUnitsRangesAndLimits() {
    func problems(_ blocks: [CustomWorkout.Block], name: String = "Test") -> [String] { workout(name, blocks).issues() }
    #expect(problems([.step(step("", 60, pct(0.5)))]).isEmpty)
    #expect(problems([.step(step("", 60, .watts(150), to: pct(0.8)))]).contains { $0.contains("one unit") })        // no ramp from 150 W to 80 %
    #expect(problems([]).contains("Add at least one step."))
    #expect(problems([.step(step("", 60, pct(0.5)))], name: "  ").contains("Give the workout a name."))
    #expect(!problems([.step(step("", 4, pct(0.5)))]).isEmpty && !problems([.step(step("", 14401, pct(0.5)))]).isEmpty)
    #expect(problems([.step(step("", 5, pct(0.5))), .step(step("", 14400, pct(0.5)))]).isEmpty)
    #expect(!problems([.step(step("", 60, pct(0.29)))]).isEmpty && !problems([.step(step("", 60, pct(2.51)))]).isEmpty)
    #expect(problems([.step(step("", 60, pct(0.3))), .step(step("", 60, pct(2.5)))]).isEmpty)
    #expect(!problems([.step(step("", 60, .watts(19)))]).isEmpty && !problems([.step(step("", 60, .watts(1501)))]).isEmpty)
    #expect(!problems([.repeats(count: 101, steps: [step("", 60, pct(0.5))])]).isEmpty && !problems([.repeats(count: 0, steps: [step("", 60, pct(0.5))])]).isEmpty)
    #expect(!problems([.repeats(count: 2, steps: [])]).isEmpty)
    // 500 expanded steps are the limit; 24 hours of riding too.
    #expect(problems([.repeats(count: 100, steps: Array(repeating: step("", 5, pct(0.5)), count: 5))]).isEmpty)
    #expect(!problems([.repeats(count: 100, steps: Array(repeating: step("", 5, pct(0.5)), count: 5)), .step(step("", 5, pct(0.5)))]).isEmpty)
    #expect(!problems(Array(repeating: .repeats(count: 100, steps: [step("", 14400, pct(0.5))]), count: 1)).isEmpty)
    // A name has to survive the text editor.
    #expect(!problems([.step(step("5m rest", 60, pct(0.5)))]).isEmpty && !problems([.step(step("Set 5x", 60, pct(0.5)))]).isEmpty)
    #expect(!problems([.step(step("two  spaces", 60, pct(0.5)))]).isEmpty && !problems([.step(step("with\nline", 60, pct(0.5)))]).isEmpty)
    #expect(problems([.step(step("Time at threshold", 60, pct(0.5)))]).isEmpty)
}

@Test func customWorkoutsRoundTripThroughJSON() throws {
    let w = workout("Round trip", [.step(step("a", 60, pct(0.5), to: pct(0.9))), .repeats(count: 3, steps: [step("", 30, .watts(300))])])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(w)
    #expect(try decoder.decode(CustomWorkout.self, from: data) == w)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"kind\":\"repeats\"") && text.contains("\"unit\":\"percentFTP\"") && text.contains("\"unit\":\"watts\""))
}

@Test func durationsParseFromFieldsAndPrintBack() {
    #expect(CustomWorkout.parseDuration("3:30") == 210 && CustomWorkout.parseDuration("1:00:00") == 3600 && CustomWorkout.parseDuration("5") == 300)
    #expect(CustomWorkout.parseDuration("90s") == 90 && CustomWorkout.parseDuration("1m30") == 90 && CustomWorkout.parseDuration("1h") == 3600)
    #expect(CustomWorkout.parseDuration("1:75") == nil && CustomWorkout.parseDuration("abc") == nil && CustomWorkout.parseDuration("-3") == nil)
    #expect(CustomWorkout.durationText(210) == "3:30" && CustomWorkout.durationText(3725) == "1:02:05")
}

@Test func theEstimatedLoadFollowsTheFourthPowerMean() throws {
    let steady = workout("S", [.step(step("", 3600, pct(0.75)))])
    let load = try #require(steady.estimatedLoad(ftp: 250))
    #expect(abs(load.intensityFactor - 0.75) < 0.001 && abs(load.tss - 56.25) < 0.1)
    let hard = workout("H", [.step(step("", 1800, pct(0.5))), .step(step("", 1800, pct(1.0)))])
    #expect((hard.estimatedLoad(ftp: 250)?.intensityFactor ?? 0) > 0.75) // variability counts for more than the average
    #expect(steady.estimatedLoad(ftp: nil) == nil)
}

// MARK: Text

private func parse(_ text: String) -> WorkoutText.Result { WorkoutText.parse(text) }

@Test func everySyntaxFormParses() throws {
    let text = """
    Warm-up
    - 10m 50%
    Main set 5x
    - 3m 115%
    - Recovery 1m30 55%
    Ramp down
    - 5m ramp 60-40%
    Sprint
    - 20s 650w
    - 1h 200W
    - 2m30s ramp 100-200w
    """
    let result = parse(text)
    #expect(result.errors.isEmpty, "\(result.errors)")
    #expect(result.blocks == [
        .step(step("Warm-up", 600, pct(0.5))),
        .repeats(count: 5, steps: [step("", 180, pct(1.15)), step("Recovery", 90, pct(0.55))]),
        .step(step("Ramp down", 300, pct(0.6), to: pct(0.4))),
        .step(step("Sprint", 20, .watts(650))),
        .step(step("", 3600, .watts(200))),
        .step(step("", 150, .watts(100), to: .watts(200)))
    ])
}

@Test func aPastedIntervalsWorkoutImports() throws {
    let result = parse("""
    Warmup
    - 20m 60%

    Main set 6x
    - 4m 100%
    - 5m recovery at 40%

    Cooldown
    - 20m 60%
    """)
    #expect(result.errors.isEmpty, "\(result.errors)")
    #expect(result.blocks == [
        .step(step("Warmup", 1200, pct(0.6))),
        .repeats(count: 6, steps: [step("", 240, pct(1.0)), step("recovery", 300, pct(0.4))]),
        .step(step("Cooldown", 1200, pct(0.6)))
    ])
    // "Main set 1/6"-style labels are Intervals' own and are not read back; the group label is not kept.
    #expect(parse("Main set 3x\n- 1m 100%\n").blocks == [.repeats(count: 3, steps: [step("", 60, pct(1.0))])])
    // "@" and "at" before a target are filler; CRLF line endings are fine.
    #expect(parse("- 5m @ 80%\r\n- Time at threshold 10m 95%\r\n").blocks == [.step(step("", 300, pct(0.8))), .step(step("Time at threshold", 600, pct(0.95)))])
}

@Test func everyUnsupportedTokenIsAnErrorThatNamesTheLine() {
    let cases: [(String, String)] = [
        ("- 10m 50% 90rpm", "rpm"), ("- 20m 60% 90-100rpm", "rpm"), ("- 5m 55% HR", "HR"), ("- 5m 100% LTHR", "LTHR"), ("- 60m Z2", "Z2"),
        ("- 10m Z2-Z3", "Z2-Z3"), ("- 5m 70% pace", "pace"), ("- 1km 80%", "1km"), ("- 800mtr 80%", "800mtr"), ("- 20m freeride", "freeride"),
        ("- Press lap 10m 50%", "Press"), ("- 10m 50% ftp", "ftp")
    ]
    for (line, token) in cases {
        let result = parse("Warm-up\n- 10m 50%\n\n" + line)
        #expect(result.errors.count == 1 && result.errors.first?.line == 4, "\(line): \(result.errors)")
        #expect(result.errors.first?.message.contains(token) == true && result.blocks.isEmpty, "\(line): \(result.errors)")
        #expect(result.errors.first?.errorDescription?.hasPrefix("Line 4:") == true)
    }
    #expect(parse("- 10m 80-90%").errors.first?.message.contains("Ranges are not supported") == true)
    #expect(parse("- 10m ramp 60%").errors.first?.message.contains("ramp") == true)
    #expect(parse("- 10m ramp").errors.first?.message.contains("ramp") == true)
    #expect(parse("- 10m").errors.first?.message.contains("target") == true)
    #expect(parse("- 80%").errors.first?.message.contains("duration") == true)
    #expect(parse("- 5m 10m 80%").errors.first?.message == "A step has one duration.")
    #expect(parse("- 5m 80% 90%").errors.first?.message == "A step has one target.")
    #expect(parse("- 3s 80%").errors.first?.message.contains("between 5 seconds and 4 hours") == true)
    #expect(parse("- 5m 20%").errors.first?.message.contains("30 and 250") == true && parse("- 5m 10w").errors.first?.message.contains("20 and 1500") == true)
    #expect(parse("Main set 101x\n- 1m 50%").errors.first?.message.contains("1 to 100") == true)
    #expect(parse("Main set 3x\n\n- 1m 50%").errors.first?.line == 1)   // a repeat with nothing under it before the blank line
    #expect(parse("").errors.first?.line == 1 && parse("   \n\n").errors.count == 1)
    // Every bad line is reported, not just the first.
    #expect(parse("- 10m 50% rpm\n- 5m\n- 1m 60%").errors.map(\.line) == [1, 2])
}

@Test func printedTextParsesBackToEqualBlocksForAGeneratedSet() {
    var generator = SeededGenerator(seed: 42)
    let names = ["", "", "Warm-up", "Hard", "Easy", "Sweet spot", "Time at threshold", "Spin-up", "Recovery", "Over", "Under"]
    func target(_ unitPercent: Bool) -> CustomWorkout.Target {
        unitPercent ? .percentFTP((Double(Int.random(in: 300...2500, using: &generator)) / 10).rounded() / 100 * 1)
                    : .watts(Double(Int.random(in: 20...1500, using: &generator)))
    }
    func makeStep() -> CustomWorkout.Step {
        let percent = Bool.random(using: &generator)
        let first = target(percent)
        // A percent made the way the parser makes it: printed number / 100.
        func canonical(_ t: CustomWorkout.Target) -> CustomWorkout.Target {
            guard t.isPercent else { return t }
            let printed = Double(String(format: "%.1f", t.number * 100)) ?? 50
            return .percentFTP(printed / 100)
        }
        let ramp = Int.random(in: 0..<4, using: &generator) == 0
        return .init(name: names.randomElement(using: &generator) ?? "", seconds: Double(Int.random(in: 5...14400, using: &generator)),
                     start: canonical(first), end: ramp ? canonical(target(percent)) : nil)
    }
    for _ in 0..<300 {
        var blocks: [CustomWorkout.Block] = []
        for _ in 0..<Int.random(in: 1...6, using: &generator) {
            if Int.random(in: 0..<3, using: &generator) == 0 {
                blocks.append(.repeats(count: Int.random(in: 1...100, using: &generator), steps: (0..<Int.random(in: 1...4, using: &generator)).map { _ in makeStep() }))
            } else { blocks.append(.step(makeStep())) }
        }
        let text = WorkoutText.print(blocks)
        let result = WorkoutText.parse(text)
        #expect(result.errors.isEmpty, "\(text) -> \(result.errors)")
        #expect(result.blocks == blocks, "\(text)")
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Test func theBuiltInCatalogSurvivesBlocksAndTextRoundTrips() throws {
    for definition in WorkoutLibrary.catalog {
        for ftp in [180.0, 250, 333] {
            let expected = try definition.plan(ftp: ftp)
            let custom = try #require(CustomWorkout(definition: definition, riderID: rider), "\(definition.id)")
            #expect(try custom.plan(ftp: ftp) == expected, "\(definition.id) as blocks")
            let result = WorkoutText.parse(WorkoutText.print(custom.blocks))
            #expect(result.errors.isEmpty, "\(definition.id) text: \(result.errors)")
            #expect(result.blocks == custom.blocks, "\(definition.id) text blocks")
            var viaText = custom; viaText.blocks = result.blocks
            #expect(try viaText.plan(ftp: ftp) == expected, "\(definition.id) as text")
        }
    }
}

@Test func anImportedPlanBecomesWattBlocksThatRebuildTheSamePlan() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Imported", ftpWatts: 250, steps: [.init("Warm-up", seconds: 300, watts: 100, endWatts: 150), .init("Hard", seconds: 600, watts: 260)])
    let custom = try #require(CustomWorkout(plan: plan, riderID: rider))
    #expect(!custom.needsFTP)
    let rebuilt = try custom.plan(ftp: 250)
    #expect(rebuilt.steps == plan.steps && rebuilt.name == plan.name)
    // A one-second step is outside the builder's limits, so such a workout cannot be duplicated into it.
    let tiny = try TrainingPlan(kind: .workout, name: "Tiny", steps: [.init("blip", seconds: 1, watts: 200)])
    #expect(CustomWorkout(plan: tiny, riderID: rider) == nil)
}

// MARK: BuilderState

@Test func switchingModesNeverLosesAnythingAndTextErrorsKeepTextMode() {
    var state = BuilderState(workout: workout("W", [.step(step("Warm-up", 300, pct(0.5))), .repeats(count: 2, steps: [step("", 60, pct(1.1)), step("", 60, pct(0.5))])]))
    #expect(state.mode == .blocks)
    let original = state.blocks
    #expect(state.switchTo(.text) && state.mode == .text && state.parsed.isValid)
    #expect(state.text == WorkoutText.print(original))
    // Break the text: switching back is refused, the text stays, and the notice says which line to fix.
    state.setText(state.text + "\n\n- 5m 90rpm")
    #expect(!state.parsed.isValid && state.chartIsStale && state.shownBlocks == original)
    #expect(!state.switchTo(.blocks) && state.mode == .text)
    #expect(state.notice?.hasPrefix("Fix line 8 first:") == true && state.text.hasSuffix("90rpm"))
    #expect(!state.canSave && state.saveBlockers.first?.hasPrefix("Line 8:") == true && state.hasUnsavedChanges)
    // Fix it: the new text is what comes back to Blocks.
    state.setText("Warm-up\n- 5m 50%\n\n- 2m 80%")
    #expect(state.parsed.isValid && !state.chartIsStale && state.canSave)
    #expect(state.switchTo(.blocks) && state.mode == .blocks && state.notice == nil)
    #expect(state.blocks == [.step(step("Warm-up", 300, pct(0.5))), .step(step("", 120, pct(0.8)))])
    // Blocks edits are ignored in Text mode and the other way round.
    state.switchTo(.text); state.setBlocks([]); #expect(!state.blocks.isEmpty)
    state.switchTo(.blocks); state.setText("garbage"); #expect(state.text != "garbage")
}

@Test func theBuilderReportsWhatBlocksSaveAndTracksChanges() {
    let blank = workout("", [])
    var state = BuilderState(workout: blank)
    #expect(!state.canSave && state.saveBlockers.contains("Give the workout a name.") && state.saveBlockers.contains("Add at least one step.") && !state.hasUnsavedChanges)
    state.name = "Mine"; state.setBlocks([.step(step("", 600, pct(0.5)))])
    #expect(state.canSave && state.hasUnsavedChanges && state.workout().name == "Mine" && state.workout().id == blank.id)
    state.setBlocks([.step(step("", 600, .watts(150), to: pct(0.8)))])
    #expect(!state.canSave)
}

// MARK: Storage, archive, library

@Test @MainActor func customWorkoutsAreStoredPerRiderAndLeaveTheImportedLibraryAlone() throws {
    let store = try LocalStore(inMemory: true)
    let a = RiderProfile(id: UUID(), name: "A"), b = RiderProfile(id: UUID(), name: "B")
    try store.saveProfile(a); try store.saveProfile(b)
    var mine = CustomWorkout(riderID: a.id, name: "Mine", blocks: [.step(step("", 600, pct(0.5)))])
    try store.saveCustomWorkout(mine)
    try store.saveCustomWorkout(CustomWorkout(riderID: b.id, name: "Theirs", blocks: [.step(step("", 300, .watts(200)))]))
    try store.saveWorkouts([CachedWorkout(riderID: a.id, source: "Imported JSON", plan: try TrainingPlan(kind: .workout, name: "Imported", steps: [.init("a", seconds: 60, watts: 100)]))])
    let kinds = (try store.customWorkouts().count, try store.workouts().count)
    #expect(kinds == (2, 1))       // the two kinds never mix
    mine.name = "Renamed"; mine.blocks.append(.step(step("", 60, pct(0.6)))); mine.updatedAt = Date()
    try store.saveCustomWorkout(mine)
    #expect(try store.customWorkouts().filter { $0.riderID == a.id }.map(\.name) == ["Renamed"])
    #expect(try store.customWorkouts().first { $0.id == mine.id }?.blocks.count == 2)
    try store.deleteCustomWorkout(id: mine.id)
    #expect(try store.customWorkouts().map(\.name) == ["Theirs"])
    #expect(try store.workouts().count == 1)
    // A workout cannot move to another rider, and invalid ones are refused.
    var stolen = try #require(store.customWorkouts().first); stolen.riderID = a.id
    #expect(throws: ArchiveError.self) { try store.saveCustomWorkout(stolen) }
    #expect(throws: CustomWorkout.BuildError.self) { try store.saveCustomWorkout(CustomWorkout(riderID: a.id, name: "", blocks: [])) }
}

@Test @MainActor func aRiderCanKeepTwoHundredWorkouts() throws {
    let store = try LocalStore(inMemory: true)
    for index in 0..<CustomWorkout.maximumPerRider { try store.saveCustomWorkout(CustomWorkout(riderID: rider, name: "W\(index)", blocks: [.step(step("", 60, pct(0.5)))])) }
    #expect(throws: ArchiveError.self) { try store.saveCustomWorkout(CustomWorkout(riderID: rider, name: "One too many", blocks: [.step(step("", 60, pct(0.5)))])) }
    #expect(try store.customWorkouts().count == CustomWorkout.maximumPerRider)
}

@Test @MainActor func customWorkoutsTravelInBackupsAndOldArchivesStillLoad() throws {
    let store = try LocalStore(inMemory: true)
    let a = RiderProfile(id: UUID(), name: "A")
    try store.saveProfile(a)
    let custom = CustomWorkout(riderID: a.id, name: "Backed up", category: .tempo, blocks: [.repeats(count: 3, steps: [step("x", 60, pct(1.0), to: pct(1.1))])], updatedAt: Date(timeIntervalSince1970: 1_793_700_000))
    try store.saveCustomWorkout(custom)
    let archive = try store.portableArchive()
    #expect(archive.version == 3 && archive.customWorkouts?.count == 1)
    let decoded = try PortableArchive.decode(archive.encoded())
    #expect(decoded.customWorkouts == [custom])
    // Restoring into an empty store brings them back; restoring again changes nothing.
    let other = try LocalStore(inMemory: true)
    try other.restore(decoded); try other.restore(decoded)
    #expect(try other.customWorkouts() == [custom])
    // Without the key (an archive from before) the field is absent and everything else loads.
    var object = try #require(JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any])
    object.removeValue(forKey: "customWorkouts")
    let old = try PortableArchive.decode(JSONSerialization.data(withJSONObject: object))
    #expect(old.customWorkouts == nil && old.profiles.count == 1)
    // A custom workout of a rider who is not in the archive, or in a version-2 archive, is refused.
    var orphan = decoded; orphan.customWorkouts = [CustomWorkout(riderID: UUID(), name: "Orphan", blocks: [.step(step("", 60, pct(0.5)))])]
    #expect(throws: ArchiveError.self) { try orphan.validate() }
    object["version"] = 2; object["customWorkouts"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([custom]))
    #expect(throws: (any Error).self) { try PortableArchive.decode(JSONSerialization.data(withJSONObject: object)) }
}

@Test @MainActor func theLibraryOffersCustomWorkoutsLikeAnyOther() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)   // FTP 250 in the preview
    try model.store.saveProfile(model.profile)
    let w = CustomWorkout(riderID: model.profile.id, name: "Mine", blocks: [.step(step("Go", 600, pct(0.8)))])
    #expect(model.saveCustomWorkout(w) && model.myCustomWorkouts.map(\.name) == ["Mine"])
    let detail = try #require(model.workoutDetail(for: .custom(w.id)))
    #expect(detail.source == "My workout" && detail.plan?.steps.first?.watts == 200 && !detail.needsFTP && detail.custom?.id == w.id)
    // Starting snapshots the plan; later edits never change the recording.
    #expect(model.duplicate(.custom(w.id))?.name == "Copy of Mine" && model.duplicate(.classic("endurance-60")) != nil)
    // Without an FTP a % workout says so and cannot start.
    model.manualFTP = ""; model.ftpSelection = "none"
    let blocked = try #require(model.workoutDetail(for: .custom(w.id)))
    #expect(blocked.needsFTP && blocked.plan == nil && blocked.previewPlan != nil)
    model.deleteCustomWorkout(w)
    #expect(model.workoutDetail(for: .custom(w.id)) == nil)
}
