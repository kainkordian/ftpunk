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

struct UploadConsent: Identifiable {
    var id: UUID { session.id }
    let session: TestSession
    let accountID: String
    let accountName: String
}

@MainActor @Observable final class AppModel {
    let bluetooth = BluetoothDevices()
    private let store: LocalStore
    private let uploads: UploadWorker
    var profile: RiderProfile
    var riders: [RiderProfile]
    var riderName = ""
    var history: [TestSession] = []
    var jobs: [ActivityUploadJob] = []
    var engine: RampEngine?
    var elapsed = 0.0
    var selectedTab = 0
    var setupStep = 0
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
    #if os(macOS)
    @ObservationIgnored private var wakeActivity: NSObjectProtocol?
    #endif

    init(store: LocalStore, preview: Bool = false) throws {
        self.store = store; self.preview = preview; uploads = UploadWorker(repository: store)
        try store.recoverInterruptedSessions()
        let savedRiders = try store.profiles()
        let availableRiders = savedRiders.isEmpty ? [RiderProfile()] : savedRiders
        riders = availableRiders
        let selectedID = preview ? nil : UserDefaults.standard.string(forKey: "selectedRiderID")
        profile = availableRiders.first(where: { $0.id.uuidString == selectedID }) ?? availableRiders[0]
        riderName = profile.name
        if let current = profile.currentFTP { ftpSelection = current.id.uuidString }
        if let kg = profile.weightKG { weight = String(kg) }
        connection = preview ? nil : try CredentialVault.load()
        // Previous prototypes could queue automatically. New tests always ask first.
        if let connection { try uploads.cancelAutomaticUploads(accountID: connection.athleteID) }
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
    var selectedRiderID: UUID {
        get { profile.id }
        set { selectRider(newValue) }
    }
    func selectRider(_ id: UUID) {
        guard !isActive, let rider = riders.first(where: { $0.id == id }) else { return }
        profile = rider; riderName = rider.name
        weight = rider.weightKG.map { String($0) } ?? ""
        manualFTP = ""
        ftpSelection = rider.currentFTPID?.uuidString ?? "manual"
        if !preview { UserDefaults.standard.set(id.uuidString, forKey: "selectedRiderID") }
    }
    func addRider(name: String) -> Bool {
        guard !isActive else { return false }
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
        guard !isActive else { return false }
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
                                        cooldownSeconds: demoMode && quickDebugTest ? 10 : 180, ftpFactor: ftpFactor,
                                        riderID: profile.id, riderName: riderName)
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
        guard let index = riders.firstIndex(where: { $0.id == session.riderID }) else { return }
        var rider = riders[index]
        let entry = FTPEntry(watts: result.estimatedFTP, source: "Ramp test")
        rider.ftpHistory.insert(entry, at: 0); rider.currentFTPID = entry.id
        do {
            try store.saveProfile(rider); riders[index] = rider
            if profile.id == rider.id { profile = rider; ftpSelection = entry.id.uuidString }
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult private func persistProfile() -> Bool {
        do {
            try store.saveProfile(profile)
            if let index = riders.firstIndex(where: { $0.id == profile.id }) { riders[index] = profile }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func start() async {
        guard !isActive, !isStarting else { return }
        isStarting = true; defer { isStarting = false }
        do {
            guard saveRiderDetails() else { return }
            let config = try configuration()
            guard readyToStart else { throw BluetoothError.notReady }
            if !demoMode {
                guard let range = bluetooth.powerRange,
                      config.warmupPower == range.quantized(config.warmupPower),
                      config.preset.startingPower == range.quantized(config.preset.startingPower),
                      config.preset.cooldownPower == range.quantized(config.preset.cooldownPower),
                      config.preset.stepWatts.isMultiple(of: range.increment) else {
                    throw BluetoothError.targetOutOfRange
                }
                try await bluetooth.startTrainer(power: config.warmupPower)
            }
            profile.weightKG = config.weightKG; profile.name = config.riderName ?? riderName
            try store.saveProfile(profile)
            if let index = riders.firstIndex(where: { $0.id == profile.id }) { riders[index] = profile }
            origin = ProcessInfo.processInfo.systemUptime; lastWallTime = origin
            heartRate = nil; heartRateTime = nil
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
        guard isActive, !demoMode else { return }
        let time = reading.uptime - origin
        guard time >= 0 else { return }
        if let rate = reading.heartRate { heartRate = rate; heartRateTime = time }
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
        if saved, session.outcome?.allowsEstimate == true { requestUpload(session) }
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
        if let session = engine?.session, session.endedAtOffset != nil { requestUpload(session) }
    }
    func disconnectIntervals() async {
        let old = connection
        do {
            uploadRetry?.cancel()
            if let old { try store.deleteUploadJobs(accountID: old.athleteID) }
            try CredentialVault.clear(); connection = nil; uploadConsent = nil; try reload()
            if let old, old.usesOAuth {
                do { try await IntervalsClient().revoke(old) }
                catch { errorMessage = "Disconnected on this device. Online revocation could not be confirmed; you can revoke access in Intervals.icu Settings." }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    private func upload(_ session: TestSession) async {
        guard let connection, !session.isDemo else { return }
        do { try uploads.enqueue(session, connection: connection); await flushUploads() }
        catch { errorMessage = error.localizedDescription }
    }
    func requestUpload(_ session: TestSession) {
        guard let connection, !session.isDemo, session.endedAtOffset != nil,
              !jobs.contains(where: { $0.sessionID == session.id && $0.accountID == connection.athleteID }) else { return }
        uploadConsent = UploadConsent(session: session, accountID: connection.athleteID, accountName: connection.athleteName)
    }
    func confirmUpload(_ consent: UploadConsent) async {
        guard connection?.athleteID == consent.accountID else {
            errorMessage = "The connected account changed. Choose Upload again to confirm the destination."; return
        }
        await upload(consent.session)
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
        do {
            try store.deleteSession(id: session.id)
            if engine?.session.id == session.id { engine = nil }
            if uploadConsent?.id == session.id { uploadConsent = nil }
            try reload()
        } catch { errorMessage = error.localizedDescription }
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
        #elseif os(macOS)
        if enabled, wakeActivity == nil {
            wakeActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "Recording an FTP ramp test")
        } else if !enabled, let activity = wakeActivity {
            ProcessInfo.processInfo.endActivity(activity); wakeActivity = nil
        }
        #endif
    }
}
