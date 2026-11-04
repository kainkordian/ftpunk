import Foundation
import FTPunkDomain
import FTPunkIntegrations
import FTPunkStorage

/// Named UI states for screenshots and tests (`--scenario <name>`). Scenarios only run against an
/// in-memory preview store: `AppModel.resetPreview` refuses a persistent one.
enum PreviewScenario: String, CaseIterable, Identifiable {
    case firstLaunch = "first-launch", homeToday = "home-today", homeNotConnected = "home-not-connected"
    case homeNoFTP = "home-no-ftp", homeRetestDue = "home-retest-due", library
    case preflightBlocked = "preflight-blocked", rideWarmup = "ride-warmup", rideRamp = "ride-ramp"
    case rideRampLowCadence = "ride-ramp-low-cadence", rideCooldown = "ride-cooldown"
    case resultNewFTP = "result-new-ftp", resultInterrupted = "result-interrupted", resultUploadPrompt = "result-upload-prompt"
    case workoutRunning = "workout-running", workoutPaused = "workout-paused"
    case freeRide = "free-ride", resistance
    case progressTwoRiders = "progress-two-riders"
    case visualRampThreshold = "visual-ramp-threshold", visualWorkoutVO2 = "visual-workout-vo2", visualRecovery = "visual-recovery"
    case visualSummit = "visual-summit", visualPaused = "visual-paused", visualOff = "visual-off"
    case settingsDevices = "settings-devices", settingsIntervals = "settings-intervals", workoutDetail = "workout-detail"
    case visualHero = "visual-hero", visualSprint = "visual-sprint", settingsIntervalsConnected = "settings-intervals-connected"
    case builderBlocks = "builder-blocks", builderText = "builder-text"
    var id: String { rawValue }

    /// The requested scenario, only when the process is an explicit in-memory preview.
    static func requested(arguments: [String] = ProcessInfo.processInfo.arguments) -> PreviewScenario? {
        guard arguments.contains("--debug-preview"), let index = arguments.firstIndex(of: "--scenario"),
              arguments.indices.contains(index + 1) else { return nil }
        return PreviewScenario(rawValue: arguments[index + 1])
    }
    /// Scenarios for the whole matrix, or a single one.
    static func requestedList(arguments: [String] = ProcessInfo.processInfo.arguments) -> [PreviewScenario] {
        if arguments.contains("--scenario-matrix") { return allCases }
        return requested(arguments: arguments).map { [$0] } ?? []
    }
}

@MainActor enum PreviewScenarios {

