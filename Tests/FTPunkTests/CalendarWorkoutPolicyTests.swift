import Foundation
import Testing
import FTPunkDomain
import FTPunkIntegrations
import FTPunkStorage
@testable import FTPunkApp

private func event(_ id: Int = 1, sport: String = "Ride", steps: [[String: Any]]) -> [String: Any] {
    ["id": id, "name": "Workout \(id)", "type": sport, "category": "WORKOUT",
     "workout_doc": ["steps": steps]]
}
private var percentStep: [String: Any] { ["duration": 60, "power": ["units": "%ftp", "value": 90]] }
private var wattsStep: [String: Any] { ["duration": 60, "power": ["units": "w", "value": 150]] }

@Test func calendarQualificationRequiresCyclingAndOriginalPercentPower() {
    for sport in ["Ride", "VirtualRide"] {
        #expect(CalendarWorkoutPolicy.qualifies(event(sport: sport, steps: [percentStep])))
        #expect(CalendarWorkoutPolicy.qualifies(event(sport: sport, steps: [wattsStep, percentStep])))
        #expect(!CalendarWorkoutPolicy.qualifies(event(sport: sport, steps: [wattsStep])))
    }
    for sport in ["Run", "WeightTraining", "Yoga", "Other", ""] {
        #expect(!CalendarWorkoutPolicy.qualifies(event(sport: sport, steps: [percentStep])))
    }
    #expect(!CalendarWorkoutPolicy.qualifies(event(steps: [])))
    #expect(!CalendarWorkoutPolicy.qualifies(["type": "Ride"]))
    #expect(!CalendarWorkoutPolicy.qualifies(event(steps: [["duration": 60, "hr": ["units": "%lthr", "value": 90]]])))
    #expect(!CalendarWorkoutPolicy.qualifies(event(steps: [["duration": 60, "pace": ["units": "%pace", "value": 90]]])))
    #expect(!CalendarWorkoutPolicy.qualifies(event(steps: [["duration": 60, "_power": ["value": 150]]])))
}

@Test func calendarQualificationIncludesNestedRampsAndResolvedPercentTargets() throws {
    let ramp: [String: Any] = ["duration": 60, "ramp": true, "power": ["units": "%FTP", "start": 50, "end": 90], "_power": ["start": 100, "end": 180]]
    let input = event(steps: [["reps": 2, "steps": [wattsStep, ["reps": 3, "steps": [ramp]]]]])
    #expect(CalendarWorkoutPolicy.qualifies(input))
    let result = try IntervalsClient.decodeWorkouts(JSONSerialization.data(withJSONObject: [input]), accountID: "test", riderID: RiderProfile.legacyID, ftp: 200)
    #expect(result.skipped.isEmpty && result.workouts.count == 1)
    #expect(result.workouts.first?.plan.steps.last?.endWatts == 180)
}

@Test func calendarDecoderSilentlyDropsUnqualifiedEventsAndNamesOnlyQualifiedFailures() throws {
    var broken = percentStep
    broken["duration"] = -1
    let events = [event(1, sport: "Run", steps: [broken]), event(2, steps: []), event(3, steps: [wattsStep]),
                  event(4, steps: [percentStep]), event(5, sport: "VirtualRide", steps: [wattsStep, percentStep]),
                  event(6, steps: [broken])]
    let result = try IntervalsClient.decodeWorkouts(JSONSerialization.data(withJSONObject: events), accountID: "test", riderID: RiderProfile.legacyID, ftp: 200)
    #expect(result.workouts.map(\.plan.name) == ["Workout 4", "Workout 5"])
    #expect(result.workouts.last?.plan.steps.map(\.watts) == [150, 180])
    #expect(result.skipped.count == 1 && result.skipped.first?.hasPrefix("Workout 6:") == true)
    // The broader file importer remains independent of the calendar rule.
    #expect(try WorkoutImport.parse(JSONSerialization.data(withJSONObject: event(steps: [wattsStep]))).steps.first?.watts == 150)
}

@Test func calendarSyncSummaryUsesTheQualifiedCount() {
    #expect(CalendarWorkoutPolicy.syncSummary(count: 7) == "7 cycling workouts with % FTP targets synced")
    #expect(CalendarWorkoutPolicy.syncSummary(count: 0) == "0 cycling workouts with % FTP targets synced")
}

private final class CalendarProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let failing = request.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("API_KEY:failure".utf8).base64EncodedString()
        let response = HTTPURLResponse(url: request.url!, statusCode: failing ? 503 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = Data(#"[{"id":1,"name":"Cycling","type":"Ride","category":"WORKOUT","workout_doc":{"steps":[{"duration":60,"power":{"units":"%ftp","value":90}}]}},{"id":2,"name":"Commute","type":"Ride"},{"id":3,"name":"Broken cycling","type":"Ride","category":"WORKOUT","workout_doc":{"steps":[{"duration":-1,"power":{"units":"%ftp","value":90}}]}}]"#.utf8)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test @MainActor func qualifiedCalendarDownloadReplacesOnlyItsCacheAndFailedDownloadKeepsIt() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CalendarProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let store = try LocalStore(inMemory: true)
    let rider = RiderProfile.legacyID, other = UUID()
    let plan = try TrainingPlan.starters(ftp: 200)[0]
    func cached(_ id: String, owner: UUID = RiderProfile.legacyID) -> CachedWorkout {
        CachedWorkout(id: id, riderID: owner, source: "Test", plan: plan, scheduledDate: "2025-01-01")
    }
    let prefix = "intervals:account:\(rider.uuidString.lowercased()):"
    let old = cached(prefix + "old"), file = cached("file"), otherAccount = cached("intervals:another:\(rider.uuidString.lowercased()):old"), otherRider = cached("intervals:account:\(other.uuidString.lowercased()):old", owner: other)
    try store.saveWorkouts([old, file, otherAccount, otherRider])
    let catalog = WorkoutCatalog(store: store, persistTimes: false, client: IntervalsClient(session: session))
    var context = WorkoutCatalog.Context(riderID: rider, ftp: 200, connection: IntervalsConnection(athleteID: "account", athleteName: "Test", apiKey: "failure"), isBusy: false)
    let failure = await catalog.download(context: { context }, quiet: false)
    #expect(failure != nil)
    #expect(Set(try store.workouts().map(\.id)) == [old.id, file.id, otherAccount.id, otherRider.id])
    context.connection = IntervalsConnection(athleteID: "account", athleteName: "Test", apiKey: "success")
    let success = await catalog.download(context: { context }, quiet: true)
    #expect(success == nil)
    #expect(Set(catalog.cached.map(\.id)) == [prefix + "1", file.id, otherAccount.id, otherRider.id])
    #expect(catalog.syncMessage == "1 cycling workouts with % FTP targets synced")
    #expect(catalog.report?.hasPrefix("Broken cycling:") == true)
    #expect(catalog.report?.contains("Skipped") == false && catalog.report?.contains("Commute") == false)
}
