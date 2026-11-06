import Foundation
import Testing
@testable import FTPunkDomain
import FTPunkStorage

// Golden fixtures for the web app's "My workouts" port (ZWO, workout text, custom workouts, portable v3 with custom workouts).
// Swift writes them with FTPUNK_WRITE_FIXTURES=1 and otherwise compares; the web copies them byte for byte into ftpunk_web/tests/fixtures/.
// Regenerate: FTPUNK_WRITE_FIXTURES=1 swift test --filter WebWorkoutFixtures

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let writing = ProcessInfo.processInfo.environment["FTPUNK_WRITE_FIXTURES"] == "1"

private func isoText(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
/// Any Codable value as a JSON object, dates as the archive writes them.
private func object<T: Encodable>(_ value: T) throws -> Any {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in var container = encoder.singleValueContainer(); try container.encode(isoText(date)) }
    return try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
}
private func planJSON(_ plan: TrainingPlan) -> [String: Any] {
    let steps = plan.steps.map { step -> [String: Any] in
        var entry: [String: Any] = ["name": step.name, "seconds": step.seconds, "watts": step.watts]
        if let end = step.endWatts { entry["endWatts"] = end }
        return entry
    }
    return ["version": plan.version, "kind": plan.kind.rawValue, "name": plan.name, "ftpWatts": plan.ftpWatts.map { $0 as Any } ?? NSNull(), "steps": steps]
}
private func message(_ operation: () throws -> Void) -> String? {
    do { try operation(); return nil } catch { return error.localizedDescription }
}
/// Writes the fixture (when asked) and then requires the stored file to equal what the code produces now.
private func matchFixture(_ name: String, _ expected: [String: Any]) throws {
    let url = root.appendingPathComponent("contracts/fixtures/\(name).json")
    if writing { try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic) }
    let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect((stored as NSDictionary).isEqual(to: expected), "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter WebWorkoutFixtures")
}

// MARK: ZWO

private func zwo(_ steps: String, sport: String = "<sportType>bike</sportType>", name: String = "<name>Test</name>") -> String {
    "<?xml version=\"1.0\"?><workout_file>\(name)\(sport)<workout>\(steps)</workout></workout_file>"
}
private let anyFile = "contracts/workout-example.zwo"

