import Foundation
import SwiftUI
import Observation
import Network
import AuthenticationServices
import FTPunkDomain
import FTPunkDevices
import FTPunkStorage
import FTPunkIntegrations
#if canImport(UIKit)
import UIKit
#endif

struct UploadConsent: Identifiable {
    var id: UUID { session.id }
    let session: TestSession
    let accountID: String
    let accountName: String
    /// The rider whose connection receives the upload: always the session's rider, never whoever is selected later.
    var riderID: UUID { session.riderID }
}

@MainActor @Observable final class AppModel {
    let bluetooth = BluetoothDevices()
    let store: LocalStore
    private let uploads: UploadWorker
    var profile: RiderProfile
    var riders: [RiderProfile]
    var riderName = ""
    var history: [TestSession] = []
    var jobs: [ActivityUploadJob] = []
    var engine: RampEngine?
    var elapsed = 0.0
    /// Preview scenarios can render the iPhone layout inside a Mac window.
    var previewPhoneLayout = false
    var previewTextSize: DynamicTypeSize?
    /// Preview scenarios only: the Settings group to show first, with the API key form open.
    var previewSettingsAnchor: String?
    /// Preview scenarios only: a workout whose detail sheet Home presents (and then clears), so the real sheet shows on iOS too.
    var previewWorkoutDetail: WorkoutRef?
    /// The workout builder, when it is open. Home presents it.
    var builder: BuilderRequest?
    /// The riders' own workouts (all riders; `myCustomWorkouts` is the selected rider's).
    var customWorkouts: [CustomWorkout] = []
    /// A first launch with no rider data shows a short setup step before Home.
    var onboardingPending = false
    /// Workout intensity chosen in the pre-flight, applied once the ride starts.
    var preflightIntensity = 100
    var intervalsHintDismissed = UserDefaults.standard.bool(forKey: "intervalsHintDismissed") {
        didSet { if !preview { UserDefaults.standard.set(intervalsHintDismissed, forKey: "intervalsHintDismissed") } }
    }
    /// Lets a scenario or link scroll Home to a section.
    var homeFocus: HomeSection?
    var destination: AppDestination = .home
    /// The ride cockpit fills the screen. Minimising it leaves the ride running behind the live-ride bar.
    var cockpitPresented = false
    var preflightPath: [RideKind] = []
    /// How the strip shows in the cockpits. A strip unless the rider chose otherwise; migrated from the earlier on/off
    /// toggle (and before that `showStelvioASCII`).
    var rideVisualPlacement = RideVisualPlacement.strip {
        didSet { if !preview { RideVisualPreference.savePlacement(rideVisualPlacement) } }
    }
    /// On/off view of `rideVisualPlacement`. Switching on restores the strip.
    var rideVisualEnabled: Bool {
        get { rideVisualPlacement != .off }
        set { rideVisualPlacement = newValue ? (rideVisualPlacement == .off ? .strip : rideVisualPlacement) : .off }
    }
    var freeRideWatts = 100
    var resistanceLevel = 0
    let catalog: WorkoutCatalog
    var workoutLibrary: [CachedWorkout] { catalog.cached }
    var downloadingWorkouts: Bool { catalog.downloading }
    var workoutImportReport: String? {
        get { catalog.report }
        set { catalog.report = newValue }
    }
    var readyForResistance: Bool {
        demoMode || (!isFinishing && bluetooth.trainerReady && bluetooth.supportsResistance && powerMatchingPrompt == nil && bluetooth.measurements.hasFreshPower(from: powerSource, at: ProcessInfo.processInfo.systemUptime))
    }
    var resistanceLimits: SupportedResistanceRange? {
        demoMode ? try? SupportedResistanceRange(minimum: 0, maximum: 1000, increment: 10) : bluetooth.supportsResistance ? bluetooth.resistanceRange : nil
    }
    var setupStep = 0
    var preset: RampPreset = .standard
    var powerSource: PowerSource = .trainer
    var powerMatchingEnabled = true {
        didSet {
            if !preview { UserDefaults.standard.set(powerMatchingEnabled, forKey: "powerMatchingEnabled") }
        }
    }
    var powerMatchingPrompt: String?
    /// Workouts and free rides pause when the rider stops pedalling and resume when they start again. Not used by the FTP test.
    var autoPauseEnabled = true {
        didSet { if !preview { UserDefaults.standard.set(autoPauseEnabled, forKey: "autoPauseEnabled") } }
    }
    @ObservationIgnored private var autoPause = AutoPause()
    /// This ride's estimate of the trainer's error. A new ride starts a new one; only `trainerWarmth` outlives it.
    private(set) var powerMatcher = PowerMatcher()
    /// Work the trainer has done since the app connected to it (reset by a new trainer connection).
    private(set) var trainerWarmth = TrainerWarmth()
    private var warmthConnection = 0
    private var matchLogPhase: WorkoutPhase?
    private var matchLogTime = 0.0
    var ftpSelection = "manual"
    var manualFTP = ""
    var weight = ""
    var warmupMinutes = 10
    var cooldownMinutes = 3
    var automaticWarmup = true
    var manualWarmup = "100"
    /// The protocol author's conservative figure. New tests always use it; older recordings keep their own factor.
    static let ftpFactor = 0.72
    /// True once the rider picked a ramp themselves; until then the weight-based recommendation applies.
    var presetChosen = false
    var demoMode = false
    private(set) var debugUnlocked = false
    private(set) var aboutTapCount = 0
    var mockScenario: MockScenario = .rampToExhaustion
    var mockSpeed = 12.0
    var quickDebugTest = true
    var mockPaused = false
    var manualMockValues = false
    var mockPower = 200.0
    var mockCadence = 88.0
    var mockHeartRate = 140.0
    private var ownership = SessionOwnership()
    private var preparingConfiguration: SessionConfiguration?
    var isStarting: Bool { ownership.phase == .starting }
    var isFinishing: Bool { ownership.phase == .finishing }
    var isBusy: Bool { ownership.isBusy || isActive }
    var errorMessage: String?
    /// One Intervals.icu connection per rider.
    var connections: [UUID: IntervalsConnection] = [:]
    /// The selected rider's connection. Switching rider switches the account everywhere.
    var connection: IntervalsConnection? {
        get { connections[profile.id] }
        set { connections[profile.id] = newValue }
    }
    @ObservationIgnored let credentials: any CredentialStoring
    /// Riders who turned off "Ask to upload after each ride" (it is on by default).
    var uploadPromptDisabled: Set<UUID> = []
    var apiKeyInput = ""
    var connecting = false
    /// FTP and weight sync choices for the connected Intervals.icu account (see AppModel+IntervalsSync).
    var athleteSync = AthleteSyncSettings()
    var athleteSyncNote: String?
    var athleteSyncNeedsReconnect = false
    var athleteSyncing = false
    var uploadConsent: UploadConsent?
    var heartRate: Int?
    private var heartRateTime: Double?
    var freshHeartRate: Int? {
        guard let heartRateTime, elapsed - heartRateTime <= 5 else { return nil }
        return heartRate
    }
    private var origin = 0.0
    private var lastWallTime = 0.0
    private var mockStream = MockRideStream()
    let preview: Bool
    private let signIn = IntervalsSignIn()
    private var timer: Task<Void, Never>?
    private var targetTask: Task<Void, Never>?
    private var trainingControlTask: Task<Void, Never>?
    private var trainerPaused = false
    var trainingTransition: String?
    private var lastAcknowledgedTarget: Int?
    private var lastAcknowledgedResistance: Int?
    private var commandStartedAt: Double?
    private var cooldownReleaseSent = false
    private var trainerStoppedForCooldown = false
    private var lastCheckpoint = -1.0
    private var finalizedID: UUID?
    private let network = NWPathMonitor()
    private var uploadRetry: Task<Void, Never>?
    #if os(macOS)
    @ObservationIgnored private var wakeActivity: NSObjectProtocol?
    #endif

