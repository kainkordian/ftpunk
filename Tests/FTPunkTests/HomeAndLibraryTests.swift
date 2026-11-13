import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
import FTPunkIntegrations
@testable import FTPunkApp

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The catalog as the shared fixture describes it. The JavaScript port compares against the same file.
private func catalogFixture() throws -> [String: Any] {
    let workouts = try WorkoutLibrary.classics(ftp: 250).map { classic -> [String: Any] in
        let steps = classic.plan.steps.map { step -> [String: Any] in
            var entry: [String: Any] = ["name": step.name, "seconds": step.seconds, "watts": step.watts]
            if let end = step.endWatts { entry["endWatts"] = end }
            return entry
        }
        return ["id": classic.id, "name": classic.plan.name, "category": classic.category.rawValue,
                "durationSeconds": classic.plan.duration, "steps": steps]
    }
    return ["format": "ftpunk-workout-library", "version": 1, "ftpWatts": 250, "workouts": workouts]
}

@Test func workoutLibraryMatchesTheSharedFixtureAt250Watts() throws {
    let url = root.appendingPathComponent("contracts/fixtures/workout-library-250w.json")
    let expected = try catalogFixture()
    if ProcessInfo.processInfo.environment["FTPUNK_WRITE_FIXTURES"] == "1" {
        try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    let stored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    #expect((stored as NSDictionary).isEqual(to: expected), "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter workoutLibraryMatchesTheSharedFixtureAt250Watts")
    let workouts = try #require(stored["workouts"] as? [[String: Any]])
    #expect(workouts.count == 14)
    // Spot-check the resolved numbers a JavaScript port must reproduce.
    let sweet = try #require(workouts.first { $0["id"] as? String == "sweet-spot-3x10" })
    let steps = try #require(sweet["steps"] as? [[String: Any]])
    #expect(steps.count == 7 && steps[0]["watts"] as? Int == 125 && steps[0]["endWatts"] == nil && steps[1]["watts"] as? Int == 225)
    #expect(sweet["durationSeconds"] as? Double == 3300 && sweet["category"] as? String == "sweetSpot")
}

@Test func scheduledDateDecodesWhenPresentAndWhenAbsent() throws {
    let plan = try TrainingPlan.starters(ftp: 200)[0]
    let dated = CachedWorkout(id: "intervals:1:r:2", riderID: RiderProfile.legacyID, source: "Intervals.icu · X", plan: plan, scheduledDate: "2026-11-02")
    let undated = CachedWorkout(id: "intervals:1:r:3", riderID: RiderProfile.legacyID, source: "Intervals.icu · Y", plan: plan)
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    #expect(try decoder.decode(CachedWorkout.self, from: encoder.encode(dated)).scheduledDate == "2026-11-02")
    let undatedData = try encoder.encode(undated)
    #expect(try decoder.decode(CachedWorkout.self, from: undatedData).scheduledDate == nil)
    #expect(try (JSONSerialization.jsonObject(with: undatedData) as? [String: Any])?["scheduledDate"] == nil) // old shape on the wire
    // A cache entry written before the field existed.
    var legacy = try #require(JSONSerialization.jsonObject(with: undatedData) as? [String: Any])
    legacy.removeValue(forKey: "scheduledDate")
    #expect(try decoder.decode(CachedWorkout.self, from: JSONSerialization.data(withJSONObject: legacy)).scheduledDate == nil)
    #expect(throws: (any Error).self) { try CachedWorkout(riderID: RiderProfile.legacyID, source: "x", plan: plan, scheduledDate: "2026-02-30").validate() }
    #expect(throws: (any Error).self) { try CachedWorkout(riderID: RiderProfile.legacyID, source: "x", plan: plan, scheduledDate: "tomorrow").validate() }
}

@Test func legacyV3ArchivesWithoutScheduledDatesStillLoad() throws {
    let data = try Data(contentsOf: root.appendingPathComponent("ftpunk_web/tests/fixtures/portable-v3.json"))
    let archive = try PortableArchive.decode(data)
    #expect(archive.workouts?.isEmpty == false && archive.workouts?.allSatisfy { $0.scheduledDate == nil } == true)
    // A dated entry survives a round trip and keeps the archive at version 3.
    var dated = archive
    let first = try #require(archive.workouts?.first)
    dated.workouts = [CachedWorkout(id: first.id, riderID: first.riderID, source: first.source, plan: first.plan, date: first.savedAt, scheduledDate: "2026-11-03")]
    let restored = try PortableArchive.decode(dated.encoded())
    #expect(restored.version == 3 && restored.workouts?.first?.scheduledDate == "2026-11-03")
    var invalid = dated
    invalid.workouts = [CachedWorkout(id: first.id, riderID: first.riderID, source: first.source, plan: first.plan, scheduledDate: "2026-13-40")]
    #expect(throws: (any Error).self) { try invalid.encoded() }
}

@Test func scheduledDateHelpers() {
    #expect(ScheduledDate.isValid("2026-11-02") && ScheduledDate.isValid("2028-02-29"))
    #expect(!ScheduledDate.isValid("2027-02-29") && !ScheduledDate.isValid("2026-1-2") && !ScheduledDate.isValid("20261102") && !ScheduledDate.isValid(""))
    #expect(ScheduledDate.from(intervalsLocal: "2026-11-02T06:30:00") == "2026-11-02")
    #expect(ScheduledDate.from(intervalsLocal: "2026-11-02") == "2026-11-02")
    #expect(ScheduledDate.from(intervalsLocal: "nonsense!!!") == nil && ScheduledDate.from(intervalsLocal: nil) == nil)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
    let instant = Date(timeIntervalSince1970: 1_793_000_000)
    let text = ScheduledDate.string(for: instant, calendar: calendar)
    #expect(ScheduledDate.isValid(text))
    #expect(ScheduledDate.date(from: text, calendar: calendar).map { calendar.isDate($0, inSameDayAs: instant) } == true)
}

@Test func intervalsEventsKeepTheirLocalCalendarDay() throws {
    let events: [[String: Any]] = [
        ["id": 1, "name": "Dated", "type": "Ride", "category": "WORKOUT", "start_date_local": "2026-11-02T06:00:00",
         "workout_doc": ["steps": [["duration": 600, "power": ["units": "%ftp", "value": 75]]]]],
        ["id": 2, "name": "Undated", "type": "Ride", "category": "WORKOUT",
         "workout_doc": ["steps": [["duration": 600, "power": ["units": "%ftp", "value": 75]]]]]
    ]
    let result = try IntervalsClient.decodeWorkouts(JSONSerialization.data(withJSONObject: events), accountID: "9", riderID: RiderProfile.legacyID, ftp: 200)
    #expect(result.workouts.count == 2)
    #expect(result.workouts.first { $0.id.hasSuffix(":1") }?.scheduledDate == "2026-11-02")
    #expect(result.workouts.first { $0.id.hasSuffix(":2") }?.scheduledDate == nil)
}

private func cached(_ id: String, _ date: String?, rider: UUID = RiderProfile.legacyID, intervals: Bool = true, saved: Double = 0) throws -> CachedWorkout {
    CachedWorkout(id: intervals ? "intervals:1:\(rider.uuidString.lowercased()):\(id)" : id, riderID: rider, source: intervals ? "Intervals.icu · \(id)" : "Imported JSON",
                  plan: try TrainingPlan.starters(ftp: 200)[0], date: Date(timeIntervalSince1970: saved), scheduledDate: date)
}

@Test func todayCardShowsTodaysWorkoutsOrTheNextOne() throws {
    let rider = RiderProfile.legacyID
    let library = [try cached("a", "2026-11-02"), try cached("b", "2026-11-02"), try cached("c", "2026-11-04"), try cached("d", "2026-11-03"),
                   try cached("old", "2026-10-30"), try cached("legacy", nil), try cached("mine", nil, intervals: false),
                   try cached("other", "2026-11-02", rider: UUID())]
    func id(_ name: String) -> String { library.first { $0.id.hasSuffix(":\(name)") || $0.id == name }!.id }
    #expect(TodayWorkouts.select(library, riderID: rider, today: "2026-11-02", connected: true) == .today([id("a"), id("b")]))
    #expect(TodayWorkouts.select(library, riderID: rider, today: "2026-11-02", connected: false) == .today([id("a"), id("b")])) // cached, so offline works
    #expect(TodayWorkouts.select(library, riderID: rider, today: "2026-11-01", connected: true) == .nothingToday(next: id("a")))
    #expect(TodayWorkouts.select(library, riderID: rider, today: "2026-11-05", connected: true) == .nothingToday(next: nil))
    #expect(TodayWorkouts.select([], riderID: rider, today: "2026-11-02", connected: false) == .notConnected)
    #expect(TodayWorkouts.select([], riderID: rider, today: "2026-11-02", connected: true) == .nothingToday(next: nil))
    let upcoming = TodayWorkouts.upcoming(library, riderID: rider, today: "2026-11-02").map(\.id)
    #expect(upcoming == [id("d"), id("c"), id("legacy")]) // dated first, undated last, past and other riders dropped
    #expect(TodayWorkouts.mine(library, riderID: rider).map(\.id) == ["mine"])
}

@Test func calendarReplacementPrunesOnlyTheCurrentRiderAndAccount() throws {
    let rider = RiderProfile.legacyID
    let kept = try cached("kept", "2026-11-05"), gone = try cached("gone", "2026-11-06"), outside = try cached("later", "2026-12-25"),
        past = try cached("past", "2026-10-01"), undated = try cached("undated", nil), mine = try cached("mine", nil, intervals: false)
    let otherRider = try cached("other", "2026-11-06", rider: UUID())
    let otherAccount = CachedWorkout(id: "intervals:2:\(rider.uuidString.lowercased()):old", riderID: rider, source: "Intervals.icu", plan: kept.plan)
    let stale = TodayWorkouts.stale(cached: [kept, gone, outside, past, undated, mine, otherRider, otherAccount], riderID: rider, accountID: "1",
                                    downloaded: [kept.id])
    #expect(Set(stale) == [gone.id, outside.id, past.id, undated.id])
}

@Test func calendarRefreshesAfterAnHourAndNeverDuringARide() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(SyncPolicy.shouldRefresh(lastDownload: nil, now: now, connected: true, rideActive: false))
    #expect(!SyncPolicy.shouldRefresh(lastDownload: now.addingTimeInterval(-3599), now: now, connected: true, rideActive: false))
    #expect(SyncPolicy.shouldRefresh(lastDownload: now.addingTimeInterval(-3601), now: now, connected: true, rideActive: false))
    #expect(!SyncPolicy.shouldRefresh(lastDownload: nil, now: now, connected: true, rideActive: true))
    #expect(!SyncPolicy.shouldRefresh(lastDownload: nil, now: now, connected: false, rideActive: false))
    #expect(!SyncPolicy.shouldRefresh(lastDownload: nil, now: now, connected: true, rideActive: false, alreadyRunning: true))
}
