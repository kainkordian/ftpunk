import Foundation
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

@MainActor @Observable final class AppModel {
    let bluetooth = BluetoothDevices()
    private let store: LocalStore
    private let uploads: UploadWorker
    var profile: RiderProfile
    var history: [TestSession] = []
    var jobs: [ActivityUploadJob] = []
    var engine: RampEngine?
    var elapsed = 0.0
    var selectedTab = 0
    var preset: RampPreset = .standard
    var ftpSelection = "manual"
    var manualFTP = ""
    var weight = ""
    var warmupMinutes = 10
    var automaticWarmup = true
    var manualWarmup = "100"
    var ftpFactor = 0.72
    var demoMode = true
    var mockScenario: MockScenario = .rampToExhaustion
    var mockSpeed = 12.0
    var quickDebugTest = true
    var mockPaused = false
    var manualMockValues = false
    var mockPower = 200.0
    var mockCadence = 88.0
    var mockHeartRate = 140.0
    var isStarting = false
    var errorMessage: String?
    var connection: IntervalsConnection?
    var apiKeyInput = ""
    var connecting = false
    var autoUpload: Bool {
        didSet {
            if !preview { UserDefaults.standard.set(autoUpload, forKey: "autoUpload") }
            if !autoUpload, let connection {
                do { try uploads.cancelAutomaticUploads(accountID: connection.athleteID); try reload() }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }
    var heartRate: Int?
    private var origin = 0.0
    private var lastWallTime = 0.0
    private var mockStream = MockRideStream()
    private let preview: Bool
    private let signIn = IntervalsSignIn()
    private var timer: Task<Void, Never>?
    private var targetTask: Task<Void, Never>?
    private var lastAcknowledgedTarget: Int?
    private var commandStartedAt: Double?
    private var lastCheckpoint = -1.0
    private var finalizedID: UUID?
    private let network = NWPathMonitor()
    private var uploadRetry: Task<Void, Never>?

    init(store: LocalStore, preview: Bool = false) throws {
        self.store = store; self.preview = preview; uploads = UploadWorker(repository: store)
        try store.recoverInterruptedSessions()
        profile = try store.loadProfile()
        autoUpload = preview ? false : UserDefaults.standard.bool(forKey: "autoUpload")
        if let current = profile.currentFTP { ftpSelection = current.id.uuidString }
        if let kg = profile.weightKG { weight = String(kg) }
        connection = preview ? nil : try CredentialVault.load()
        if preview { manualFTP = "250"; weight = "75" }
        try reload()
        bluetooth.onReading = { [weak self] in self?.receive($0) }
        bluetooth.onEssentialFailure = { [weak self] reason in
            guard let self, self.isActive, !self.demoMode else { return }
            self.interrupt(reason)
        }
        network.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in await self?.flushUploads() } }
        }
        if !preview { network.start(queue: DispatchQueue(label: "FTPunk.network")) }
    }
    var isActive: Bool { engine?.phase.isActive == true }
    var activeSession: TestSession? { engine?.session }
    var oauthConfigured: Bool { IntervalsSignIn.configuration != nil }
    var selectedFTP: FTPEntry? {
        if ftpSelection == "manual" { return number(manualFTP).map { FTPEntry(watts: $0) } }
        return profile.ftpHistory.first { $0.id.uuidString == ftpSelection }
    }
    var warmupPreview: String {
        guard let config = try? configuration() else { return "Enter valid setup values" }
        return "\(config.warmupPower) W"
    }
    var readyToStart: Bool {
        if demoMode { return true }
        guard bluetooth.trainerReady, let last = bluetooth.lastPedalUptime else { return false }
        return ProcessInfo.processInfo.systemUptime - last <= 2 && bluetooth.pedalCadence != nil
    }
    func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private func configuration() throws -> SessionConfiguration {
        if ftpSelection == "manual", !manualFTP.trimmingCharacters(in: .whitespaces).isEmpty,
           number(manualFTP).map({ $0.isFinite && $0 > 0 }) != true { throw ConfigurationError.invalidFTP }
        if !weight.trimmingCharacters(in: .whitespaces).isEmpty,
           number(weight).map({ $0.isFinite && $0 > 0 }) != true { throw ConfigurationError.invalidWeight }
        let manual = Int(manualWarmup)
        if !automaticWarmup && manual == nil { throw ConfigurationError.invalidWarmup }
        return try SessionConfiguration(preset: preset, priorFTP: selectedFTP, weightKG: number(weight),
                                        warmupSeconds: demoMode && quickDebugTest ? 10 : Double(warmupMinutes * 60),
                                        manualWarmupPower: automaticWarmup ? nil : manual,
                                        cooldownSeconds: demoMode && quickDebugTest ? 10 : 180, ftpFactor: ftpFactor)
    }
    func saveExistingFTP() {
        guard let value = number(manualFTP), value.isFinite, value > 0, value <= 32767 else {
            errorMessage = ConfigurationError.invalidFTP.localizedDescription; return
        }
        let entry = FTPEntry(watts: value)
        profile.ftpHistory.insert(entry, at: 0); profile.currentFTPID = entry.id
        persistProfile(); ftpSelection = entry.id.uuidString
    }
    func adopt(_ session: TestSession) {
        guard !session.isDemo, let result = session.result else { return }
        let entry = FTPEntry(watts: result.estimatedFTP, source: "Ramp test")
        profile.ftpHistory.insert(entry, at: 0); profile.currentFTPID = entry.id
        persistProfile(); ftpSelection = entry.id.uuidString
    }
    private func persistProfile() {
        do { try store.saveProfile(profile) } catch { errorMessage = error.localizedDescription }
    }
    func start() async {
        guard !isActive, !isStarting else { return }
        isStarting = true; defer { isStarting = false }
        do {
            let config = try configuration()
            guard readyToStart else { throw BluetoothError.notReady }
            if !demoMode {
                guard let range = bluetooth.powerRange,
                      config.warmupPower == range.quantized(config.warmupPower),
                      config.preset.startingPower == range.quantized(config.preset.startingPower),
                      config.preset.cooldownPower == range.quantized(config.preset.cooldownPower),
                      5.isMultiple(of: range.increment) else {
                    throw BluetoothError.targetOutOfRange
                }
                try await bluetooth.startTrainer(power: config.warmupPower)
            }
            profile.weightKG = config.weightKG; try store.saveProfile(profile)
            origin = ProcessInfo.processInfo.systemUptime; lastWallTime = origin
            mockStream = MockRideStream(); mockPaused = false
            elapsed = 0; lastCheckpoint = -1; finalizedID = nil
            lastAcknowledgedTarget = demoMode ? nil : config.warmupPower
            engine = RampEngine(configuration: config, isDemo: demoMode, devices: demoMode ? [] : bluetooth.deviceSnapshots)
            try store.save(engine!.session)
            selectedTab = 1
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
            if !demoMode { try? await bluetooth.stopTrainer() }
        }
    }
    private func receive(_ reading: DeviceReading) {
        if let rate = reading.heartRate { heartRate = rate }
        guard isActive, !demoMode else { return }
        let time = reading.uptime - origin
        guard time >= 0 else { return }
        let sample = RideSample(time: time,
                                power: reading.role == .pedals ? reading.power : nil,
                                cadence: reading.role == .pedals ? reading.cadence : nil,
                                heartRate: reading.heartRate,
                                trainerPower: reading.role == .trainer ? reading.power : nil)
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
        if !demoMode, let began = commandStartedAt, elapsed - began > 2 {
            interrupt("Trainer target confirmation was delayed."); return
        }
        if engine?.phase == .cooldown, engine?.session.outcome == .exhaustion, !demoMode {
            // Release ERG after cadence failure; do not force a stalled rider through a cooldown load.
            engine?.endActivity(at: elapsed)
        }
        if !demoMode, isActive, let target = engine?.targetPower, target != lastAcknowledgedTarget, targetTask == nil {
            commandStartedAt = elapsed
            targetTask = Task { [weak self] in
                guard let self else { return }
                defer { self.targetTask = nil; self.commandStartedAt = nil }
                do {
                    try await self.bluetooth.setTargetPower(target)
                    guard self.isActive else { return }
                    self.lastAcknowledgedTarget = target
                    self.engine?.recordEvent(at: self.elapsed, message: "Trainer confirmed \(target) W")
                } catch { self.interrupt(error.localizedDescription) }
            }
        }
        checkpoint()
        if !isActive { finalize() }
    }
    func advanceMock(seconds: Double) {
        guard demoMode, isActive, seconds.isFinite, seconds > 0 else { return }
        let end = elapsed + min(seconds, 3600)
        while elapsed < end && isActive {
            elapsed = min(end, elapsed + 0.5)
            let sample = mockStream.sample(at: elapsed, target: engine?.targetPower ?? 100,
                                           phase: engine?.phase ?? .waiting, scenario: mockScenario,
                                           manualPower: manualMockValues ? mockPower : nil,
                                           manualCadence: manualMockValues ? mockCadence : nil,
                                           manualHeartRate: manualMockValues ? Int(mockHeartRate) : nil)
            heartRate = sample.heartRate
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
    func finishRamp() {
        guard engine?.phase == .ramp else { return }
        engine?.finishRamp(at: elapsed); checkpoint(force: true)
    }
    func stop() {
        guard isActive else { return }
        engine?.endActivity(at: elapsed); finalize()
    }
    func interrupt(_ reason: String) {
        guard isActive else { return }
        engine?.interrupt(at: elapsed, reason: reason); finalize()
    }
    private func checkpoint(force: Bool = false) {
        guard let session = engine?.session, force || elapsed - lastCheckpoint >= 1 else { return }
        do { try store.save(session); lastCheckpoint = elapsed }
        catch {
            errorMessage = "Recording could not be saved: \(error.localizedDescription)"
            engine?.interrupt(at: elapsed, reason: "Local storage failed.")
        }
    }
    private func finalize() {
        guard let session = engine?.session, finalizedID != session.id else { return }
        finalizedID = session.id; timer?.cancel(); timer = nil; setAwake(false)
        targetTask?.cancel()
        var saved = false
        do { try store.save(session); saved = true; try reload() }
        catch { errorMessage = "Activity could not be saved: \(error.localizedDescription)" }
        if !session.isDemo {
            Task { [weak self] in
                guard let self else { return }
                do { try await self.bluetooth.stopTrainer() }
                catch { self.errorMessage = "Trainer stop was not confirmed: \(error.localizedDescription)" }
            }
        }
        if saved, autoUpload, let connection, session.outcome?.allowsEstimate == true, !session.isDemo {
            do { try uploads.enqueue(session, connection: connection, automatic: true); Task { await flushUploads() } }
            catch { errorMessage = error.localizedDescription }
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
            let value = try await IntervalsClient().connect(apiKey: apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
            try await acceptConnection(value); apiKeyInput = ""
        } catch { errorMessage = error.localizedDescription }
    }
    private func acceptConnection(_ value: IntervalsConnection) async throws {
        if let old = connection, old.athleteID != value.athleteID { try store.deleteUploadJobs(accountID: old.athleteID) }
        try CredentialVault.save(value); connection = value
        await flushUploads()
    }
    func disconnectIntervals() async {
        let old = connection
        do {
            uploadRetry?.cancel()
            if let old { try store.deleteUploadJobs(accountID: old.athleteID) }
            try CredentialVault.clear(); connection = nil; autoUpload = false; try reload()
            if let old, old.usesOAuth {
                do { try await IntervalsClient().revoke(old) }
                catch { errorMessage = "Disconnected on this device. Online revocation could not be confirmed; you can revoke access in Intervals.icu Settings." }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func upload(_ session: TestSession) async {
        guard let connection, !session.isDemo else { return }
        do { try uploads.enqueue(session, connection: connection); await flushUploads() }
        catch { errorMessage = error.localizedDescription }
    }
    func flushUploads(manual: Bool = false) async {
        guard let connection else { return }
        do {
            if manual { try uploads.retryPending(accountID: connection.athleteID) }
            try await uploads.run(connection: connection); try reload()
            uploadRetry?.cancel()
            if let next = jobs.filter({ $0.accountID == connection.athleteID && $0.status == .queued }).map(\.nextAttemptAt).min() {
                let delay = min(3600, max(1, next.timeIntervalSinceNow))
                uploadRetry = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    await self?.flushUploads()
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func delete(_ session: TestSession) {
        guard session.id != engine?.session.id || !isActive else { return }
        do { try store.deleteSession(id: session.id); try reload() } catch { errorMessage = error.localizedDescription }
    }
    func reload() throws { history = try store.sessions(); jobs = try store.uploadJobs() }
    func export(_ session: TestSession, kind: String) -> URL? {
        do {
            let data = try kind == "tcx" ? ActivityExport.tcx(session) : kind == "csv" ? ActivityExport.csv(session) : ActivityExport.json(session)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FTPunk-\(session.id).\(kind)")
            try data.write(to: url, options: .atomic); return url
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
        #endif
    }
}