    static func apply(_ scenario: PreviewScenario, to model: AppModel) async throws {
        let alex = PreviewFixtures.rider()
        switch scenario {
        case .firstLaunch:
            try model.resetPreview()
            model.onboardingPending = true
        case .homeToday, .library:
            try model.resetPreview { store in
                try store.saveProfile(alex)
                try store.saveWorkouts(try intervalsFixtures(for: alex))
            }
            model.connection = IntervalsConnection(athleteID: "preview", athleteName: "Preview athlete", apiKey: "preview-only")
            if scenario == .library { model.homeFocus = .library }
        case .homeNotConnected:
            try model.resetPreview { try $0.saveProfile(alex) }
        case .homeNoFTP:
            let noFTP = PreviewFixtures.rider(ftp: nil)
            try model.resetPreview { try $0.saveProfile(noFTP) }
            model.ftpSelection = "none"
        case .homeRetestDue:
            let old = PreviewFixtures.rider(daysAgo: 63)
            try model.resetPreview { try $0.saveProfile(old) }
        case .preflightBlocked:
            try model.resetPreview { try $0.saveProfile(alex) }
            model.demoMode = false
            model.openPreflight(.ftpTest)
        case .rideWarmup:
            try await startRamp(model, rider: alex)
            model.advanceMock(seconds: 4); model.mockPaused = true
        case .rideRamp, .rideRampLowCadence:
            try await startRamp(model, rider: alex)
            model.skipMockWarmup(); model.advanceMock(seconds: 95)
            if scenario == .rideRampLowCadence {
                // Power stays at the current step's target (a rider who holds the watts but whose cadence has
                // dropped), so the low-cadence guard is the only thing that looks wrong.
                model.manualMockValues = true
                model.mockPower = Double(model.engine?.targetPower ?? 150); model.mockCadence = 54
                model.advanceMock(seconds: 3)
            }
            model.mockPaused = true
        case .rideCooldown:
            try await startRamp(model, rider: alex)
            model.skipMockWarmup()
            while model.engine?.phase != .cooldown && model.isActive { model.advanceMock(seconds: 0.5) }
            model.mockPaused = true
        case .resultNewFTP:
            try model.resetPreview { try $0.saveProfile(alex) }
            try model.showFinished(PreviewFixtures.finishedRampEngine(for: alex, daysAgo: 0, scale: 1.0))
        case .resultUploadPrompt:
            // The finished test of a rider with an Intervals.icu connection: the consent sheet opens by itself.
            try model.resetPreview { try $0.saveProfile(alex) }
            model.connections[alex.id] = IntervalsConnection(athleteID: "preview", athleteName: "Preview athlete", apiKey: "preview-only")
            let finished = try PreviewFixtures.finishedRampEngine(for: alex, daysAgo: 0, scale: 1.0)
            try model.showFinished(finished)
            model.askToUploadAfterRide(finished.session)
        case .resultInterrupted:
            try await startRamp(model, rider: alex)
            model.skipMockWarmup(); model.advanceMock(seconds: 100)
            model.simulateTrainerDisconnect()
        case .workoutRunning, .workoutPaused:
            try model.resetPreview { try $0.saveProfile(alex) }
            model.demoMode = true
            let plan = try definition("sweet-spot-3x10").plan(ftp: 250)
            await model.start(training: plan)
            model.advanceMock(seconds: 760)
            if scenario == .workoutPaused { model.pauseTraining() }
            model.mockPaused = true
        case .freeRide:
            try model.resetPreview { try $0.saveProfile(alex) }
            model.demoMode = true
            await model.start(training: try .freeRide(watts: 150))
            model.advanceMock(seconds: 60); model.mockPaused = true
        case .resistance:
            try model.resetPreview { try $0.saveProfile(alex) }
            model.demoMode = true
            await model.start(training: try .resistanceRide(level: 100))
            model.advanceMock(seconds: 45); model.mockPaused = true
        case .progressTwoRiders:
            try model.resetPreview { try PreviewFixtures.seed($0, demo: false) }
            model.destination = .progress
        case .visualRampThreshold:
            // Ride until the ramp target reaches 250 W, 100 % of Alex's FTP (step 31), then let the mock power settle.
            try await startRamp(model, rider: alex)
            model.skipMockWarmup()
            while (model.engine?.targetPower ?? 0) < 250 && model.isActive { model.advanceMock(seconds: 2) }
            model.advanceMock(seconds: 5); model.mockPaused = true
        case .visualWorkoutVO2:
            // Six seconds before the second VO2max effort ends, so the billboard previews the recovery district.
            try await startWorkout(model, rider: alex, id: "vo2max-5x3", seconds: 1134)
        case .visualRecovery:
            try await startWorkout(model, rider: alex, id: "vo2max-5x3", seconds: 840)
        case .visualPaused:
            try await startWorkout(model, rider: alex, id: "vo2max-5x3", seconds: 1000, pause: true)
        case .visualSummit:
            try await startRamp(model, rider: alex)
            model.skipMockWarmup()
            while model.engine?.phase != .cooldown && model.isActive { model.advanceMock(seconds: 0.5) }
            model.mockPaused = true
        case .settingsDevices, .settingsIntervals:
            try model.resetPreview { try $0.saveProfile(alex) }
            model.demoMode = false
            model.destination = .settings
            model.previewSettingsAnchor = scenario == .settingsDevices ? SettingsGroup.devices.rawValue : SettingsGroup.intervals.rawValue
        case .workoutDetail:
            try model.resetPreview { try $0.saveProfile(alex) }
            // Set after the reset (the earlier attempt raced it). Home presents the real sheet; the Mac walkthrough also renders it off screen.
            model.previewWorkoutDetail = .classic("vo2max-5x3")
        case .builderBlocks, .builderText:
            try model.resetPreview { try $0.saveProfile(alex) }
            // After the reset; Home presents the builder from this request.
            var state = BuilderState(workout: sampleWorkout(for: alex))
            if scenario == .builderText { state.switchTo(.text) }
            model.builder = BuilderRequest(state: state, isNew: false, mode: state.mode)
        case .settingsIntervalsConnected:
            // A fake connection and seeded sync state: the sync rows without network or Keychain access.
            let synced = PreviewFixtures.rider(weightKG: 71, ftp: 230, daysAgo: 1, source: "Intervals.icu")
            try model.resetPreview { try $0.saveProfile(synced) }
            model.demoMode = false
            model.connection = IntervalsConnection(athleteID: "preview", athleteName: "Preview athlete", apiKey: "preview-only")
            model.athleteSync = AthleteSyncSettings(enabled: true, lastSynced: Date().addingTimeInterval(-3600),
                                                    state: AthleteSyncState(lastSeenFTP: 230, lastSeenWeight: 71))
            model.athleteSyncNote = "FTP 230 W and weight 71.0 kg updated from Intervals.icu"
            model.destination = .settings
            model.previewSettingsAnchor = SettingsGroup.intervals.rawValue
        case .visualHero:
            try await startWorkout(model, rider: alex, id: "vo2max-5x3", seconds: 1134)
            model.rideVisualPlacement = .hero
        case .visualSprint:
            // Free ERG with a manual 650 W burst: above 7 W/kg for the 75 kg fixture rider, so the rider stands.
            try model.resetPreview { try $0.saveProfile(alex) }
            model.demoMode = true; model.mockSpeed = 1
            await model.start(training: try .freeRide(watts: 200))
            model.advanceMock(seconds: 30)
            model.manualMockValues = true; model.mockPower = 650; model.mockCadence = 110
            model.advanceMock(seconds: 4); model.mockPaused = true
        case .visualOff:
            try await startRamp(model, rider: alex)
            model.skipMockWarmup(); model.advanceMock(seconds: 95)
            model.rideVisualEnabled = false; model.mockPaused = true
        }
    }

