import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

@MainActor private func ramp(_ rider: RiderProfile, ago days: Double, demo: Bool = false, interrupted: Bool = false) throws -> TestSession {
    var session = try PreviewFixtures.finishedRamp(for: rider, daysAgo: days, scale: 0.9, demo: demo)
    if interrupted { session.outcome = .interrupted; session.result = nil }
    return session
}
@MainActor private func workout(_ rider: RiderProfile, ago days: Double, kind: TrainingPlan.Kind) throws -> TestSession {
    var session = TestSession(startedAt: Date().addingTimeInterval(-days * 86400), configuration: try SessionConfiguration(riderID: rider.id, riderName: rider.name))
    session.training = kind == .workout ? try WorkoutLibrary.definition(id: "tempo-3x5")!.plan(ftp: 200) : try .freeRide(watts: 120)
    session.outcome = .completed; session.endedAtOffset = 1800
    session.samples = [RideSample(time: 0, power: 150), RideSample(time: 1, power: 150)]
    return session
}

@Test @MainActor func activityFiltersSeparateTestsWorkoutsAndFreeRides() throws {
    let rider = PreviewFixtures.rider()
    let test = try ramp(rider, ago: 3), session = try workout(rider, ago: 2, kind: .workout), free = try workout(rider, ago: 1, kind: .freeRide)
    let all = [test, session, free]
    #expect(ProgressRules.activities(all, rider: nil, filter: .all).map(\.id) == [free.id, session.id, test.id]) // newest first
    #expect(ProgressRules.activities(all, rider: nil, filter: .ftpTests).map(\.id) == [test.id])
    #expect(ProgressRules.activities(all, rider: nil, filter: .workouts).map(\.id) == [session.id])
    #expect(ProgressRules.activities(all, rider: nil, filter: .freeRides).map(\.id) == [free.id])
    #expect(ProgressRules.activities(all, rider: UUID(), filter: .all).isEmpty)
    #expect(ActivityFilter.allCases.map(\.title) == ["All", "FTP tests", "Workouts", "Free rides"])
}

@Test @MainActor func activityRowsShowDateActivityResultAndBadges() throws {
    let rider = PreviewFixtures.rider()
    let test = try ramp(rider, ago: 3)
    let row = ActivityRowModel.make(test, uploadStatus: .uploaded)
    #expect(row.title.hasSuffix("· FTP test") && row.value == "\(Int(test.result!.estimatedFTP.rounded())) W")
    #expect(row.badges == [.uploaded] && row.subtitle.hasPrefix("Alex"))
    #expect(ActivityRowModel.make(test, uploadStatus: nil, showRider: false).subtitle == test.outcome?.title)
    let debug = try ramp(rider, ago: 1, demo: true)
    #expect(ActivityRowModel.make(debug, uploadStatus: .queued).badges == [.debug, .uploadQueued])
    #expect(ActivityRowModel.make(debug, uploadStatus: .needsAttention).badges == [.debug, .uploadFailed])
    let broken = try ramp(rider, ago: 1, interrupted: true)
    #expect(ActivityRowModel.make(broken, uploadStatus: nil).badges == [.interrupted] && ActivityRowModel.make(broken, uploadStatus: nil).value == nil)
    let ride = try workout(rider, ago: 1, kind: .workout)
    let rideRow = ActivityRowModel.make(ride, uploadStatus: nil)
    #expect(rideRow.title.hasSuffix("· Tempo 3×5") && rideRow.value == "30 min" && rideRow.badges.isEmpty)
}

@Test @MainActor func trendShowsRealResultsByDefaultAndDebugOnRequestPerRider() throws {
    let alex = PreviewFixtures.rider(), sam = PreviewFixtures.rider(id: PreviewFixtures.samID, name: "Sam", weightKG: nil, ftp: 180)
    let real = try ramp(alex, ago: 10), debug = try ramp(alex, ago: 5, demo: true), other = try ramp(sam, ago: 8)
    let none = try workout(alex, ago: 2, kind: .workout)
    let all = [real, debug, other, none]
    #expect(Set(ProgressRules.trendSessions(all, rider: nil, metric: .watts, includeDebug: false).map(\.id)) == [real.id, other.id])
    #expect(Set(ProgressRules.trendSessions(all, rider: nil, metric: .watts, includeDebug: true).map(\.id)) == [real.id, debug.id, other.id])
    #expect(ProgressRules.trendSessions(all, rider: alex.id, metric: .watts, includeDebug: false).map(\.id) == [real.id])
    // W/kg needs a saved weight: Sam has none.
    #expect(ProgressRules.trendSessions(all, rider: sam.id, metric: .wattsPerKG, includeDebug: false).isEmpty)
    #expect(ProgressRules.trendSessions(all, rider: alex.id, metric: .wattsPerKG, includeDebug: false).count == 1)
    #expect(TrendMetric.allCases.map(\.rawValue) == ["FTP, W", "FTP, W/kg"])
}

@Test @MainActor func twoRidersKeepSeparateResultsAndTrends() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.progressTwoRiders, to: model)
    #expect(model.destination == .progress && model.riders.count == 2 && model.history.count == 3)
    let groups = RiderHistory.groups(sessions: model.history, profiles: model.riders)
    #expect(groups.map(\.name) == ["Alex", "Sam"] && groups.map { $0.sessions.count } == [2, 1])
    let alexOnly = ProgressRules.activities(model.history, rider: PreviewFixtures.alexID, filter: .ftpTests)
    #expect(alexOnly.count == 2 && alexOnly.allSatisfy { $0.riderID == PreviewFixtures.alexID })
    #expect(ProgressRules.trendSessions(model.history, rider: PreviewFixtures.samID, metric: .watts, includeDebug: false).count == 1)
}

@Test @MainActor func deletingARecordingRemovesItsSamplesAndPendingUploadButKeepsAdoptedFTP() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    let rider = PreviewFixtures.rider(ftp: nil)
    try store.saveProfile(rider); try model.reload(); model.selectRider(rider.id)
    let session = try ramp(rider, ago: 2)
    try store.save(session); try model.reload()
    model.adopt(session)
    let adopted = try #require(model.riders.first { $0.id == rider.id }?.currentFTP?.watts)
    var job = ActivityUploadJob(sessionID: session.id, accountID: "acct", file: Data("x".utf8), name: "n", description: "d"); job.status = .queued
    try store.saveUploadJob(job); try model.reload()
    #expect(model.history.count == 1 && model.jobs.count == 1)
    model.delete(session)
    #expect(model.history.isEmpty && model.jobs.isEmpty)
    #expect(try store.sessions().isEmpty && store.uploadJobs().isEmpty)
    #expect(model.riders.first { $0.id == rider.id }?.currentFTP?.watts == adopted) // adopted FTP is kept
    // A different rider's recordings are untouched.
    let other = PreviewFixtures.rider(id: PreviewFixtures.samID, name: "Sam", ftp: nil)
    try store.saveProfile(other)
    let keep = try ramp(other, ago: 1), drop = try ramp(rider, ago: 3)
    try store.save(keep); try store.save(drop); try model.reload()
    model.delete(drop)
    #expect(model.history.map(\.id) == [keep.id])
}

@Test @MainActor func aRunningRideCannotBeDeletedFromProgress() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    await model.start(training: try .freeRide(watts: 100))
    model.advanceMock(seconds: 3)
    let session = try #require(model.engine?.session)
    model.delete(session)
    #expect(model.engine != nil && model.isActive)
    model.stop()
    #expect(model.history.contains { $0.id == session.id })
    model.delete(session)
    #expect(model.history.isEmpty && model.engine == nil)
}
