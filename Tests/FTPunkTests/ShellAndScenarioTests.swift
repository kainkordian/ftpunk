import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

@Test func scenarioArgumentIsHonouredOnlyForExplicitInMemoryPreviews() {
    #expect(PreviewScenario.requested(arguments: ["FTPunk", "--scenario", "ride-ramp"]) == nil)
    #expect(PreviewScenario.requested(arguments: ["FTPunk", "--debug-preview", "--scenario", "ride-ramp"]) == .rideRamp)
    #expect(PreviewScenario.requested(arguments: ["FTPunk", "--debug-preview", "--scenario", "nonsense"]) == nil)
    #expect(PreviewScenario.requested(arguments: ["FTPunk", "--debug-preview", "--scenario"]) == nil)
    #expect(PreviewScenario.requestedList(arguments: ["FTPunk", "--debug-preview", "--scenario-matrix"]) == PreviewScenario.allCases)
}

@Test func scenarioNamesMatchThePlan() {
    let expected: Set<String> = ["first-launch", "home-today", "home-not-connected", "home-no-ftp", "home-retest-due", "library",
        "preflight-blocked", "ride-warmup", "ride-ramp", "ride-ramp-low-cadence", "ride-cooldown", "result-new-ftp", "result-interrupted", "result-upload-prompt",
        "workout-running", "workout-paused", "free-ride", "resistance", "progress-two-riders",
        "visual-ramp-threshold", "visual-workout-vo2", "visual-recovery", "visual-summit", "visual-paused", "visual-off",
        "settings-devices", "settings-intervals", "workout-detail", "visual-hero", "visual-sprint", "settings-intervals-connected", "builder-blocks", "builder-text"]
    #expect(Set(PreviewScenario.allCases.map(\.rawValue)) == expected)
}

@Test @MainActor func scenariosNeverTouchAPersistentStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistent = try LocalStore(url: directory.appendingPathComponent("store.sqlite"))
    try persistent.saveProfile(RiderProfile(name: "Keep me"))
    #expect(throws: (any Error).self) { try persistent.eraseAllForPreview() }
    let model = try AppModel(store: persistent, preview: true)
    #expect(throws: (any Error).self) { try model.resetPreview() }
    #expect(try persistent.profiles().map(\.name) == ["Keep me"])
}

