import Foundation
import FTPunkDomain
import FTPunkDevices
import FTPunkStorage

/// Presentation-facing state derived from the coordinator. Pure rules live in `FTPunkDomain`.
extension AppModel {
    /// Why Start is disabled for this kind of ride, or nil when it can start.
    func startBlocker(for kind: RideKindID, durationsValid: Bool = true, needsFTP: Bool = false, plan: TrainingPlan? = nil, intensity: Int = 100) -> StartBlocker? {
        var readiness = StartReadiness(kind: kind)
        readiness.isMock = demoMode
        readiness.isFinishing = isFinishing
        readiness.isBusy = isBusy && !isFinishing
        readiness.trainerConnected = bluetooth.names[.trainer] != nil
        readiness.trainerControlReady = bluetooth.trainerReady
        readiness.powerRangeKnown = bluetooth.powerRange != nil
        readiness.matchingChoicePending = powerMatchingPrompt != nil
        readiness.powerSource = powerSource
        readiness.freshSelectedPower = bluetooth.measurements.hasFreshPower(from: powerSource, at: ProcessInfo.processInfo.systemUptime)
        readiness.supportsResistance = bluetooth.supportsResistance
        readiness.durationsValid = durationsValid
        readiness.needsFTP = needsFTP
        if let plan, plan.resistance == nil, !demoMode, let range = bluetooth.powerRange {
            readiness.targetsInRange = plan.supports(intensity: intensity, minimum: range.minimum, maximum: range.maximum)
                && plan.steps.allSatisfy { range.quantized($0.watts) > 0 && range.quantized($0.endWatts ?? $0.watts) > 0 }
        }
        return StartBlocker.blocker(for: readiness)
    }

    var deviceSummary: DeviceSummary {
        .make(mock: demoMode, trainerConnected: bluetooth.names[.trainer] != nil, trainerReady: bluetooth.trainerReady,
              powerSource: powerSource, externalMeterConnected: bluetooth.names[.pedals] != nil,
              heartRateConnected: bluetooth.names[.heartRate] != nil)
    }

    /// FTP that library workouts resolve against: the rider's saved current FTP, then the setup selection.
    var libraryFTP: Double? { profile.currentFTP?.watts ?? selectedFTP?.watts }
    var riderWeight: Double? { number(weight).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }

    /// Saves an FTP as the rider's current value. Never changes the setup selection silently.
    @discardableResult func setCurrentFTP(_ text: String) -> Bool {
        guard !isBusy else { return false }
        guard let value = number(text), value.isFinite, value > 0, value <= 32767 else {
            errorMessage = ConfigurationError.invalidFTP.localizedDescription; return false
        }
        let entry = FTPEntry(watts: value)
        profile.ftpHistory.insert(entry, at: 0); profile.currentFTPID = entry.id
        guard persistProfile() else { return false }
        ftpSelection = entry.id.uuidString; manualFTP = ""
        return true
    }

    // MARK: Workouts

    /// A workout ready to show or start. `plan` is nil for a classic until the rider has an FTP.
    struct WorkoutDetail {
        let ref: WorkoutRef
        let title: String
        let source: String
        let category: WorkoutCategory?
        let duration: Double
        let plan: TrainingPlan?
        /// A shape-only plan (at 100 W) for drawing a profile before the rider has an FTP.
        let previewPlan: TrainingPlan?
        let cached: CachedWorkout?
        var custom: CustomWorkout?
        var needsFTP: Bool { plan == nil }
    }

    func workoutDetail(for ref: WorkoutRef) -> WorkoutDetail? {
        switch ref {
        case .classic(let id):
            guard let definition = WorkoutLibrary.definition(id: id) else { return nil }
            return WorkoutDetail(ref: ref, title: definition.name, source: "Built-in", category: definition.category, duration: definition.duration,
                                 plan: libraryFTP.flatMap { try? definition.plan(ftp: $0) }, previewPlan: try? definition.plan(ftp: 100), cached: nil)
        case .cached(let id):
            guard let workout = workoutLibrary.first(where: { $0.id == id }) else { return nil }
            return WorkoutDetail(ref: ref, title: workout.plan.name, source: workout.isFromIntervals ? "Intervals.icu" : "Imported", category: nil,
                                 duration: workout.plan.duration, plan: workout.plan, previewPlan: workout.plan, cached: workout)
        case .custom(let id):
            guard let workout = customWorkout(id: id) else { return nil }
            return WorkoutDetail(ref: ref, title: workout.name, source: "My workout", category: workout.category, duration: workout.duration,
                                 plan: try? workout.plan(ftp: libraryFTP), previewPlan: try? workout.plan(ftp: libraryFTP ?? 100), cached: nil, custom: workout)
        }
    }

