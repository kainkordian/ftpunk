import SwiftUI
import Charts
import FTPunkDomain
import FTPunkDevices

private let accent = Color(red: 0.77, green: 0.97, blue: 0.30)

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            SetupView(model: model).tabItem { Label("Test setup", systemImage: "slider.horizontal.3") }.tag(0)
            RideView(model: model).tabItem { Label("Ride", systemImage: "waveform.path.ecg") }.tag(1)
            HistoryView(model: model).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(2)
            SettingsView(model: model).tabItem { Label("Connections", systemImage: "link") }.tag(3)
        }
        .tint(accent)
        .alert("FTPunk", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct SetupView: View {
    @Bindable var model: AppModel
    @ViewState private var deviceRole: DeviceRole? = nil
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("FIND YOUR NEXT\nTHRESHOLD.")
                        .font(.system(size: 34, weight: .black, design: .rounded)).foregroundStyle(accent)
                    Text("Pedal power. Trainer control. Your progress, saved locally.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Demo mode", isOn: $model.demoMode)
                    if model.demoMode {
                        Label("Synthetic ride · 12× speed · never uploads", systemImage: "play.rectangle")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        ForEach(DeviceRole.allCases) { role in
                            Button { deviceRole = role } label: {
                                LabeledContent(role.title, value: model.bluetooth.names[role] ?? (role == .heartRate ? "Optional" : "Connect"))
                            }
                        }
                        if model.bluetooth.trainerCanPrepare && !model.bluetooth.trainerReady {
                            Button("Enable trainer control") {
                                Task { do { try await model.bluetooth.prepareTrainer() } catch { model.errorMessage = error.localizedDescription } }
                            }
                        }
                        Text(model.bluetooth.trainerReady ? "ERG control confirmed" : model.bluetooth.status)
                            .font(.caption).foregroundStyle(.secondary)
                        if let range = model.bluetooth.powerRange {
                            Text("Trainer range: \(range.minimum)–\(range.maximum) W, \(range.increment) W increments")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Your devices") }
                Section {
                    Picker("Existing FTP", selection: $model.ftpSelection) {
                        Text("Enter manually").tag("manual")
                        Text("No existing FTP").tag("none")
                        ForEach(model.profile.ftpHistory) { entry in
                            Text("\(Int(entry.watts.rounded())) W · \(entry.date.formatted(date: .abbreviated, time: .omitted))\(entry.id == model.profile.currentFTPID ? " · current" : "")")
                                .tag(entry.id.uuidString)
                        }
                    }
                    if model.ftpSelection == "manual" {
                        LabeledContent("Existing FTP, W") { TextField("e.g. 250", text: $model.manualFTP).numberEntry() }
                        Button("Save as current FTP", action: model.saveExistingFTP).disabled(model.manualFTP.isEmpty)
                    }
                    LabeledContent("Rider weight, kg") { TextField("e.g. 75.0", text: $model.weight).numberEntry() }
                    Text("Weight is saved with this test and used for FTP in W/kg. It does not choose your ramp protocol.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Your starting point") }
                Section {
                    Picker("Ramp rate", selection: $model.preset) {
                        ForEach(RampPreset.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Starts at \(model.preset.startingPower) W. Adds 5 W every \(Int(model.preset.stepSeconds)) seconds.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Warm-up", selection: $model.warmupMinutes) {
                        ForEach([0, 1, 5, 10, 15, 20], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    Toggle("Warm up at 50% of existing FTP", isOn: $model.automaticWarmup)
                    if !model.automaticWarmup {
                        LabeledContent("Warm-up watts") { TextField("100", text: $model.manualWarmup).numberEntry() }
                    }
                    LabeledContent("Warm-up target", value: model.warmupPreview).foregroundStyle(accent)
                    Picker("FTP estimate factor", selection: $model.ftpFactor) {
                        Text("72% · conservative").tag(0.72)
                        Text("75%").tag(0.75)
                    }
                    if model.selectedFTP == nil && model.automaticWarmup {
                        Text("No FTP selected. Using the preset's warm-up power.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Limits: 600 W or 30 minutes of ramp. Ride seated at a comfortable cadence; the ramp ends after sustained low cadence.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Test protocol") }
                Section {
                    Button {
                        Task { await model.start() }
                    } label: {
                        HStack {
                            Text(model.isStarting ? "Preparing…" : model.demoMode ? "Start demo test" : "Start ramp test")
                            Spacer(); Image(systemName: "arrow.right")
                        }.font(.headline)
                    }
                    .disabled(model.isStarting || !model.readyToStart)
                }
            }
            .disabled(model.isActive)
            .navigationTitle("FTPunk")
            .sheet(item: $deviceRole) { DevicePicker(model: model, role: $0) }
        }
    }
}

private struct DevicePicker: View {
    @Bindable var model: AppModel
    let role: DeviceRole
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Wake the sensor by pedaling. Close other apps controlling the trainer. Select the Assioma master sensor that reports total power.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Scan again") { model.bluetooth.scan() }
                    Text(model.bluetooth.status).font(.caption)
                }
                ForEach(model.bluetooth.nearby.filter { $0.roles.contains(role) }) { device in
                    Button {
                        model.bluetooth.connect(device, as: role); dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("\(device.signal) dBm · \(device.id.uuidString.suffix(8))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.bluetooth.names[role] != nil {
                    Button("Disconnect \(role.title)", role: .destructive) { model.bluetooth.disconnect(role); dismiss() }
                }
            }
            .navigationTitle(role.title)
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { model.bluetooth.scan() }
            .onDisappear { model.bluetooth.stopScanning() }
        }
    }
}

private struct RideView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationStack {
            ScrollView {
                if let engine = model.engine {
                    VStack(spacing: 24) {
                        if engine.session.isDemo {
                            Label("DEMO · SYNTHETIC DATA", systemImage: "play.rectangle.fill")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                        HStack {
                            Text(engine.phase.title.uppercased()).font(.headline).foregroundStyle(accent)
                            Spacer(); Text(time(model.elapsed)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        VStack(spacing: 0) {
                            Text(engine.lastPower.map { "\(Int($0.watts.rounded()))" } ?? "—")
                                .font(.system(size: 90, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("PEDAL WATTS").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 24) {
                            Metric(title: "TARGET", value: engine.targetPower.map { "\($0) W" } ?? "—")
                            Metric(title: "CADENCE", value: engine.lastCadence.map { "\(Int($0.rpm)) rpm" } ?? "—")
                            Metric(title: "HEART RATE", value: model.heartRate.map { "\($0) bpm" } ?? "—")
                        }
                        if engine.phase == .warmup {
                            Text("Ramp begins in \(time(max(0, engine.session.configuration.warmupSeconds - (model.elapsed - engine.phaseStartedAt))))")
                        } else if engine.phase == .ramp {
                            let step = engine.session.configuration.preset.stepSeconds
                            Text("Next +5 W in \(Int(ceil(step - (model.elapsed - engine.phaseStartedAt).truncatingRemainder(dividingBy: step)))) s")
                        }
                        PowerChart(samples: engine.session.samples)
                        if let result = engine.session.result { ResultCard(result: result) }
                        if let reason = engine.session.endReason { Text(reason).foregroundStyle(.orange) }
                        if engine.phase == .ramp {
                            Button("Finish ramp · begin cooldown", action: model.finishRamp).buttonStyle(.bordered)
                        }
                        if model.isActive {
                            Button("Stop and save", role: .destructive, action: model.stop)
                                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                        } else {
                            Text("\(engine.session.outcome?.title ?? "Finished") · saved locally")
                                .foregroundStyle(.secondary)
                            Button("Set up another test") { model.selectedTab = 0 }
                        }
                    }.padding(24).frame(maxWidth: 850)
                } else {
                    ContentUnavailableView("Ready when you are", systemImage: "bicycle",
                                           description: Text("Configure a ramp test or try the demo from Test setup."))
                        .padding(.top, 80)
                }
            }.navigationTitle("Your test")
        }
    }
    private func time(_ seconds: Double) -> String { "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))" }
}

private struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct PowerChart: View {
    let samples: [RideSample]
    var body: some View {
        Chart {
            ForEach(Array(samples.enumerated()), id: \.offset) { item in
                if let power = item.element.power {
                    LineMark(x: .value("Minutes", item.element.time / 60), y: .value("Watts", power))
                        .foregroundStyle(accent)
                }
            }
        }.chartXAxisLabel("Minutes").chartYAxisLabel("W").frame(height: 180)
    }
}

private struct ResultCard: View {
    let result: FTPResult
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ESTIMATED FTP").font(.caption.bold()).foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(result.estimatedFTP.rounded())) W").font(.largeTitle.bold())
                if let wkg = result.wattsPerKG { Text("\(wkg, specifier: "%.2f") W/kg").font(.title3).foregroundStyle(.secondary) }
            }
            Text("Range: \(Int(result.lowerFTP.rounded()))–\(Int(result.upperFTP.rounded())) W")
            Text("\(Int(result.factor * 100))% of your best 60 seconds (\(Int(result.bestMinutePower.rounded())) W). A training estimate, not a measured physiological threshold.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct HistoryView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                if model.history.isEmpty {
                    ContentUnavailableView("Your first test starts here", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Completed tests and interrupted recordings appear here."))
                }
                ForEach(model.history) { session in
                    NavigationLink { SessionDetail(model: model, session: session) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.isDemo ? "Demo test" : session.outcome?.title ?? "Recording").font(.headline)
                                Spacer()
                                if let ftp = session.result?.estimatedFTP { Text("\(Int(ftp.rounded())) W").foregroundStyle(accent) }
                            }
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Delete", role: .destructive) { model.delete(session) } }
                }
            }.navigationTitle("Test history")
        }
    }
}