    init(store: LocalStore, preview: Bool = false, credentials: (any CredentialStoring)? = nil, uploader: (any ActivityUploader)? = nil) throws {
        self.store = store; self.preview = preview; uploads = UploadWorker(repository: store, uploader: uploader ?? AppInfo.intervalsClient)
        self.credentials = credentials ?? (preview ? InMemoryCredentialVault() : CredentialVault())
        catalog = WorkoutCatalog(store: store, persistTimes: !preview)
        debugUnlocked = preview || UserDefaults.standard.bool(forKey: "debugUnlocked")
        // Previews always start with the strip on; real launches read (and migrate) the stored choice.
        rideVisualPlacement = preview ? .strip : RideVisualPreference.loadPlacement()
        if !preview { UserDefaults.standard.removeObject(forKey: "cyclepunkEnabled") } // the removed story's switch
        demoMode = preview
        autoPauseEnabled = preview ? true : (UserDefaults.standard.object(forKey: "autoPauseEnabled") as? Bool ?? true)
        powerMatchingEnabled = preview ? true : (UserDefaults.standard.object(forKey: "powerMatchingEnabled") as? Bool ?? true)
        try store.recoverInterruptedSessions()
        let savedRiders = try store.profiles()
        let availableRiders = savedRiders.isEmpty ? [RiderProfile()] : savedRiders
        riders = availableRiders
        let selectedID = preview ? nil : UserDefaults.standard.string(forKey: "selectedRiderID")
        profile = availableRiders.first(where: { $0.id.uuidString == selectedID }) ?? availableRiders[0]
        riderName = profile.name
        if let current = profile.currentFTP { ftpSelection = current.id.uuidString }
        if let kg = profile.weightKG { weight = String(kg) }
        if !preview {
            uploadPromptDisabled = Set((UserDefaults.standard.stringArray(forKey: Self.promptDisabledKey) ?? []).compactMap(UUID.init(uuidString:)))
        }
        try migrateLegacyConnection()
        try loadConnections()
        // Previous prototypes could queue automatically. New tests always ask first.
        for connection in connections.values { try uploads.cancelAutomaticUploads(accountID: connection.athleteID) }
        if preview { manualFTP = "250"; weight = "75" }
        try reload()
        loadAthleteSync()
        onboardingPending = !preview && savedRiders.isEmpty && history.isEmpty && workoutLibrary.isEmpty
        bluetooth.onExternalMeterReady = { [weak self] in self?.externalMeterReady(name: $0) }
        bluetooth.onReading = { [weak self] in self?.receive($0) }
        bluetooth.onDeviceFailure = { [weak self] role, reason in
            guard let self, self.isBusy, !self.demoMode else { return }
            guard let configuration = self.preparingConfiguration ?? self.engine?.session.configuration,
                  MeasurementRouting.isEssential(role, configuration: configuration) else { return }
            self.interrupt(reason)
        }
        network.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in await self?.flushUploads() } }
        }
        if !preview { network.start(queue: DispatchQueue(label: "FTPunk.network")) }
    }
    func externalMeterReady(name: String) {
        guard !isBusy else { return }
        powerSource = .externalPowerMeter
        powerMatchingPrompt = name
    }
    func choosePowerMatching(_ enabled: Bool) {
        guard !isBusy else { powerMatchingPrompt = nil; return }
        powerMatchingEnabled = enabled
        powerMatchingPrompt = nil
    }
    var isActive: Bool { engine?.phase.isActive == true }
    func tapAboutInfo() {
        guard !debugUnlocked else { return }
        aboutTapCount += 1
        if aboutTapCount == 10 {
            debugUnlocked = true
            if !isBusy { demoMode = true }
            if !preview { UserDefaults.standard.set(true, forKey: "debugUnlocked") }
        }
    }
    func hideDebugTools() {
        guard !isBusy else { return }
        demoMode = false; debugUnlocked = false; aboutTapCount = 0
        if !preview { UserDefaults.standard.set(false, forKey: "debugUnlocked") }
    }
    var activeSession: TestSession? { engine?.session }
    var oauthConfigured: Bool { IntervalsSignIn.configuration != nil }
    var selectedFTP: FTPEntry? {
        if ftpSelection == "manual" { return number(manualFTP).map { FTPEntry(watts: $0) } }
        return profile.ftpHistory.first { $0.id.uuidString == ftpSelection }
    }
    var selectedRiderID: UUID {
        get { profile.id }
        set { selectRider(newValue) }
    }
    func selectRider(_ id: UUID) {
        guard !isBusy, let rider = riders.first(where: { $0.id == id }) else { return }
        profile = rider; riderName = rider.name; presetChosen = false
        loadAthleteSync(); athleteSyncNote = nil; athleteSyncNeedsReconnect = false
        weight = rider.weightKG.map { String($0) } ?? ""
        manualFTP = ""
        ftpSelection = rider.currentFTPID?.uuidString ?? "manual"
        if !preview { UserDefaults.standard.set(id.uuidString, forKey: "selectedRiderID") }
    }
    func addRider(name: String) -> Bool {
        guard !isBusy else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { errorMessage = ConfigurationError.invalidRider.localizedDescription; return false }
        guard !riders.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "A rider with that name already exists. Select them or use a different name."; return false
        }
        let rider = RiderProfile(id: UUID(), name: name)
        do { try store.saveProfile(rider); riders.append(rider); selectRider(rider.id); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func saveRiderDetails() -> Bool {
        guard !isBusy else { return false }
        let name = riderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { errorMessage = ConfigurationError.invalidRider.localizedDescription; return false }
        guard !riders.contains(where: { $0.id != profile.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            errorMessage = "Another rider already uses that name. Use a distinct name to keep the history clear."; return false
        }
        if !weight.trimmingCharacters(in: .whitespaces).isEmpty,
           number(weight).map({ $0.isFinite && $0 > 0 }) != true {
            errorMessage = ConfigurationError.invalidWeight.localizedDescription; return false
        }
        profile.name = name; profile.weightKG = number(weight)
        return persistProfile()
    }
    func name(for riderID: UUID) -> String {
        riders.first(where: { $0.id == riderID })?.name ?? history.first(where: { $0.riderID == riderID })?.riderName ?? "You"
    }
    var warmupPreview: String {
        guard let config = try? configuration() else { return "Enter valid setup values" }
        return "\(config.warmupPower) W"
    }
    var readyToStart: Bool {
        guard !isFinishing else { return false }
        if demoMode { return true }
        return powerMatchingPrompt == nil && bluetooth.trainerReady && bluetooth.powerRange != nil && bluetooth.measurements.hasFreshPower(from: powerSource, at: ProcessInfo.processInfo.systemUptime)
    }
    var cadenceSource: CadenceSource {
        if demoMode { return powerSource == .trainer ? .trainer : .externalPowerMeter }
        return bluetooth.measurements.preferredCadence(for: powerSource, at: ProcessInfo.processInfo.systemUptime)
    }
    func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private func configuration(training: TrainingPlan? = nil) throws -> SessionConfiguration {
        if ftpSelection == "manual", !manualFTP.trimmingCharacters(in: .whitespaces).isEmpty,
           number(manualFTP).map({ $0.isFinite && $0 > 0 }) != true { throw ConfigurationError.invalidFTP }
        if !weight.trimmingCharacters(in: .whitespaces).isEmpty,
           number(weight).map({ $0.isFinite && $0 > 0 }) != true { throw ConfigurationError.invalidWeight }
        let manual = Int(manualWarmup)
        if training == nil && !automaticWarmup && manual == nil { throw ConfigurationError.invalidWarmup }
        return try SessionConfiguration(preset: preset, priorFTP: selectedFTP, weightKG: number(weight),
                                        warmupSeconds: training != nil ? 0 : demoMode && quickDebugTest ? 10 : Double(warmupMinutes * 60),
                                        manualWarmupPower: training?.steps.first?.watts ?? (automaticWarmup ? nil : manual),
                                        cooldownSeconds: training != nil ? 0 : demoMode && quickDebugTest ? 10 : Double(cooldownMinutes * 60), ftpFactor: Self.ftpFactor,
                                        riderID: profile.id, riderName: riderName,
                                        powerSource: powerSource, cadenceSource: cadenceSource,
                                        powerMatchingEnabled: powerMatchingEnabled && training?.resistance == nil)
    }
    func saveExistingFTP() {
        guard !isBusy else { return }
        guard let value = number(manualFTP), value.isFinite, value > 0, value <= 32767 else {
            errorMessage = ConfigurationError.invalidFTP.localizedDescription; return
        }
        let entry = FTPEntry(watts: value)
        profile.ftpHistory.insert(entry, at: 0); profile.currentFTPID = entry.id
        persistProfile(); ftpSelection = entry.id.uuidString
    }
    func adopt(_ session: TestSession) {
        guard !isBusy, !session.isDemo, let result = session.result else { return }
        guard let index = riders.firstIndex(where: { $0.id == session.riderID }) else { return }
        var rider = riders[index]
        let entry = FTPEntry(watts: result.estimatedFTP, source: "Ramp test")
        rider.ftpHistory.insert(entry, at: 0); rider.currentFTPID = entry.id
        do {
            try store.saveProfile(rider); riders[index] = rider
            if profile.id == rider.id { profile = rider; ftpSelection = entry.id.uuidString }
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func persistProfile() -> Bool {
        do {
            try store.saveProfile(profile)
            if let index = riders.firstIndex(where: { $0.id == profile.id }) { riders[index] = profile }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func start(training: TrainingPlan? = nil) async {
        guard !isBusy, saveRiderDetails(), let generation = ownership.begin() else { return }
        let isMock = demoMode
        var touchedTrainer = false
        defer { preparingConfiguration = nil }
        do {
            try training?.validate()
            if !demoMode, let plan = training, plan.resistance == nil {
                guard let range = bluetooth.powerRange, plan.supports(intensity: 100, minimum: range.minimum, maximum: range.maximum),
                      plan.steps.allSatisfy({ range.quantized($0.watts) > 0 && range.quantized($0.endWatts ?? $0.watts) > 0 }) else { throw BluetoothError.targetOutOfRange }
            }
            let config = try configuration(training: training)
            let initialTarget = training?.steps.first?.watts ?? config.warmupPower
            let initialResistance = training?.resistance
            preparingConfiguration = config
            guard initialResistance != nil ? readyForResistance : readyToStart else { throw BluetoothError.notReady }
            if !demoMode {
                if let initialResistance {
                    guard let range = resistanceLimits, range.quantized(initialResistance) == initialResistance else { throw BluetoothError.targetOutOfRange }
                    touchedTrainer = true; try await bluetooth.startResistance(level: initialResistance)
                } else {
                    guard let range = bluetooth.powerRange else { throw BluetoothError.notReady }
                    if training == nil {
                        guard [config.warmupPower, config.preset.startingPower, config.preset.cooldownPower].allSatisfy({ $0 == range.quantized($0) }), config.preset.stepWatts.isMultiple(of: range.increment) else { throw BluetoothError.targetOutOfRange }
                    }
                    touchedTrainer = true; try await bluetooth.startTrainer(power: range.quantized(initialTarget))
                }
            }
            if let reason = ownership.cancellationReason { throw SessionStartCancelled(reason: reason) }
            profile.weightKG = config.weightKG; profile.name = config.riderName ?? riderName
            try store.saveProfile(profile)
            if let index = riders.firstIndex(where: { $0.id == profile.id }) { riders[index] = profile }
            origin = ProcessInfo.processInfo.systemUptime; lastWallTime = origin
            heartRate = nil; heartRateTime = nil
            mockStream = MockRideStream(); mockPaused = false
            elapsed = 0; lastCheckpoint = -1; finalizedID = nil
            cooldownReleaseSent = false; trainerStoppedForCooldown = false
            powerMatcher = PowerMatcher(); trainerWarmth.beginSession(); matchLogPhase = nil; trainerPaused = false; trainingTransition = nil
            lastAcknowledgedTarget = demoMode ? nil : bluetooth.powerRange?.quantized(initialTarget)
            lastAcknowledgedResistance = demoMode ? nil : initialResistance
            autoPause = AutoPause()
            engine = RampEngine(configuration: config, isDemo: demoMode, devices: demoMode ? [] : bluetooth.deviceSnapshots, training: training)
            try store.save(engine!.session)
            guard ownership.started(generation) else { throw SessionStartCancelled(reason: "Starting was cancelled.") }
            cockpitPresented = true; preflightPath = []
            setAwake(true)
            timer?.cancel()
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    self?.update()
                    do { try await Task.sleep(for: .milliseconds(self?.demoMode == true ? 100 : 250)) } catch { return }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            if ownership.owns(generation) {
                engine?.interrupt(at: elapsed, reason: error.localizedDescription)
                if let session = engine?.session { try? store.save(session) }
                ownership.beginFinishing(generation)
                if touchedTrainer && !isMock {
                    do { try await bluetooth.stopTrainer() }
                    catch { errorMessage = "Trainer stop was not confirmed: \(error.localizedDescription)" }
                }
                ownership.released(generation)
                setAwake(false)
            }
        }
    }
    private func receive(_ reading: DeviceReading) {
        guard isActive, !demoMode else { return }
        guard let configuration = engine?.session.configuration,
              let sample = MeasurementRouting.sample(reading, configuration: configuration, origin: origin) else { return }
        if let rate = reading.heartRate { heartRate = rate; heartRateTime = sample.time }
        engine?.receive(sample)
    }
    private func update() {
        guard isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let wallDelta = max(0, now - lastWallTime); lastWallTime = now
        if demoMode {
            guard !mockPaused else { return }
            // Bounded substeps exercise the real freshness and deadline policies at every speed.
            advanceMock(seconds: min(wallDelta, 0.5) * mockSpeed)
            return
        }
        elapsed = now - origin
        engine?.tick(at: elapsed)
        if autoPauseEnabled, let engine, engine.session.training != nil {
            let power = engine.lastPower.flatMap { elapsed - $0.time <= 2 ? $0.watts : nil }
            switch autoPause.update(time: elapsed, phase: engine.phase, power: power, canResume: engine.canResume(at: elapsed)) {
            case .pause: pauseTraining()
            case .resume: resumeTraining()
            case nil: break
            }
        }
        if warmthConnection != bluetooth.trainerConnections { warmthConnection = bluetooth.trainerConnections; trainerWarmth = TrainerWarmth(); trainerWarmth.beginSession() }
        if let reported = engine?.lastTrainerPower { trainerWarmth.add(reported) }
        if !demoMode, let began = commandStartedAt, elapsed - began > 2 {
            interrupt("Trainer target confirmation was delayed."); return
        }
        if engine?.isFreewheelCooldown == true, !cooldownReleaseSent, targetTask == nil {
            // Stop ERG immediately after exhaustion, then record the chosen free-spin recovery.
            cooldownReleaseSent = true; commandStartedAt = elapsed
            guard let generation = ownership.generation else { return }
            targetTask = Task { [weak self] in
                guard let self else { return }
                defer { self.targetTask = nil; self.commandStartedAt = nil }
                guard self.ownership.canControl(generation), self.isActive, self.engine?.phase != .paused else { return }
                do {
                    try await self.bluetooth.stopTrainer()
                    guard self.ownership.canControl(generation) else { return }
                    self.trainerStoppedForCooldown = true
                    self.engine?.recordEvent(at: self.elapsed, message: "Trainer released for free-spin cooldown")
                } catch {
                    if self.ownership.canControl(generation) { self.interrupt(error.localizedDescription) }
                }
            }
        }
        if !demoMode, isActive, let level = engine?.targetResistance, level != lastAcknowledgedResistance, targetTask == nil,
           let generation = ownership.generation {
            commandStartedAt = elapsed
            targetTask = Task { [weak self] in
                guard let self else { return }
                defer { self.targetTask = nil; self.commandStartedAt = nil }
                guard self.ownership.canControl(generation), self.isActive, self.engine?.phase != .paused else { return }
                do {
                    try await self.bluetooth.setResistance(level)
                    guard self.ownership.canControl(generation), self.isActive, self.engine?.phase != .paused else { return }
                    self.lastAcknowledgedResistance = level
                    self.engine?.recordEvent(at: self.elapsed, message: "Trainer confirmed resistance \(Double(level) / 10)")
                } catch { if self.ownership.canControl(generation) { self.interrupt(error.localizedDescription) } }
            }
        }
        if !demoMode, isActive, let workoutTarget = engine?.targetPower, targetTask == nil {
            let target: Int
            if engine?.session.configuration.usesPowerMatching == true, let range = bluetooth.powerRange {
                let cadence = engine?.lastCadence.flatMap { elapsed - $0.time <= 2 ? $0.rpm : nil }
                target = powerMatcher.command(target: workoutTarget, meter: engine?.lastPower, trainer: engine?.lastTrainerPower,
                                              cadence: cadence, at: elapsed, range: range, warmth: trainerWarmth)
            } else { target = bluetooth.powerRange?.quantized(workoutTarget) ?? workoutTarget }
            if target != lastAcknowledgedTarget {
                guard let generation = ownership.generation else { return }
                commandStartedAt = elapsed
                targetTask = Task { [weak self] in
                    guard let self else { return }
                    defer { self.targetTask = nil; self.commandStartedAt = nil }
                    guard self.ownership.canControl(generation), self.isActive, self.engine?.phase != .paused else { return }
                    do {
                        try await self.bluetooth.setTargetPower(target)
                        guard self.ownership.canControl(generation), self.isActive, self.engine?.phase != .paused else { return }
                        self.lastAcknowledgedTarget = target
                        self.engine?.recordEvent(at: self.elapsed, message: "Trainer confirmed \(target) W (workout target \(workoutTarget) W)")
                    } catch {
                        if self.ownership.canControl(generation) { self.interrupt(error.localizedDescription) }
                    }
                }
            }
        }
        logPowerMatching()
        checkpoint()
        if !isActive { finalize() }
    }
    /// What the matcher did, for the owner to read in the ride's events: at ramp start, every 2 minutes of ramp and at ramp end.
    private func logPowerMatching() {
        guard let phase = engine?.phase, engine?.session.configuration.usesPowerMatching == true else { return }
        let previous = matchLogPhase; matchLogPhase = phase
        let rampStarted = phase == .ramp && previous != .ramp
        let periodic = phase == .ramp && elapsed - matchLogTime >= 120
        let rampEnded = previous == .ramp && phase != .ramp
        guard rampStarted || periodic || rampEnded else { return }
        matchLogTime = elapsed
        let label = rampStarted ? "ramp start" : rampEnded ? "ramp end" : "ramp"
        engine?.recordEvent(at: elapsed, message: String(format: "Power matching (%@): gain %.3f, offset %+.1f W, trainer warmth %.0f kJ, fade guard %.0f s, %d measurements",
                                                         label, powerMatcher.gain, powerMatcher.offset, trainerWarmth.kilojoules, powerMatcher.fadeSeconds, powerMatcher.measurementCount))
    }
    func advanceMock(seconds: Double) {
        guard demoMode, isActive, seconds.isFinite, seconds > 0 else { return }
        let end = elapsed + min(seconds, 3600)
        while elapsed < end && isActive {
            elapsed = min(end, elapsed + 0.5)
            let sample = mockStream.sample(at: elapsed, target: engine?.targetPower ?? (engine?.isFreewheelCooldown == true ? 0 : 100),
                                           phase: engine?.phase ?? .waiting, scenario: mockScenario,
                                           powerSource: engine?.session.configuration.resolvedPowerSource ?? .trainer,
                                           manualPower: manualMockValues ? mockPower : nil,
                                           manualCadence: manualMockValues ? mockCadence : nil,
                                           manualHeartRate: manualMockValues ? Int(mockHeartRate) : nil)
            heartRate = sample.heartRate
            if sample.heartRate != nil { heartRateTime = elapsed }
            engine?.receive(sample); engine?.tick(at: elapsed)
        }
        checkpoint()
        if !isActive { finalize() }
    }
    func skipMockWarmup() {
        guard demoMode, let engine, engine.phase == .warmup else { return }
        advanceMock(seconds: max(0.5, engine.session.configuration.warmupSeconds - (elapsed - engine.phaseStartedAt) + 0.5))
    }
    func simulateTrainerDisconnect() {
        guard demoMode else { return }
        interrupt("Debug simulation: trainer connection lost.")
    }
    func pauseTraining() {
        guard isActive, trainingControlTask == nil, engine?.session.training != nil,
              let generation = ownership.generation else { return }
        if !demoMode { elapsed = max(elapsed, ProcessInfo.processInfo.systemUptime - origin) }
        guard engine?.pause(at: elapsed) == true else { if !isActive { finalize() }; return }
        powerMatcher.restartSettle(at: elapsed)
        if demoMode { trainerPaused = true }
        else {
            let pending = targetTask
            trainingTransition = "Releasing trainer…"
            trainingControlTask = Task { [weak self] in
                guard let self else { return }
                defer { self.trainingControlTask = nil; self.trainingTransition = nil }
                await pending?.value
                guard self.ownership.canControl(generation), self.engine?.phase == .paused else { return }
                do {
                    try await self.bluetooth.stopTrainer()
                    guard self.ownership.canControl(generation), self.engine?.phase == .paused else { return }
                    self.trainerPaused = true; self.lastAcknowledgedTarget = nil
                    self.engine?.recordEvent(at: self.elapsed, message: "Trainer release confirmed for pause")
                } catch {
                    if self.ownership.canControl(generation) { self.interrupt(error.localizedDescription) }
                }
            }
        }
        checkpoint(force: true)
        if !isActive { finalize() }
    }
    func resumeTraining() {
        guard engine?.phase == .paused, trainingControlTask == nil, trainerPaused,
              let generation = ownership.generation, let target = engine?.resumeResistance ?? engine?.resumeTarget else { return }
        if !demoMode { elapsed = max(elapsed, ProcessInfo.processInfo.systemUptime - origin) }
        guard engine?.canResume(at: elapsed) == true else {
            errorMessage = "Pedal until fresh power and cadence arrive, then resume."; return
        }
        if demoMode {
            engine?.resume(at: elapsed); trainerPaused = false; powerMatcher.restartSettle(at: elapsed); checkpoint(force: true)
            if !isActive { finalize() }
            return
        }
        trainerPaused = false // A cancelled restart still needs a confirmed Stop.
        trainingTransition = "Resuming trainer…"
        trainingControlTask = Task { [weak self] in
            guard let self else { return }
            defer { self.trainingControlTask = nil; self.trainingTransition = nil }
            guard self.ownership.canControl(generation), self.engine?.phase == .paused else { return }
            do {
                if self.engine?.resumeResistance != nil { try await self.bluetooth.startResistance(level: target) }
                else { try await self.bluetooth.startTrainer(power: self.bluetooth.powerRange?.quantized(target) ?? target) }
                guard self.ownership.canControl(generation), self.engine?.phase == .paused else { return }
                self.elapsed = max(self.elapsed, ProcessInfo.processInfo.systemUptime - self.origin)
                guard self.engine?.resume(at: self.elapsed) == true else {
                    self.interrupt("Fresh movement was lost while resuming. The ride has been interrupted."); return
                }
                self.powerMatcher.restartSettle(at: self.elapsed); self.lastAcknowledgedTarget = self.bluetooth.powerRange?.quantized(target)
                self.lastAcknowledgedResistance = self.engine?.resumeResistance
                self.checkpoint(force: true)
                if !self.isActive { self.finalize() }
            } catch {
                if self.ownership.canControl(generation) { self.interrupt(error.localizedDescription) }
            }
        }
    }
    func finishRamp() {
        guard engine?.phase == .ramp else { return }
        engine?.finishRamp(at: elapsed); logPowerMatching(); checkpoint(force: true)
        if !isActive { finalize() }
    }
    func stop() {
        if isStarting { ownership.cancelStart("Starting the test was cancelled."); return }
        guard isActive else { return }
        engine?.endActivity(at: elapsed); finalize()
    }
    func interrupt(_ reason: String) {
        if isStarting { ownership.cancelStart(reason); return }
        guard isActive else { return }
        engine?.interrupt(at: elapsed, reason: reason); finalize()
    }
    private func checkpoint(force: Bool = false) {
        guard let session = engine?.session, force || elapsed - lastCheckpoint >= 1 else { return }
        do { try store.save(session); lastCheckpoint = elapsed
            if let updated = try store.profiles().first(where: { $0.id == profile.id }) { profile.cycleProgress = updated.cycleProgress } }
        catch {
            errorMessage = "Recording could not be saved: \(error.localizedDescription)"
            engine?.interrupt(at: elapsed, reason: "Local storage failed.")
        }
    }
    private func finalize() {
        guard let session = engine?.session, finalizedID != session.id,
              let generation = ownership.generation, ownership.beginFinishing(generation) else { return }
        finalizedID = session.id; timer?.cancel(); timer = nil
        var saved = false
        do { try store.save(session); saved = true; try reload() }
        catch { errorMessage = "Activity could not be saved: \(error.localizedDescription)" }
        if session.isDemo || trainerStoppedForCooldown {
            ownership.released(generation); setAwake(false)
            if saved { askToUploadAfterRide(session) }
            return
        }
        let pending = targetTask, trainingPending = trainingControlTask
        Task { [weak self] in
            guard let self else { return }
            // Stop owns the controller until both the outstanding command and release finish.
            // A cancelled Swift task alone does not cancel a Bluetooth transaction.
            await pending?.value
            await trainingPending?.value
            do { if !self.trainerPaused { try await self.bluetooth.stopTrainer() } }
            catch { self.errorMessage = "Trainer stop was not confirmed: \(error.localizedDescription)" }
            guard self.ownership.owns(generation) else { return }
            self.targetTask = nil; self.commandStartedAt = nil
            self.ownership.released(generation); self.setAwake(false)
            if saved { self.askToUploadAfterRide(session) }
        }
    }
    func connectIntervals() async {
        guard !connecting else { return }
        connecting = true; defer { connecting = false }
        do {
            let value = try await signIn.connect()
            try await acceptConnection(value)
        }
        catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { errorMessage = error.localizedDescription }
        }
    }
    func connectIntervalsWithAPIKey() async {
        guard !connecting else { return }
        connecting = true; defer { connecting = false }
        do {
            let value = try await AppInfo.intervalsClient.connect(apiKey: apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
            try await acceptConnection(value); apiKeyInput = ""
        } catch { errorMessage = error.localizedDescription }
    }
    /// Connects the selected rider. An Intervals.icu account can belong to one rider only.
    func acceptConnection(_ value: IntervalsConnection) async throws {
        let riderID = profile.id
        if let owner = riders.first(where: { $0.id != riderID && connections[$0.id]?.athleteID == value.athleteID }) {
            if value.usesOAuth { try? await AppInfo.intervalsClient.revoke(value) }
            errorMessage = "This Intervals.icu account is already connected to \(owner.name)."
            return
        }
        if let old = connections[riderID], old.athleteID != value.athleteID { try store.deleteUploadJobs(accountID: old.athleteID) }
        try credentials.save(value, riderID: riderID); connections[riderID] = value
        loadAthleteSync()
        await syncAthleteSettings()
        await flushUploads()
        if let session = engine?.session, session.endedAtOffset != nil, session.riderID == riderID { requestUpload(session) }
    }
    /// Disconnects the selected rider only. Other riders keep their accounts and queued uploads.
    func disconnectIntervals() async {
        let riderID = profile.id, old = connections[riderID]
        do {
            uploadRetry?.cancel()
            if let old { try store.deleteUploadJobs(accountID: old.athleteID) }
            try credentials.clear(riderID: riderID); connections[riderID] = nil
            if uploadConsent?.riderID == riderID { uploadConsent = nil }
            try reload()
            athleteSync = AthleteSyncSettings(); athleteSyncNote = nil; athleteSyncNeedsReconnect = false
            if !preview { UserDefaults.standard.removeObject(forKey: syncKey(riderID)) }
            if let old, old.usesOAuth {
                do { try await AppInfo.intervalsClient.revoke(old) }
                catch { errorMessage = "Disconnected on this device. Online revocation could not be confirmed; you can revoke access in Intervals.icu Settings." }
            }
            await flushUploads()
        } catch { errorMessage = error.localizedDescription }
    }
    private func upload(_ session: TestSession) async {
        guard let connection = connections[session.riderID], !session.isDemo else { return }
        do { try uploads.enqueue(session, connection: connection); await flushUploads() }
        catch { errorMessage = error.localizedDescription }
    }
    /// Opens the consent sheet for a saved activity. Used by the manual buttons and, through `askToUploadAfterRide`, after a ride.
    func requestUpload(_ session: TestSession) {
        guard let connection = connections[session.riderID], !session.isDemo, session.endedAtOffset != nil,
              !jobs.contains(where: { $0.sessionID == session.id && $0.accountID == connection.athleteID }) else { return }
        uploadConsent = UploadConsent(session: session, accountID: connection.athleteID, accountName: connection.athleteName)
    }
    /// Drops the finished upload record of a saved activity and opens the consent sheet again, so the activity is sent anew
    /// with a freshly encoded file. Intervals.icu matches uploads by `external_id`, so it may treat this as a duplicate
    /// of the earlier one; delete the old activity there first if the new file should replace it.
    func requestReupload(_ session: TestSession) {
        guard let connection = connections[session.riderID], !session.isDemo, session.endedAtOffset != nil else { return }
        let finished = jobs.filter { $0.sessionID == session.id && $0.accountID == connection.athleteID && $0.status != .uploading }
        guard !finished.isEmpty, finished.count == jobs.filter({ $0.sessionID == session.id && $0.accountID == connection.athleteID }).count else { return }
        do {
            for job in finished { try store.deleteUploadJob(id: job.id) }
            try reload()
            requestUpload(session)
        } catch { errorMessage = error.localizedDescription }
    }
    /// After a finished ride: ask when `UploadPromptRule` says so. Never uploads by itself.
    func askToUploadAfterRide(_ session: TestSession) {
        let connection = connections[session.riderID]
        let existing = jobs.first { $0.sessionID == session.id && $0.accountID == connection?.athleteID }
        guard UploadPromptRule.shouldAsk(session: session, hasConnection: connection != nil,
                                         askEnabled: !uploadPromptDisabled.contains(session.riderID), existingJob: existing) else { return }
        requestUpload(session)
    }
    func confirmUpload(_ consent: UploadConsent) async {
        guard connections[consent.riderID]?.athleteID == consent.accountID else {
            errorMessage = "The connected account changed. Choose Upload again to confirm the destination."; return
        }
        await upload(consent.session)
    }
    /// Uploads queued jobs for every rider that has a connection, each with its own account.
    func flushUploads(manual: Bool = false) async {
        do {
            for connection in connections.values {
                if manual, connection.athleteID == self.connection?.athleteID { try uploads.retryPending(accountID: connection.athleteID) }
                try await uploads.run(connection: connection)
            }
            try reload()
            uploadRetry?.cancel()
            let accounts = Set(connections.values.map(\.athleteID))
            if let next = jobs.filter({ accounts.contains($0.accountID) && $0.status == .queued }).map(\.nextAttemptAt).min() {
                let delay = min(3600, max(1, next.timeIntervalSinceNow))
                uploadRetry = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    await self?.flushUploads()
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func delete(_ session: TestSession) {
        guard !isBusy else { return }
        do {
            try store.deleteSession(id: session.id)
            if engine?.session.id == session.id { engine = nil }
            if uploadConsent?.id == session.id { uploadConsent = nil }
            try reload()
        } catch { errorMessage = error.localizedDescription }
    }
    func reload() throws {
        history = try store.sessions(); jobs = try store.uploadJobs(); try catalog.reload(); customWorkouts = try store.customWorkouts()
        let saved = try store.profiles()
        if !saved.isEmpty { riders = saved }
        if let updated = saved.first(where: { $0.id == profile.id }) { profile.cycleProgress = updated.cycleProgress }
    }
    func adjustIntensity(by delta: Int) {
        guard isActive, trainingControlTask == nil, let engine, engine.session.training?.kind == .workout else { return }
        let percent = engine.intensity + delta
        let minimum = demoMode ? 1 : bluetooth.powerRange?.minimum ?? 1
        let maximum = demoMode ? 32767 : bluetooth.powerRange?.maximum ?? 0
        if !demoMode, let range = bluetooth.powerRange, let plan = engine.session.training,
           !plan.steps.allSatisfy({ [$0.watts, $0.endWatts ?? $0.watts].allSatisfy { range.quantized(Int((Double($0) * Double(percent) / 100).rounded())) > 0 } }) {
            errorMessage = "The adjusted target rounds to zero on this trainer."; return
        }
        guard self.engine?.setIntensity(percent, at: elapsed, minimum: minimum, maximum: maximum) == true else {
            errorMessage = "Choose 50–150% intensity within the trainer’s supported power range."; return
        }
        powerMatcher.restartSettle(at: elapsed); checkpoint(force: true)
        if !isActive { finalize() }
    }
    /// Moves a workout on to its next step; the trainer gets the new target on the next tick.
    func skipStep() {
        guard isActive, trainingControlTask == nil, engine?.skipStep(at: elapsed) == true else { return }
        powerMatcher.restartSettle(at: elapsed); checkpoint(force: true)
    }
    func adjustResistance(by steps: Int) {
        guard isActive, trainingControlTask == nil, let current = engine?.resumeResistance, let range = resistanceLimits else { return }
        engine?.adjustResistance(to: range.quantized(current + steps * range.increment), at: elapsed)
    }
    private var catalogContext: WorkoutCatalog.Context {
        WorkoutCatalog.Context(riderID: profile.id, ftp: libraryFTP, connection: connection, isBusy: isBusy)
    }
    func importWorkout(_ data: Data) {
        guard !isBusy else { return }
        do { try catalog.importWorkout(data, context: catalogContext) } catch { errorMessage = error.localizedDescription }
    }
    func deleteWorkout(_ workout: CachedWorkout) {
        guard !isBusy else { return }
        do { try catalog.delete(workout) } catch { errorMessage = error.localizedDescription }
    }
    /// Downloads the next 14 days. Automatic refreshes are quiet; manual ones report errors.
    func downloadWorkouts(quiet: Bool = false) async {
        guard !preview else { catalog.report = "Preview mode: Intervals.icu downloads are disabled."; return }
        await syncAthleteSettings()
        if let message = await catalog.download(context: { [unowned self] in self.catalogContext }, quiet: quiet) { errorMessage = message }
    }
    /// Home refreshes the calendar when it appears and the last download is over an hour old, never during a ride.
    func refreshWorkoutsIfNeeded() async {
        guard SyncPolicy.shouldRefresh(lastDownload: catalog.lastDownload(for: connection?.athleteID), connected: connection != nil,
                                       rideActive: isBusy, alreadyRunning: catalog.downloading) else { return }
        await downloadWorkouts(quiet: true)
    }
    func adjustERG(by delta: Int) {
        guard isActive, trainingControlTask == nil, engine?.resumeResistance == nil, engine?.session.training?.kind == .freeRide else { return }
        let requested = (engine?.targetPower ?? engine?.resumeTarget ?? freeRideWatts) + delta
        let target = demoMode ? min(1000, max(1, requested)) : bluetooth.powerRange?.quantized(requested)
        guard let target else { return }
        engine?.adjustFreeRide(to: target, at: elapsed); powerMatcher.restartSettle(at: elapsed)
    }
    func export(_ session: TestSession, format: ActivityFileFormat) -> URL? {
        do {
            let data = try ActivityExport.data(session, format: format)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ActivityExport.fileName(session, format: format))
            try data.write(to: url, options: .atomic); return url
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    var canTransferData: Bool { !isBusy && !uploads.isRunning && !downloadingWorkouts }
    func archiveFile() -> URL? {
        guard canTransferData else { errorMessage = "Wait for the ride or upload to finish before transferring data."; return nil }
        do {
            let data = try store.portableArchive().encoded()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FTPunk-Backup-\(UUID()).json")
            try data.write(to: url, options: .atomic); return url
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func restoreArchive(_ archive: PortableArchive) -> URL? {
        guard canTransferData else { errorMessage = "Wait for the ride or upload to finish before importing."; return nil }
        do {
            try archive.validate()
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
                .appendingPathComponent("FTPunk/Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let backup = directory.appendingPathComponent("Before-import-\(UUID()).json")
            try store.portableArchive().encoded().write(to: backup, options: .atomic)
            try store.restore(archive)
            engine = nil; uploadConsent = nil
            riders = try store.profiles()
            try loadConnections()
            let selected = riders.first(where: { $0.id == profile.id }) ?? riders[0]
            selectRider(selected.id); try reload()
            return backup
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func captureFile() -> URL? {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted; encoder.dateEncodingStrategy = .iso8601
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FTPunk-Bluetooth-Capture.json")
            try encoder.encode(bluetooth.captures).write(to: url, options: .atomic); return url
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    private func setAwake(_ enabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = enabled
        #elseif os(macOS)
        if enabled, wakeActivity == nil {
            wakeActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "Recording an FTP ramp test")
        } else if !enabled, let activity = wakeActivity {
            ProcessInfo.processInfo.endActivity(activity); wakeActivity = nil
        }
        #endif
    }
}

private struct SessionStartCancelled: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
