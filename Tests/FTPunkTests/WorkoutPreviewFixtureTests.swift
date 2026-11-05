import Foundation
import Testing
import FTPunkDomain

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func rounded(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

/// What the workout preview shows for every classic at 250 W, with values on and off. The JavaScript port compares against
/// the same file (`ftpunk_web/tests/fixtures/workout-preview-250w.json`).
private func previewFixture() throws -> [String: Any] {
    let workouts = try WorkoutLibrary.classics(ftp: 250).map { classic -> [String: Any] in
        let plan = classic.plan
        func steps(_ intensity: Int, _ showValues: Bool) -> [[String: Any]] {
            WorkoutPreview.steps(for: plan, intensity: intensity, showValues: showValues).map { step in
                var entry: [String: Any] = ["name": step.name, "valueText": step.valueText, "spokenText": step.spokenText, "wattsText": step.wattsText,
                                            "durationText": step.durationText]
                entry["zone"] = step.zone?.title ?? NSNull()
                entry["percentText"] = step.percentText ?? NSNull()
                return entry
            }
        }
        let groups = WorkoutPreview.groups(for: plan).map { group -> [String: Any] in
            ["start": group.range.lowerBound, "end": group.range.upperBound, "repeats": group.repeats, "text": group.text]
        }
        let bars = WorkoutProfile.bars(for: plan).map { bar -> [String: Any] in
            ["start": rounded(bar.start), "end": rounded(bar.end), "startHeight": rounded(bar.startHeight), "endHeight": rounded(bar.endHeight),
             "zone": bar.zone?.title ?? NSNull()]
        }
        return ["id": classic.id, "durationSeconds": plan.duration, "durationText": DurationFormat.workout(plan.duration),
                "intensityLabel": IntensityLabel.label(for: plan), "mainSetWatts": IntensityLabel.mainSetWatts(for: plan) ?? NSNull(),
                "mainSetText": WorkoutPreview.mainSetText(for: plan) ?? NSNull(),
                "mainSetTextNoValues": WorkoutPreview.mainSetText(for: plan, showValues: false) ?? NSNull(),
                "mainSetText110": WorkoutPreview.mainSetText(for: plan, intensity: 110) ?? NSNull(),
                "averageWatts": rounded(WorkoutProfile.averageWatts(for: plan)),
                "steps": steps(100, true), "stepsNoValues": steps(100, false), "steps110": steps(110, true),
                "groups": groups, "bars": bars]
    }
    return ["format": "ftpunk-workout-preview", "version": 1, "ftpWatts": 250, "workouts": workouts]
}

@Test func workoutPreviewMatchesTheSharedFixtureAt250Watts() throws {
    let url = root.appendingPathComponent("contracts/fixtures/workout-preview-250w.json")
    let expected = try previewFixture()
    if ProcessInfo.processInfo.environment["FTPUNK_WRITE_FIXTURES"] == "1" {
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect((stored as NSDictionary).isEqual(to: expected), "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter workoutPreviewMatchesTheSharedFixtureAt250Watts")
    let workouts = try #require(stored["workouts"] as? [[String: Any]])
    #expect(workouts.count == 14)
    let vo2 = try #require(workouts.first { $0["id"] as? String == "vo2max-5x3" })
    #expect(vo2["mainSetText"] as? String == "5 × 3:00 @ 115 % (288 W)")
}