@Test func zwoCasesMatchTheSharedFixture() throws {
    let example = try Data(contentsOf: root.appendingPathComponent(anyFile))
    // The web keeps a byte-identical copy of the example so its suite stays self-contained.
    let copy = try Data(contentsOf: root.appendingPathComponent("ftpunk_web/tests/fixtures/workout-example.zwo"))
    #expect(copy == example, "Copy contracts/workout-example.zwo to ftpunk_web/tests/fixtures/ again")

    let steady = #"<SteadyState Duration="60" Power="0.5"/>"#
    let inputs: [(String, String?, String, Double?)] = [   // name, file, xml, ftp
        ("the example at 250 W", "workout-example.zwo", "", 250),
        ("the example at 180 W", "workout-example.zwo", "", 180),
        ("no FTP", nil, zwo(steady), nil), ("zero FTP", nil, zwo(steady), 0),
        ("free ride", nil, zwo(steady + #"<FreeRide Duration="600"/>"#), 250), ("max effort", nil, zwo(#"<MaxEffort Duration="30"/>"#), 250),
        ("solid state without power", nil, zwo(#"<SolidState Duration="30"/>"#), 250),
        ("solid state steady", nil, zwo(#"<SolidState Duration="30" Power="0.9"/>"#), 250),
        ("solid state ramp", nil, zwo(#"<SolidState Duration="30" PowerLow="0.5" PowerHigh="1.0"/>"#), 250),
        ("sport is run", nil, zwo(steady, sport: "<sportType>run</sportType>"), 250), ("sport is absent", nil, zwo(steady, sport: ""), 250),
        ("sport is BIKE in capitals", nil, zwo(steady, sport: "<sportType> BIKE </sportType>"), 250),
        ("empty file", nil, "", 250), ("not xml", nil, "not xml", 250), ("unclosed", nil, "<workout_file><workout><SteadyState Duration=\"60\" Power=\"0.5\"/></workout>", 250),
        ("other root", nil, "<other/>", 250), ("doctype with entity", nil, "<!DOCTYPE workout_file [<!ENTITY a \"b\">]><workout_file><workout/></workout_file>", 250),
        ("doctype alone", nil, "<!DOCTYPE workout_file><workout_file><workout><SteadyState Duration=\"60\" Power=\"0.5\"/></workout></workout_file>", 250),
        ("no steps", nil, zwo(""), 250),
        ("watts instead of a fraction", nil, zwo(#"<SteadyState Duration="60" Power="200"/>"#), 250),
        ("missing power", nil, zwo(#"<SteadyState Duration="60"/>"#), 250), ("ramp with one end", nil, zwo(#"<Ramp Duration="60" PowerLow="0.5"/>"#), 250),
        ("missing duration", nil, zwo(#"<SteadyState Power="0.5"/>"#), 250), ("negative duration", nil, zwo(#"<SteadyState Duration="-5" Power="0.5"/>"#), 250),
        ("repeat 101", nil, zwo(#"<IntervalsT Repeat="101" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#), 250),
        ("repeat 0", nil, zwo(#"<IntervalsT Repeat="0" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#), 250),
        ("repeat 2.5", nil, zwo(#"<IntervalsT Repeat="2.5" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#), 250),
        ("intervals with ramps", nil, zwo(#"<IntervalsT Repeat="2" OnDuration="60" OffDuration="30" PowerOnLow="0.8" PowerOnHigh="1.1" OffPower="0.5"/>"#), 250),
        ("intervals with half a ramp", nil, zwo(#"<IntervalsT Repeat="2" OnDuration="60" OffDuration="30" PowerOnLow="0.8" OffPower="0.5"/>"#), 250),
        ("too many steps", nil, zwo(String(repeating: #"<IntervalsT Repeat="100" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#, count: 3)), 250),
        ("longer than a day", nil, zwo(#"<SteadyState Duration="86000" Power="0.5"/><SteadyState Duration="86000" Power="0.5"/>"#), 250),
        ("one step over a day", nil, zwo(#"<SteadyState Duration="86401" Power="0.5"/>"#), 250),
        ("textevent and cadence are ignored", nil, zwo(#"<SteadyState Duration="60" Power="0.5" Cadence="90"><textevent timeoffset="0" message="Go"/></SteadyState><Cooldown Duration="120" PowerLow="0.6" PowerHigh="0.3"/>"#), 250),
        ("a long name is cut to 100 characters", nil, zwo(steady, name: "<name>\(String(repeating: "N", count: 130))</name>"), 250),
        ("a blank name", nil, zwo(steady, name: "<name>   </name>"), 250),
        ("rounding to whole watts", nil, zwo(#"<SteadyState Duration="60" Power="0.567"/><SteadyState Duration="60" Power="1.005"/>"#), 233),
        ("power that rounds to zero watts", nil, zwo(#"<SteadyState Duration="60" Power="0.001"/>"#), 100),
        ("sport after the workout, with a bad step first", nil, "<workout_file><workout><FreeRide Duration=\"60\"/></workout><sportType>run</sportType></workout_file>", 250),
    ]
    let imports = inputs.map { name, file, xml, ftp -> [String: Any] in
        let data = file.map { _ in example } ?? Data(xml.utf8)
        var entry: [String: Any] = ["name": name, "ftp": ftp.map { $0 as Any } ?? NSNull()]
        if let file { entry["file"] = file } else { entry["xml"] = xml }
        do { entry["plan"] = planJSON(try ZWOImport.parse(data, ftp: ftp)) } catch { entry["error"] = error.localizedDescription }
        return entry
    }

    func plan(_ name: String, ftp: Double?, _ steps: [TrainingPlan.Step]) throws -> TrainingPlan { try TrainingPlan(kind: .workout, name: name, ftpWatts: ftp, steps: steps) }
    let sweet = try WorkoutLibrary.definition(id: "sweet-spot-3x10")!.plan(ftp: 250)
    let exportCases: [(String, TrainingPlan, Double?)] = [
        ("escapes text and uses the plan's FTP", try plan("Over & <under> \"x\"", ftp: 200, [.init("a", seconds: 60, watts: 150), .init("b", seconds: 90.4, watts: 100, endWatts: 250)]), 999),
        ("watt plan uses the rider's FTP", try plan("Plain", ftp: nil, [.init("a", seconds: 60, watts: 150)]), 300),
        ("watt plan without an FTP", try plan("Plain", ftp: nil, [.init("a", seconds: 60, watts: 150)]), nil),
        ("resistance ride", try TrainingPlan.resistanceRide(level: 50), 250),
        ("a library workout", sweet, nil),
        ("a plan with ramps and half seconds", try plan("Ramps ünïcode 100% – done", ftp: 233, [.init("a", seconds: 0.4, watts: 117, endWatts: 351), .init("b", seconds: 30.5, watts: 1)]), nil),
        ("a name with no letters", try plan("--- ###", ftp: 250, [.init("a", seconds: 60, watts: 125)]), nil),
    ]
    let exports = exportCases.map { name, plan, ftp -> [String: Any] in
        var entry: [String: Any] = ["name": name, "plan": planJSON(plan), "riderFTP": ftp.map { $0 as Any } ?? NSNull(), "fileName": ZWOExport.fileName(for: plan)]
        do { entry["xml"] = String(decoding: try ZWOExport.data(plan, ftp: ftp), as: UTF8.self) } catch { entry["error"] = error.localizedDescription }
        return entry
    }
    try matchFixture("zwo-cases", ["format": "ftpunk-zwo-cases", "version": 1, "imports": imports, "exports": exports])
}

// MARK: Workout text, custom workouts

private let riderA = UUID(uuidString: "A1E00000-0000-4000-8000-000000000001")!
private let riderB = UUID(uuidString: "5A400000-0000-4000-8000-000000000002")!
private let stamp = Date(timeIntervalSince1970: 1_793_700_000)
private func pct(_ value: Double) -> CustomWorkout.Target { .percentFTP(value) }
private func step(_ name: String = "", _ seconds: Double, _ start: CustomWorkout.Target, to end: CustomWorkout.Target? = nil) -> CustomWorkout.Step {
    .init(name: name, seconds: seconds, start: start, end: end)
}
private func custom(_ n: Int, _ name: String, rider: UUID = riderA, category: WorkoutCategory? = nil, _ blocks: [CustomWorkout.Block]) -> CustomWorkout {
    CustomWorkout(id: UUID(uuidString: String(format: "C0570000-0000-4000-8000-%012d", n))!, riderID: rider, name: name, category: category, blocks: blocks, updatedAt: stamp)
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
private func generatedBlocks(count: Int) -> [[CustomWorkout.Block]] {
    var generator = SeededGenerator(seed: 42)
    let names = ["", "", "Warm-up", "Hard", "Easy", "Sweet spot", "Time at threshold", "Spin-up", "Recovery", "Over", "Under"]
    func canonical(_ t: CustomWorkout.Target) -> CustomWorkout.Target {
        guard t.isPercent else { return t }
        return .percentFTP((Double(String(format: "%.1f", t.number * 100)) ?? 50) / 100)
    }
    func target(_ percent: Bool) -> CustomWorkout.Target {
        percent ? .percentFTP((Double(Int.random(in: 300...2500, using: &generator)) / 10).rounded() / 100) : .watts(Double(Int.random(in: 20...1500, using: &generator)))
    }
    func makeStep() -> CustomWorkout.Step {
        let percent = Bool.random(using: &generator), first = target(percent), ramp = Int.random(in: 0..<4, using: &generator) == 0
        return .init(name: names.randomElement(using: &generator) ?? "", seconds: Double(Int.random(in: 5...14400, using: &generator)), start: canonical(first), end: ramp ? canonical(target(percent)) : nil)
    }
    return (0..<count).map { _ in
        (0..<Int.random(in: 1...6, using: &generator)).map { _ in
            Int.random(in: 0..<3, using: &generator) == 0
                ? .repeats(count: Int.random(in: 1...100, using: &generator), steps: (0..<Int.random(in: 1...4, using: &generator)).map { _ in makeStep() })
                : .step(makeStep())
        }
    }
}

@Test func workoutTextCasesMatchTheSharedFixture() throws {
    let parseInputs: [String] = [
        "Warm-up\n- 10m 50%\nMain set 5x\n- 3m 115%\n- Recovery 1m30 55%\nRamp down\n- 5m ramp 60-40%\nSprint\n- 20s 650w\n- 1h 200W\n- 2m30s ramp 100-200w",
        "Warmup\n- 20m 60%\n\nMain set 6x\n- 4m 100%\n- 5m recovery at 40%\n\nCooldown\n- 20m 60%",
        "Main set 3x\n- 1m 100%\n", "- 5m @ 80%\r\n- Time at threshold 10m 95%\r\n", "- 5m @ 80%\r- 1m 50%", "  - 30s 120%  \n\t- 1h30m 45%",
        "- 10m 50% 90rpm", "- 20m 60% 90-100rpm", "- 5m 55% HR", "- 5m 100% LTHR", "- 60m Z2", "- 10m Z2-Z3", "- 5m 70% pace", "- 1km 80%", "- 800mtr 80%",
        "- 20m freeride", "- Press lap 10m 50%", "- 10m 50% ftp", "- 5m 50% 1mi", "- 5m 50% %hr", "- 5m 50% noshowavg",
        "- 10m 80-90%", "- 10m ramp 60%", "- 10m ramp", "- 10m", "- 80%", "- 5m 10m 80%", "- 5m 80% 90%", "- 3s 80%", "- 4h1s 80%", "- 5m 20%", "- 5m 10w", "- 5m 251%",
        "- 5m ramp 60-80% 70%", "- 5m 70% ramp 60-80%", "- 5m ramp ramp 60-80%", "- 5m ramp 60-80w 70%", "- 5m ramp 60-80% foo",
        "Main set 101x\n- 1m 50%", "Main set 0x\n- 1m 50%", "Main set 3x\n\n- 1m 50%", "5x\n- 1m 50%\n- 2m 60%", "Set -5x\n- 1m 50%", "Set +5x\n- 1m 50%", "Set 05X\n- 1m 50%",
        "", "   \n\n", "just a header", "Header only\n\n", "- 10m 50% 90rpm\n- 5m\n- 1m 60%", "Warm-up\n- 10m 50%\n\n- 10m 50% 90rpm",
        "- 1m30 50%", "- 1m30s 50%", "- 90s 50%", "- 1h 50%", "- 1h30 50%", "- 30s1m 50%", "- 1.5m 50%", "- 10 50%", "- 7:30 50%",
        "- 80.5% for 5m", "- 5m 80.55%", "- 5m 99.999%", "- 5m 0.8%", "- 5m 200.5w", "- 5m ramp 60.5-80.25%", "- 5m 080%",
        "Name 1\n- 5m 50%\nName 2\n- Own 5m 60%", "Name\n- 5m 50%\n- 5m 60%", "Set\nMain 3x\n- 5m 50%", "Warm-up\n\n- 5m 50%",
        "- Zone training 5m 50%", "- Hard 10m at 100%", "- Sweet at spot 5m 90%", "- at 5m 90%", "- 5m at ramp 50-90%", "- Tempo ünïcode 5m 75%",
        "- " + String(repeating: "N", count: 101) + " 5m 50%", "- " + String(repeating: "N", count: 100) + " 5m 50%",
        "-5m 50%", "- - 5m 50%", "-", "- ", "x\n- 1m 50%", "1x\n- 1m 50%", "100x\n- 1m 50%\n\n2x\n- 30s 120%\n- 30s 50%",
    ]
    let parsed = try parseInputs.map { text -> [String: Any] in
        let result = WorkoutText.parse(text)
        var entry: [String: Any] = ["text": text]
        if result.isValid { entry["blocks"] = try object(result.blocks) }
        else { entry["errors"] = result.errors.map { ["line": $0.line, "message": $0.message] as [String: Any] } }
        return entry
    }
    let printed = try generatedBlocks(count: 80).map { blocks -> [String: Any] in ["blocks": try object(blocks), "text": WorkoutText.print(blocks)] }
    // Every printed text of the generated set reads back to the same blocks (the same promise the Swift suite checks).
    for blocks in generatedBlocks(count: 80) { #expect(WorkoutText.parse(WorkoutText.print(blocks)).blocks == blocks) }

    let nameCases = ["Plain", "Time at threshold", "5m rest", "Set 5x", "two  spaces", "with\nline", " lead", "x", "-dash", "80%", "ramp up", "Zone", "Z2", "at", "@", "Spin-up", "10w", "5X", "5x5", "Press", "ftp", "hr"]
    let names = nameCases.map { ["name": $0, "plain": CustomWorkout.nameIsPlain($0), "normalized": CustomWorkout.normalized($0)] as [String: Any] }
    let durationCases = ["3:30", "1:00:00", "5", "90s", "1m30", "1h", "1:75", "abc", "-3", "0", "", "5.5", "1:2:3:4", "0:30", "2:30:75", "10m", "1h30m", " 7 ", "1h5s", "2m5", "5m 3s"]
    let durations = durationCases.map { text -> [String: Any] in ["text": text, "seconds": CustomWorkout.parseDuration(text).map { $0 as Any } ?? NSNull()] }
    let durationTexts = [0, 5, 59, 60, 210, 3599, 3600, 3725, 86399, 90.4, 90.6].map { ["seconds": $0, "text": CustomWorkout.durationText($0)] as [String: Any] }
    let printTexts = [0, 5, 30, 59, 60, 90, 600, 3600, 3661, 14400, 12.4, 12.6].map { ["seconds": $0, "text": WorkoutText.durationText(Double($0))] as [String: Any] }
    try matchFixture("workout-text-cases", ["format": "ftpunk-workout-text-cases", "version": 1, "parse": parsed, "print": printed,
                                           "names": names, "durations": durations, "durationTexts": durationTexts, "printedDurations": printTexts])
}

@Test func customWorkoutsResolveLikeTheSharedFixtureAt250Watts() throws {
    let mixed = custom(1, "Mixed", [.step(step("Warm-up", 300, pct(0.5))), .repeats(count: 2, steps: [step("Hard", 60, pct(1.2)), step("Easy", 60, .watts(100))]), .step(step("", 120, .watts(100), to: .watts(250)))])
    var valid: [CustomWorkout] = [
        mixed,
        custom(2, "Watts only", category: .threshold, [.step(step("a", 60, .watts(200)))]),
        custom(3, "Ramps in percent", category: .vo2max, [.step(step("", 600, pct(0.4), to: pct(0.9))), .step(step("Down", 300, pct(0.9), to: pct(0.4)))]),
        custom(4, "Limits", [.step(step("", 5, pct(0.3))), .step(step("", 14400, pct(2.5))), .step(step("", 5, .watts(20))), .step(step("", 5, .watts(1500)))]),
        custom(5, "Repeat of repeats of one", [.repeats(count: 100, steps: Array(repeating: step("s", 5, pct(0.5)), count: 5))]),
        custom(6, "Rounding", [.step(step("a", 60, pct(0.333))), .step(step("b", 60, pct(0.5)))]),   // 83.25 W and 125 W at 250
        custom(7, "Same ends", [.step(step("flat", 60, .watts(150), to: .watts(150)))]),               // a ramp with equal ends is a plain step in the plan
        custom(8, "  Trim me  ", [.step(step("", 60, pct(0.5)))]),
        custom(9, "Tiny percent", [.step(step("", 60, pct(0.3)))]),
        custom(10, "Other rider", rider: riderB, [.step(step("x", 60, pct(1)))]),
    ]
    for (index, definition) in WorkoutLibrary.catalog.enumerated() {
        valid.append(try #require(CustomWorkout(definition: definition, riderID: riderA, id: UUID(uuidString: String(format: "C0570000-0000-4000-8000-%012d", 100 + index))!, date: stamp)))
    }
    let plan = try WorkoutLibrary.catalog[0].plan(ftp: 200)
    valid.append(try #require(CustomWorkout(plan: plan, riderID: riderA, id: UUID(uuidString: "C0570000-0000-4000-8000-000000000200")!, date: stamp)))
    let tooSmall = try TrainingPlan(kind: .workout, name: "Tiny", steps: [.init("blip", seconds: 1, watts: 200)])
    #expect(CustomWorkout(plan: tooSmall, riderID: riderA) == nil)

    let records = try valid.map { workout -> [String: Any] in
        var entry: [String: Any] = ["workout": try object(workout), "issues": workout.issues(), "needsFTP": workout.needsFTP, "durationSeconds": workout.duration,
                                    "flatCount": workout.flattened.count, "text": WorkoutText.print(workout.blocks),
                                    "flatRanges": workout.flatRanges().map { [$0.lowerBound, $0.upperBound] }]
        do { entry["plan250"] = planJSON(try workout.plan(ftp: 250)) } catch { entry["error250"] = error.localizedDescription }
        do { entry["planNoFTP"] = planJSON(try workout.plan(ftp: nil)) } catch { entry["errorNoFTP"] = error.localizedDescription }
        do { entry["plan100"] = planJSON(try workout.plan(ftp: 100)) } catch { entry["error100"] = error.localizedDescription }
        entry["load250"] = workout.estimatedLoad(ftp: 250).map { ["intensityFactor": $0.intensityFactor, "tss": $0.tss] as [String: Any] } ?? NSNull()
        return entry
    }
    let invalid: [CustomWorkout] = [
        custom(300, "", [.step(step("", 60, pct(0.5)))]), custom(301, "No steps", []), custom(302, String(repeating: "N", count: 101), [.step(step("", 60, pct(0.5)))]),
        custom(303, "Short", [.step(step("", 4, pct(0.5)))]), custom(304, "Long", [.step(step("", 14401, pct(0.5)))]),
        custom(305, "Low %", [.step(step("", 60, pct(0.29)))]), custom(306, "High %", [.step(step("", 60, pct(2.51)))]),
        custom(307, "Low W", [.step(step("", 60, .watts(19)))]), custom(308, "High W", [.step(step("", 60, .watts(1501)))]),
        custom(309, "Mixed ramp", [.step(step("", 60, .watts(150), to: pct(0.8)))]),
        custom(310, "Repeat 101", [.repeats(count: 101, steps: [step("", 60, pct(0.5))])]), custom(311, "Repeat 0", [.repeats(count: 0, steps: [step("", 60, pct(0.5))])]),
        custom(312, "Empty repeat", [.repeats(count: 2, steps: [])]),
        custom(313, "Too many steps", [.repeats(count: 100, steps: Array(repeating: step("", 5, pct(0.5)), count: 5)), .step(step("", 5, pct(0.5)))]),
        custom(314, "Longer than a day", [.repeats(count: 100, steps: [step("", 14400, pct(0.5))])]),
        custom(315, "Names", [.step(step("5m rest", 60, pct(0.5))), .step(step("Set 5x", 60, pct(0.5))), .step(step("two  spaces", 60, pct(0.5))), .step(step("with\nline", 60, pct(0.5))), .step(step(String(repeating: "N", count: 101), 60, pct(0.5)))]),
        custom(316, "Many problems", [.step(step("", 1, pct(5))), .repeats(count: 0, steps: [step("", 99999, .watts(1))])]),
    ]
    let rejected = try invalid.map { workout -> [String: Any] in ["workout": try object(workout), "issues": workout.issues()] }
    try matchFixture("custom-workouts-250w", ["format": "ftpunk-custom-workouts", "version": 1, "ftpWatts": 250, "workouts": records, "invalid": rejected])
}

// MARK: Portable v3 with custom workouts

@Test func portableV3WithCustomWorkoutsMatchesTheSharedFixtureAndRoundTrips() throws {
    let a = RiderProfile(id: riderA, name: "Alex", weightKG: 71, ftpHistory: [FTPEntry(id: UUID(uuidString: "F7000000-0000-4000-8000-000000000230")!, watts: 230, date: stamp, source: "Ramp test")],
                         currentFTPID: UUID(uuidString: "F7000000-0000-4000-8000-000000000230")!)
    let b = RiderProfile(id: riderB, name: "Sam")
    let workouts = [custom(1, "Mixed", category: .sweetSpot, [.step(step("Warm-up", 300, pct(0.5))), .repeats(count: 3, steps: [step("Hard", 180, pct(1.05), to: pct(1.1)), step("Easy", 120, .watts(100))]), .step(step("", 120, .watts(100), to: .watts(250)))]),
                    custom(2, "Watts only", [.step(step("", 600, .watts(180)))]), custom(3, "Sam's", rider: riderB, [.step(step("x", 60, pct(1)))])]
    let cached = CachedWorkout(id: "5a400000-0000-4000-8000-000000000099", riderID: riderA, source: "Imported ZWO",
                               plan: try TrainingPlan(kind: .workout, name: "Imported", ftpWatts: 230, steps: [.init("Steady", seconds: 600, watts: 200)]), date: stamp)
    let archive = PortableArchive(profiles: [a, b], sessions: [], date: stamp, workouts: [cached], customWorkouts: workouts)
    #expect(archive.version == 3 && archive.customWorkouts?.count == 3)
    let url = root.appendingPathComponent("contracts/fixtures/portable-v3-custom.json")
    if writing { try archive.encoded().write(to: url, options: .atomic) }
    // Native -> file -> native.
    let decoded = try PortableArchive.decode(Data(contentsOf: url))
    #expect(decoded.customWorkouts == workouts && decoded.version == 3)
    #expect(try Data(contentsOf: url) == archive.encoded(), "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter WebWorkoutFixtures")
    // The file the web app wrote after reading it (kept next to the web fixtures) decodes to the same custom workouts.
    let webCopy = root.appendingPathComponent("ftpunk_web/tests/fixtures/portable-v3-custom.json")
    #expect(try Data(contentsOf: webCopy) == Data(contentsOf: url))
}