@MainActor private func visualState(_ model: AppModel) throws -> RideVisualState {
    RideVisualState.make(RideVisualInput(model: model, engine: try #require(model.engine)))
}

@Test @MainActor func everyScenarioAppliesToAFreshInMemoryPreview() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    for scenario in PreviewScenario.allCases {
        try await PreviewScenarios.apply(scenario, to: model)
        #expect(!model.riders.isEmpty, "\(scenario.rawValue)")
        switch scenario {
        case .rideWarmup: #expect(model.engine?.phase == .warmup && model.cockpitPresented)
        case .rideRamp: #expect(model.engine?.phase == .ramp && model.cockpitPresented)
        case .rideRampLowCadence:
            #expect(model.engine?.phase == .ramp && model.cockpitPresented)
            // Cadence is low, power is not: the seeded watts follow the step target instead of overshooting it.
            let sample = try #require(model.engine?.session.samples.last)
            let target = try #require(model.engine?.targetPower)
            #expect(abs((sample.power ?? 0) - Double(target)) <= 25, "power \(sample.power ?? -1) W against a \(target) W target")
            #expect((sample.cadence ?? 100) < 60)
        case .rideCooldown: #expect(model.engine?.phase == .cooldown)
        case .resultNewFTP:
            #expect(model.engine?.session.isDemo == false && model.engine?.session.result != nil && !model.isActive)
            #expect(model.cockpitPresented)
        case .workoutDetail:
            #expect(model.previewWorkoutDetail == .classic("vo2max-5x3"))   // set after the reset; Home clears it once the sheet shows
        case .settingsIntervalsConnected:
            #expect(model.connection?.athleteName == "Preview athlete" && model.athleteSync.state.lastSeenFTP == 230 && model.profile.currentFTP?.watts == 230)
            #expect(model.destination == .settings && model.athleteSyncNote?.contains("FTP 230 W") == true)
        case .builderBlocks, .builderText:
            let request = try #require(model.builder)
            #expect(request.state.mode == (scenario == .builderBlocks ? .blocks : .text) && request.state.canSave && !request.isNew)
        case .resultUploadPrompt:
            #expect(model.uploadConsent?.accountName == "Preview athlete" && model.cockpitPresented)
            #expect(try model.store.uploadJobs().isEmpty) // asking never uploads
        case .resultInterrupted: #expect(model.engine?.phase == .interrupted)
        case .workoutRunning: #expect(model.engine?.phase == .riding && model.engine?.session.training?.kind == .workout)
        case .workoutPaused: #expect(model.engine?.phase == .paused)
        case .freeRide: #expect(model.engine?.session.training?.kind == .freeRide && model.engine?.resumeResistance == nil)
        case .resistance: #expect(model.engine?.resumeResistance == 100)
        case .visualRampThreshold:
            #expect(model.engine?.phase == .ramp && model.cockpitPresented && model.rideVisualEnabled)
            #expect(try visualState(model).zone == .threshold && visualState(model).level == 31)
        case .visualWorkoutVO2:
            #expect(model.engine?.phase == .riding && model.rideVisualEnabled)
            #expect(try visualState(model).zone == .vo2max && visualState(model).upcoming?.text == "NEXT 3:00 · 125 W")
        case .visualRecovery:
            #expect(try visualState(model).zone == .recovery && visualState(model).district.kind == .residential)
        case .visualSummit:
            #expect(model.engine?.phase == .cooldown)
            #expect(try visualState(model).world == .rooftop && visualState(model).sign?.kind == .finish)
        case .visualPaused:
            #expect(model.engine?.phase == .paused)
            #expect(try visualState(model).motion == .footDown && visualState(model).sign?.text == "PAUSED")
        case .visualOff: #expect(model.engine?.phase == .ramp && !model.rideVisualEnabled)
        case .homeNoFTP: #expect(model.ftpSummary == nil)
        case .homeRetestDue: #expect(model.ftpSummary?.retest.isDue == true)
        case .progressTwoRiders: #expect(model.riders.count == 2 && model.history.count == 3 && model.history.allSatisfy { !$0.isDemo })
        case .firstLaunch: #expect(model.onboardingPending && model.history.isEmpty)
        default: break
        }
    }
    // Scenarios start rides on the in-memory preview store only, and no ride carries story fields any more.
    #expect(model.history.allSatisfy { $0.adventureEnabled == nil && $0.eligibleMilliseconds == nil })
}

@Test @MainActor func quickRideFlowKeepsTheCockpitSeparateFromTheTabs() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    #expect(model.destination == .home && !model.cockpitPresented)
    model.openPreflight(.freeERG)
    #expect(model.preflightPath == [.freeERG])
    await model.start(training: try .freeRide(watts: 120))
    #expect(model.cockpitPresented && model.preflightPath.isEmpty && model.isActive)
    model.cockpitPresented = false // minimise: the ride keeps running behind the live-ride bar
    #expect(model.isActive && model.engine != nil)
    model.openPreflight(.ftpTest) // cannot start a second ride
    #expect(model.preflightPath.isEmpty)
    model.stop()
    model.closeCockpit()
    #expect(!model.cockpitPresented && model.engine == nil && model.destination == .home)
}

@Test @MainActor func startBlockerFollowsTheLiveDeviceState() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    #expect(model.startBlocker(for: .ftpTest) == nil)
    #expect(model.readyToStart)
    model.demoMode = false
    #expect(model.startBlocker(for: .ftpTest) == .trainerMissing)
    #expect(!model.readyToStart)
    #expect(model.startBlocker(for: .ftpTest, durationsValid: false) == .invalidDurations)
    model.demoMode = true
    #expect(model.startBlocker(for: .workout, needsFTP: true) == .needsFTP)
    #expect(model.deviceSummary.trainer == .ready)
}

@Test @MainActor func ftpCardUsesTheSavedCurrentFTPAndSavingIsExplicit() throws {
    let store = try LocalStore(inMemory: true), model = try AppModel(store: store, preview: true)
    #expect(model.addRider(name: "Casey"))
    #expect(model.ftpSummary == nil)
    model.weight = "60"
    #expect(model.setCurrentFTP("240"))
    let summary = try #require(model.ftpSummary)
    #expect(summary.watts == 240 && summary.date != nil && summary.wattsPerKG == 4)
    #expect(model.libraryFTP == 240)
    #expect(try store.profiles().first { $0.name == "Casey" }?.currentFTP?.watts == 240)
    #expect(!model.setCurrentFTP("-5") && model.errorMessage != nil)
    #expect(!model.setCurrentFTP("abc"))
    #expect(model.profile.currentFTP?.watts == 240)
}
