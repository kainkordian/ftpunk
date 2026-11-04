import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
import FTPunkIntegrations
@testable import FTPunkApp

@Test @MainActor func homeTodayScenarioShowsTodaysWorkoutAndTheRestOfTheCalendar() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.homeToday, to: model)
    let today = ScheduledDate.string(for: Date())
    guard case .today(let ids) = TodayWorkouts.select(model.workoutLibrary, riderID: model.profile.id, today: today, connected: model.connection != nil) else {
        Issue.record("Expected a workout planned for today"); return
    }
    #expect(ids.count == 1 && model.workoutLibrary.first { $0.id == ids[0] }?.plan.name == "Sweet spot 3×12")
    let upcoming = TodayWorkouts.upcoming(model.workoutLibrary, riderID: model.profile.id, today: today)
    #expect(upcoming.map(\.plan.name) == ["Endurance with tempo", "Threshold 2×20", "Older calendar entry"])
    #expect(upcoming.last?.scheduledDate == nil) // an older cache entry appears without a date
    #expect(TodayWorkouts.mine(model.workoutLibrary, riderID: model.profile.id).map(\.plan.name) == ["Club over-unders"])
    // The preview never reaches the network, even though Home asks for a refresh.
    await model.refreshWorkoutsIfNeeded()
    #expect(model.workoutLibrary.count == 5 && model.catalog.syncMessage == nil)
    try await PreviewScenarios.apply(.library, to: model)
    #expect(model.homeFocus == .library)
    try await PreviewScenarios.apply(.homeNotConnected, to: model)
    #expect(TodayWorkouts.select(model.workoutLibrary, riderID: model.profile.id, today: today, connected: false) == .notConnected)
}

@Test @MainActor func classicsNeedAnFTPAndFollowTheCurrentOne() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.homeNoFTP, to: model)
    let none = try #require(model.workoutDetail(for: .classic("sweet-spot-3x10")))
    #expect(none.needsFTP && none.plan == nil && none.previewPlan != nil && none.duration == 3300)
    #expect(model.startBlocker(for: .workout, needsFTP: none.needsFTP) == .needsFTP)
    await model.startWorkout(.classic("sweet-spot-3x10"))
    #expect(!model.isBusy && model.errorMessage == StartBlocker.needsFTP.reason)
    #expect(model.setCurrentFTP("250"))
    let ready = try #require(model.workoutDetail(for: .classic("sweet-spot-3x10")))
    #expect(!ready.needsFTP && ready.plan?.steps[1].watts == 225 && ready.plan?.ftpWatts == 250)
    #expect(model.setCurrentFTP("200"))
    #expect(model.workoutDetail(for: .classic("sweet-spot-3x10"))?.plan?.steps[1].watts == 180)
    #expect(model.workoutDetail(for: .classic("nope")) == nil && model.workoutDetail(for: .cached("nope")) == nil)
}

@Test @MainActor func aClassicWorkoutRunsFromTheLibraryAtTheChosenIntensity() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    try await PreviewScenarios.apply(.homeNotConnected, to: model)
    model.demoMode = true
    model.preflightIntensity = 110
    await model.startWorkout(.classic("sweet-spot-3x10"))
    #expect(model.cockpitPresented && model.engine?.intensity == 110 && model.preflightIntensity == 100)
    let plan = try #require(model.engine?.session.training)
    #expect(plan.name == "Sweet spot 3×10" && plan.ftpWatts == 250) // snapshotted when the ride starts
    model.advanceMock(seconds: 5)
    #expect(model.engine?.targetPower == 138) // first warm-up watt, 125 W at 110 %
    model.setCurrentFTP("180")
    #expect(model.isBusy) // a running ride is never changed by a new FTP
    #expect(model.engine?.session.training == plan)
    model.pauseTraining(); #expect(model.engine?.phase == .paused)
    model.resumeTraining(); #expect(model.engine?.phase == .riding)
    model.stop(); #expect(!model.isBusy && model.history.count == 1)
}

@Test @MainActor func importedWorkoutsKeepTheirWattsAndCanBeRemoved() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("ftpunk_web/tests/fixtures/workout-ramps.json")
    model.importWorkout(try Data(contentsOf: url))
    let imported = try #require(model.workoutLibrary.first)
    #expect(!imported.isFromIntervals && imported.scheduledDate == nil)
    let detail = try #require(model.workoutDetail(for: .cached(imported.id)))
    #expect(detail.plan == imported.plan && detail.source == "Imported" && !detail.needsFTP)
    #expect(TodayWorkouts.mine(model.workoutLibrary, riderID: model.profile.id).count == 1)
    model.deleteWorkout(imported)
    #expect(model.workoutLibrary.isEmpty && model.workoutDetail(for: .cached(imported.id)) == nil)
}

@Test @MainActor func onboardingSavesTheFirstRiderOrLeadsToTheFTPTest() async throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    try await PreviewScenarios.apply(.firstLaunch, to: model)
    #expect(model.onboardingPending)
    #expect(!model.completeOnboarding(name: "  ", weight: "", ftp: "", thenTest: false) && model.onboardingPending)
    #expect(!model.completeOnboarding(name: "Robin", weight: "abc", ftp: "", thenTest: false) && model.onboardingPending)
    #expect(model.completeOnboarding(name: "Robin", weight: "64", ftp: "210", thenTest: false))
    #expect(!model.onboardingPending && model.profile.name == "Robin")
    let saved = try #require(store.profiles().first)
    #expect(saved.weightKG == 64 && saved.currentFTP?.watts == 210)
    try await PreviewScenarios.apply(.firstLaunch, to: model)
    #expect(model.completeOnboarding(name: "Sam", weight: "", ftp: "", thenTest: true))
    #expect(model.preflightPath == [.ftpTest] && model.ftpSummary == nil)
    try await PreviewScenarios.apply(.firstLaunch, to: model)
    model.skipOnboarding()
    let profiles = try store.profiles()
    #expect(!model.onboardingPending && !profiles.isEmpty)
}

@Test @MainActor func calendarRefreshNeverRunsInAPreviewOrDuringARide() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.connection = IntervalsConnection(athleteID: "x", athleteName: "X", apiKey: "k")
    #expect(SyncPolicy.shouldRefresh(lastDownload: nil, connected: true, rideActive: model.isBusy))
    await model.downloadWorkouts()
    #expect(model.workoutImportReport?.contains("Preview mode") == true)
    await model.start(training: try .freeRide(watts: 100))
    #expect(!SyncPolicy.shouldRefresh(lastDownload: nil, connected: true, rideActive: model.isBusy))
    await model.refreshWorkoutsIfNeeded()
    #expect(!model.downloadingWorkouts)
    model.stop()
}