    /// A workout with every kind of block: constant % FTP, a ramp, a repeat, and a watts step.
    private static func sampleWorkout(for rider: RiderProfile) -> CustomWorkout {
        CustomWorkout(riderID: rider.id, name: "Over-unders and a sprint", category: .overUnders, blocks: [
            .step(.init(name: "Warm-up", seconds: 600, start: .percentFTP(0.5))),
            .repeats(count: 4, steps: [.init(name: "Over", seconds: 180, start: .percentFTP(1.05)), .init(name: "Under", seconds: 120, start: .percentFTP(0.9))]),
            .step(.init(name: "Recovery", seconds: 300, start: .percentFTP(0.55))),
            .step(.init(name: "Sprint", seconds: 20, start: .watts(650))),
            .step(.init(name: "Cool-down", seconds: 300, start: .percentFTP(0.6), end: .percentFTP(0.4)))
        ])
    }

    private static func definition(_ id: String) throws -> WorkoutDefinition {
        guard let value = WorkoutLibrary.definition(id: id) else { throw ArchiveError.invalid("Unknown workout \(id)") }
        return value
    }

    private static func startRamp(_ model: AppModel, rider: RiderProfile) async throws {
        try model.resetPreview { try $0.saveProfile(rider) }
        model.demoMode = true; model.quickDebugTest = false
        model.warmupMinutes = 1; model.cooldownMinutes = 3; model.mockSpeed = 1
        await model.start()
    }

    private static func startWorkout(_ model: AppModel, rider: RiderProfile, id: String, seconds: Double, pause: Bool = false) async throws {
        try model.resetPreview { try $0.saveProfile(rider) }
        model.demoMode = true; model.mockSpeed = 1
        await model.start(training: try definition(id).plan(ftp: 250))
        model.advanceMock(seconds: seconds)
        if pause { model.pauseTraining() }
        model.mockPaused = true
    }

    /// Calendar entries for the Today, Upcoming and My workouts sections, plus one older cache entry without a date.
    private static func intervalsFixtures(for rider: RiderProfile) throws -> [CachedWorkout] {
        let calendar = Calendar.current
        func day(_ offset: Int) -> String { ScheduledDate.string(for: calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()) }
        func plan(_ id: String, _ name: String) throws -> TrainingPlan {
            let base = try definition(id).plan(ftp: 250)
            return try TrainingPlan(kind: .workout, name: name, ftpWatts: 250, steps: base.steps)
        }
        func intervals(_ number: Int, _ name: String, _ base: String, _ offset: Int?) throws -> CachedWorkout {
            CachedWorkout(id: "intervals:preview:\(rider.id.uuidString.lowercased()):\(number)", riderID: rider.id, source: "Intervals.icu · \(name)",
                          plan: try plan(base, name), scheduledDate: offset.map(day))
        }
        return [
            try intervals(1001, "Sweet spot 3×12", "sweet-spot-3x10", 0),
            try intervals(1002, "Endurance with tempo", "tempo-3x10", 1),
            try intervals(1003, "Threshold 2×20", "threshold-2x20", 4),
            try intervals(1004, "Older calendar entry", "endurance-60", nil),
            CachedWorkout(riderID: rider.id, source: "Imported JSON", plan: try plan("over-unders-3x9", "Club over-unders"))
        ]
    }
}