private struct SessionDetail: View {
    @Bindable var model: AppModel
    let session: TestSession
    @ViewState private var exportURL: URL? = nil
    var body: some View {
        List {
            if session.isDemo { Label("Demo · synthetic data", systemImage: "play.rectangle").foregroundStyle(.orange) }
            if let result = session.result {
                ResultCard(result: result)
                if !session.isDemo { Button("Use this estimate as my current FTP") { model.adopt(session) } }
            } else { Text("No valid FTP estimate. A continuous 60-second ramp window is required.") }
            Section("This test") {
                LabeledContent("Protocol", value: session.configuration.preset.title)
                LabeledContent("Existing FTP", value: session.configuration.priorFTP.map { "\(Int($0.watts.rounded())) W" } ?? "Not provided")
                LabeledContent("Session weight", value: session.configuration.weightKG.map { "\($0) kg" } ?? "Not provided")
                LabeledContent("Warm-up", value: "\(session.configuration.warmupPower) W")
                LabeledContent("Outcome", value: session.outcome?.title ?? "Recording")
                if let reason = session.endReason { Text(reason).foregroundStyle(.orange) }
                PowerChart(samples: session.samples)
            }
            Section("Export") {
                ForEach(["tcx", "csv", "json"], id: \.self) { kind in
                    Button("Prepare \(kind.uppercased()) file") { exportURL = model.export(session, kind: kind) }
                }
                if let exportURL { ShareLink("Share \(exportURL.pathExtension.uppercased())", item: exportURL) }
            }
            if !session.isDemo && session.endedAtOffset != nil {
                Section("Intervals.icu") {
                    if let job = model.jobs.first(where: { $0.sessionID == session.id }) {
                        Text("Upload: \(job.status.rawValue)")
                        if let error = job.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button("Upload activity") { Task { await model.upload(session) } }.disabled(model.connection == nil)
                }
            }
        }.navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
    }
}

private struct SettingsView: View {
    @Bindable var model: AppModel
    @ViewState private var captureURL: URL? = nil
    var body: some View {
        NavigationStack {
            Form {
                Section("Intervals.icu") {
                    if let connection = model.connection {
                        LabeledContent("Connected", value: connection.athleteName)
                        Toggle("Automatically upload saved activities", isOn: $model.autoUpload)
                        Button("Retry pending uploads") { Task { await model.flushUploads(manual: true) } }
                        Button("Disconnect", role: .destructive, action: model.disconnectIntervals)
                    } else {
                        SecureField("Personal API key", text: $model.apiKeyInput)
                        Text("For your private app, use your own key from Intervals.icu → Settings → Developer settings. It is stored in Keychain.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(model.connecting ? "Connecting…" : "Connect Intervals.icu") { Task { await model.connectIntervals() } }
                            .disabled(model.apiKeyInput.isEmpty || model.connecting)
                    }
                    Text("Uploads happen after cooldown and saving. Offline activities wait for a retry. Demo rides never upload. Disconnecting leaves already uploaded activities on Intervals.icu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Bluetooth diagnostics") {
                    Toggle("Capture Bluetooth packets", isOn: Binding(get: { model.bluetooth.captureEnabled }, set: { model.bluetooth.captureEnabled = $0 }))
                    Picker("Trainer resistance field", selection: Binding(get: { model.bluetooth.resistanceLayout }, set: { model.bluetooth.resistanceLayout = $0 })) {
                        Text("Standard · 1 byte").tag(ResistanceLayout.standardOneByte)
                        Text("Reference layout · 2 bytes").tag(ResistanceLayout.legacyTwoBytes)
                    }.disabled(model.isActive)
                    Text("Use the standard layout unless a capture confirms your trainer needs the reference layout. No automatic guessing. Captures contain the latest 500 received packets and stay on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Prepare packet capture") { captureURL = model.captureFile() }
                    if let captureURL { ShareLink("Share packet capture", item: captureURL) }
                }
                Section("Local by default") {
                    Text("Bluetooth readings and test history stay on this device. Intervals.icu is optional. No COROS auto-upload is included.")
                        .foregroundStyle(.secondary)
                    Text("Hardware prototype: validate trainer control and stop behavior at a low load before a maximal test.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.navigationTitle("Connections")
        }
    }
}

private extension View {
    @ViewBuilder func numberEntry() -> some View {
        #if canImport(UIKit)
        self.keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        #else
        self.multilineTextAlignment(.trailing)
        #endif
    }
}
