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
    case dashWorkout = "dash-workout"
    case dashWorkoutRecoveryNext = "dash-workout-recovery-next"
    case dashWorkoutCountdown = "dash-workout-countdown"
    case dashWorkoutPaused = "dash-workout-paused"
    case dashWorkoutScaled = "dash-workout-scaled"
    case dashFtpWarmup = "dash-ftp-warmup"
    case dashFtpRamp = "dash-ftp-ramp"
    case dashFtpLowCadence = "dash-ftp-low-cadence"
    case dashFtpEnding = "dash-ftp-ending"
    case dashFtpCooldown = "dash-ftp-cooldown"
    case dashFreeRide = "dash-free-ride"
    case dashFreeRideResistance = "dash-free-ride-resistance"
    case dashMoreMetrics = "dash-more-metrics"
    case dashSignalLost = "dash-signal-lost"
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
        if scenario.rawValue.hasPrefix("dash-") {
            try await dashboard(scenario, model: model, rider: alex)
            return
        }
        switch scenario {
        case .dashWorkout, .dashWorkoutRecoveryNext, .dashWorkoutCountdown, .dashWorkoutPaused, .dashWorkoutScaled, .dashFtpWarmup, .dashFtpRamp, .dashFtpLowCadence, .dashFtpEnding, .dashFtpCooldown, .dashFreeRide, .dashFreeRideResistance, .dashMoreMetrics, .dashSignalLost: break

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

    private static func dashboard(_ scenario: PreviewScenario, model: AppModel, rider: RiderProfile) async throws {
        try model.resetPreview { try $0.saveProfile(rider) }
        model.demoMode = true; model.mockSpeed = 1
        let recoveryNext = scenario == .dashWorkoutRecoveryNext
        let isFTP = scenario.rawValue.contains("ftp-")
        let isFree = scenario.rawValue.contains("free-ride") || scenario == .dashMoreMetrics
        let steps: [TrainingPlan.Step] = [
            .init("Warm-up", seconds: 900, watts: 165), .init("Sweet spot 1 of 3", seconds: 720, watts: 225),
            .init("Recovery", seconds: 300, watts: 125), .init("Sweet spot 2 of 3", seconds: 720, watts: 225),
            .init(recoveryNext ? "Recovery 2 of 3" : "Recovery", seconds: 300, watts: 125), .init("Sweet spot 3 of 3", seconds: 720, watts: 225), .init("Cool-down", seconds: 300, watts: 125)]
        let plan: TrainingPlan? = isFTP ? nil : isFree ? try .freeRide(watts: 180) : try TrainingPlan(kind: .workout, name: "Sweet spot 3×12 min @ 90 %", ftpWatts: 250, steps: steps)
        if let plan { await model.start(training: plan) } else { await model.start() }
        model.mockPaused = true
        let config = try SessionConfiguration(warmupSeconds: isFTP ? 600 : 0, manualWarmupPower: 125, cooldownSeconds: 180)
        var engine = RideEngine(configuration: config, isDemo: true, training: plan)
        let end: Int = isFTP ? (scenario == .dashFtpWarmup ? 348 : 1048) : isFree ? 1458 : scenario == .dashWorkoutCountdown ? 2632 : recoveryNext ? 2750 : 2238
        for second in 0...end {
            let time = Double(second)
            let cadence: Double = scenario == .dashFtpLowCadence && second >= end - 2 ? 54 : scenario == .dashFtpEnding && second >= end - 2 ? 40 : isFTP ? (scenario == .dashFtpWarmup ? 88 : 84) : isFree ? (second < end - 3 ? 89 : 90) : recoveryNext ? 86 : 88
            let rampWatts = Double(100 + max(0, (second - 600) / 12) * 5)
            let freePower = 179.8 + 8 * sin(time * .pi / 90) + 3 * sin(time * .pi / 23.5)
            let workoutPower = recoveryNext && second >= 2640 ? 127.0 : 228.0
            let watts: Double = isFTP ? second < 600 ? 123 : second >= end - 3 ? 281 : rampWatts : isFree ? second >= end - 3 ? 183 : second == 300 ? 312 : freePower : workoutPower
            let workoutStart = second < 900 ? 0 : second < 1620 ? 900 : second < 1920 ? 1620 : 1920
            let workoutDuration = second < 900 ? 900.0 : second < 1620 ? 720.0 : second < 1920 ? 300.0 : 720.0
            let heartStart = second < 900 ? 115.0 : second < 1620 ? 127.0 : second < 1920 ? 147.0 : 127.0
            let heartEnd = second < 900 ? 127.0 : second < 1620 ? 147.0 : second < 1920 ? 127.0 : 147.0
            let fraction = min(1, Double(second - workoutStart) / workoutDuration)
            let rise = second < 900 ? (1 - cos(fraction * .pi)) / 2 : 1 - pow(1 - fraction, 7.0 / 3)
            var workoutHeart = Int((heartStart + (heartEnd - heartStart) * rise).rounded())
            if recoveryNext && second >= 1920 && second < 2640 {
                let progress = Double(second - 1920) / 720
                workoutHeart = Int((127 + 23 * (1 - pow(1 - progress, 16.0 / 7))).rounded())
            } else if recoveryNext && second >= 2640 {
                let progress = min(1, Double(second - 2640) / 300)
                workoutHeart = Int((150 - 24 * (1 - pow(1 - progress, 6))).rounded())
            }
            let heart = isFTP ? second < 600 ? 112 : 171 : isFree ? second >= end - 4 ? 131 : second == 300 ? 144 : Int((128 + 4 * sin(time * .pi / 90) + 3 * sin(time * .pi / 45)).rounded()) : workoutHeart
            engine.receive(.init(time: time, power: watts, cadence: cadence, heartRate: heart, leftBalance: 49))
            engine.tick(at: time)
        }
        if scenario == .dashWorkoutPaused { _ = engine.pause(at: Double(end)) }
        if scenario == .dashWorkoutScaled { _ = engine.setIntensity(110, at: Double(end)) }
        if scenario == .dashFreeRideResistance { _ = engine.switchFreeRide(resistance: 40, watts: 180, at: Double(end)) }
        if scenario == .dashFtpCooldown { engine.finishRamp(at: Double(end)) }
        model.installDashboardPreview(engine, elapsed: Double(end) + (scenario == .dashSignalLost ? 3 : 0))
        model.previewDashboardMore = scenario == .dashMoreMetrics
        // The references contain independent illustrative totals (including a header clock that
        // differs from the ride clock). Seed those presentation-only figures explicitly, rather
        // than changing recorded samples, the simulation or any engine rule to manufacture them.
        model.previewDashboardReadings = ["headerClock": "18:42"]
        if isFree {
            model.previewDashboardReadings.merge(["Normalized": "184", "Max power": "312", "Work": "262", "Calories": "261", "Speed": "30.6", "Distance": "12.4", "Balance": "49/51", "Max HR": "144", "NP": "184"]) { _, new in new }
        }
        if isFTP && scenario != .dashFtpWarmup { model.previewDashboardReadings["bestMinute"] = "272" }
        model.rideVisualPlacement = .off
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