    /// Starts a library workout at the intensity chosen in the pre-flight.
    func startWorkout(_ ref: WorkoutRef) async {
        guard let plan = workoutDetail(for: ref)?.plan else { errorMessage = StartBlocker.needsFTP.reason; return }
        await start(training: plan)
        if isActive, preflightIntensity != 100 { adjustIntensity(by: preflightIntensity - 100) }
        preflightIntensity = 100
    }

    // MARK: Onboarding

    /// Saves the first rider. A blank FTP or weight is fine; "not sure" leads to the FTP test.
    @discardableResult func completeOnboarding(name: String, weight: String, ftp: String, thenTest: Bool) -> Bool {
        riderName = name; self.weight = weight
        guard saveRiderDetails() else { return false }
        if !ftp.trimmingCharacters(in: .whitespaces).isEmpty, !setCurrentFTP(ftp) { return false }
        onboardingPending = false
        if thenTest { openPreflight(.ftpTest) }
        return true
    }
    func skipOnboarding() { if persistProfile() { onboardingPending = false } }

    /// The recommended ramp for the rider's weight, until they pick another.
    var recommendedProtocol: ProtocolRecommendation { .recommend(weightKG: riderWeight) }
    func applyRecommendedProtocol() { if !presetChosen { preset = recommendedProtocol.preset } }
    func choosePreset(_ value: RampPreset) { preset = value; presetChosen = true }

    /// Leaves the cockpit. A finished ride's result remains in Progress.
    func closeCockpit() {
        cockpitPresented = false; destination = .home; preflightPath = []
        if !isBusy { engine = nil }
    }

    func openPreflight(_ kind: RideKind) {
        guard !isBusy else { return }
        destination = .home
        preflightPath = [kind]
    }

    /// Preview only: shows a finished, saved recording as the result screen.
    func showFinished(_ finished: RampEngine) throws {
        guard preview else { throw StoreError.persistentStoreProtected }
        try store.save(finished.session); try reload()
        engine = finished; elapsed = finished.session.endedAtOffset ?? 0
        cockpitPresented = true
    }

    /// Preview only: replaces the in-memory store contents and resets presentation state.
    func resetPreview(seed: (LocalStore) throws -> Void = { _ in }) throws {
        guard preview, store.isInMemory else { throw StoreError.persistentStoreProtected }
        if isStarting || isActive { stop() }
        engine = nil; mockPaused = false
        try store.eraseAllForPreview()
        try seed(store)
        let saved = try store.profiles()
        riders = saved.isEmpty ? [RiderProfile()] : saved
        profile = riders[0]
        try reload()
        selectRider(profile.id)
        previewWorkoutDetail = nil; previewSettingsAnchor = nil; builder = nil
        connections = [:]; athleteSync = AthleteSyncSettings(); errorMessage = nil; workoutImportReport = nil; uploadConsent = nil
        destination = .home; cockpitPresented = false; preflightPath = []
        preset = .standard; presetChosen = false; powerSource = .trainer; warmupMinutes = 10; cooldownMinutes = 3
        automaticWarmup = true; manualWarmup = "100"; quickDebugTest = true; setupStep = 0
        freeRideWatts = 100; resistanceLevel = 0; preflightIntensity = 100; homeFocus = nil; onboardingPending = false; rideVisualPlacement = .strip; manualMockValues = false
    }
}

/// What the FTP card shows. `date` is nil for a value entered for one ride and never saved.
struct FTPSummary {
    let watts: Double
    let date: Date?
    let source: String
    let wattsPerKG: Double?
    var isRamp: Bool { source == "Ramp test" }
    var retest: RetestAdvice { RetestAdvice.evaluate(lastTest: date) }
    /// The card's single status line, for example "Tested 12 Oct · 3 weeks ago".
    var statusLine: FTPStatusLine { FTPStatusLine.make(date: date, isRamp: isRamp, source: source) }
}

extension AppModel {
    var ftpSummary: FTPSummary? {
        let weight = riderWeight
        if let entry = profile.currentFTP {
            return FTPSummary(watts: entry.watts, date: entry.date, source: entry.source, wattsPerKG: weight.map { entry.watts / $0 })
        }
        if let entry = selectedFTP {
            return FTPSummary(watts: entry.watts, date: nil, source: "Entered for this ride", wattsPerKG: weight.map { entry.watts / $0 })
        }
        return nil
    }
}
