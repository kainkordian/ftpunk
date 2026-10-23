import SwiftUI
import FTPunkDomain
import FTPunkDevices

private enum SetupStage: Int, CaseIterable {
    case rider, protocolChoice, ready
    var title: String {
        switch self { case .rider: "Rider"; case .protocolChoice: "Protocol"; case .ready: "Ready" }
    }
}

struct SetupView: View {
    @Bindable var model: AppModel
    private var stage: SetupStage {
        get { SetupStage(rawValue: model.setupStep) ?? .rider }
        nonmutating set { model.setupStep = newValue.rawValue }
    }
    @ViewState private var deviceRole: DeviceRole? = nil
    @ViewState private var info: TestInfo? = nil
    @ViewState private var addingRider = false
    @ViewState private var newName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    ForEach(SetupStage.allCases, id: \.rawValue) { item in
                        Label(item.title, systemImage: item.rawValue < stage.rawValue ? "checkmark.circle.fill" : "\(item.rawValue + 1).circle\(item == stage ? ".fill" : "")")
                            .font(.subheadline.weight(item == stage ? .bold : .regular))
                            .foregroundStyle(item == stage ? Theme.accent : .secondary)
                        if item != .ready { Spacer() }
                    }
                }.padding()
                Form {
                    switch stage {
                    case .rider: riderSections
                    case .protocolChoice: protocolSections
                    case .ready: readySections
                    }
                }.formStyle(.grouped)
                HStack {
                    if stage != .rider {
                        Button("Back") { stage = SetupStage(rawValue: stage.rawValue - 1)! }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    if stage == .ready {
                        Button { Task { await model.start() } } label: {
                            Label(model.isStarting ? "Preparing…" : model.demoMode ? "Start debug test" : "Start ramp test", systemImage: "play.fill")
                        }
                        .disabled(model.isStarting || !model.readyToStart)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            if stage != .rider || model.saveRiderDetails() {
                                stage = SetupStage(rawValue: stage.rawValue + 1)!
                            }
                        } label: { Label("Continue", systemImage: "arrow.right") }
                        .buttonStyle(.borderedProminent)
                    }
                }.controlSize(.large).padding().background(.bar)
            }
            .disabled(model.isActive)
            .navigationTitle("New test")
            .toolbar { Button { info = .protocols } label: { Image(systemName: "info.circle") }.accessibilityLabel("About ramp tests") }
            .sheet(item: $deviceRole) { DevicePicker(model: model, role: $0) }
            .sheet(item: $info) { ProtocolInfoView(topic: $0) }
            .sheet(isPresented: $addingRider) {
                NavigationStack {
                    Form {
                        TextField("Rider's name", text: $newName)
                        Text("Each rider has separate FTP settings, weight and test history. Intervals.icu is a shared connection; every upload asks you to confirm its destination.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.formStyle(.grouped).navigationTitle("Add rider")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingRider = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { if model.addRider(name: newName) { addingRider = false; newName = "" } }
                                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                }.frame(minWidth: 320, idealWidth: 460, minHeight: 260)
            }
        }
    }

    @ViewBuilder private var riderSections: some View {
        Section {
            Text("Who’s riding?").font(.title2.bold())
            Text("Choose a rider, then check their starting point. These values are saved with the test.").foregroundStyle(.secondary)
        }
        Section("Rider") {
            Picker("Saved rider", selection: $model.selectedRiderID) {
                ForEach(model.riders) { Text($0.name).tag($0.id) }
            }
            TextField("Rider's name", text: $model.riderName)
            Button { addingRider = true } label: { Label("Add another rider", systemImage: "person.badge.plus") }
        }
        Section("Starting point") {
            Picker("Existing FTP", selection: $model.ftpSelection) {
                Text("Enter manually").tag("manual")
                Text("No existing FTP").tag("none")
                ForEach(model.profile.ftpHistory) { entry in
                    Text("\(Int(entry.watts.rounded())) W · \(entry.date.formatted(date: .abbreviated, time: .omitted))\(entry.id == model.profile.currentFTPID ? " · current" : "")")
                        .tag(entry.id.uuidString)
                }
            }
            if model.ftpSelection == "manual" {
                LabeledContent("Existing FTP, W") { TextField("Optional", text: $model.manualFTP).numberEntry() }
                Button("Save as this rider’s current FTP", action: model.saveExistingFTP).disabled(model.manualFTP.isEmpty)
            }
            LabeledContent("Rider weight, kg") { TextField("Optional", text: $model.weight).numberEntry() }
            Text("FTP sets the default warm-up target. Weight is used for the result in W/kg; it never changes your protocol automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var protocolSections: some View {
        Section {
            Text("Choose your ramp").font(.title2.bold())
            ForEach([RampPreset.gentle, .standard, .zwift]) { preset in
                Button { model.preset = preset } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.preset == preset ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(model.preset == preset ? Theme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(preset.title).font(.headline).foregroundStyle(.primary)
                            Text(preset.summary).foregroundStyle(.primary)
                            Text(preset.audience).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Button { info = .protocols } label: { Label("Which protocol, and why?", systemImage: "info.circle") }
        }
        Section("Warm-up") {
            LabeledContent("Target", value: model.warmupPreview)
            if model.demoMode && model.quickDebugTest {
                Text("10 seconds in quick debug mode").foregroundStyle(.secondary)
            } else {
                Picker("Duration", selection: $model.warmupMinutes) {
                    ForEach([0, 1, 5, 10, 15, 20], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }
            DisclosureGroup("Customize warm-up") {
                Toggle("Use 50% of existing FTP", isOn: $model.automaticWarmup)
                if !model.automaticWarmup {
                    LabeledContent("Target watts") { TextField("100", text: $model.manualWarmup).numberEntry() }
                }
                if model.selectedFTP == nil && model.automaticWarmup {
                    Text("No FTP selected: using the protocol’s fallback target.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section("FTP estimate") {
            Picker("Factor", selection: $model.ftpFactor) {
                Text("72% · conservative").tag(0.72)
                Text("75% · common app estimate").tag(0.75)
            }
            Button { info = .estimate } label: { Label("Why the 72–77% range?", systemImage: "info.circle") }
        }
    }

    @ViewBuilder private var readySections: some View {
        Section("Your test") {
            LabeledContent("Rider", value: model.riderName)
            LabeledContent("Protocol", value: model.preset.title)
            LabeledContent("Warm-up", value: model.warmupPreview)
            LabeledContent("FTP factor", value: "\(Int(model.ftpFactor * 100))%")
            Text("Stay seated and hold a comfortable, steady cadence. The trainer sets the load; the selected power source measures the result.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Devices") {
            Toggle("Debug mode · no devices", isOn: $model.demoMode)
            if model.demoMode {
                Label("Mock sensor stream · never uploads", systemImage: "play.rectangle").foregroundStyle(.orange)
                DisclosureGroup("Debug options") {
                    Toggle("Quick warm-up and cooldown · 10 s", isOn: $model.quickDebugTest)
                    Picker("Playback speed", selection: $model.mockSpeed) {
                        ForEach([1.0, 4.0, 12.0, 60.0], id: \.self) { Text("\(Int($0))×").tag($0) }
                    }
                }
            } else {
                ForEach([DeviceRole.trainer, .heartRate]) { role in
                    Button { deviceRole = role } label: {
                        LabeledContent(role.title, value: model.bluetooth.names[role] ?? (role == .heartRate ? "Optional" : "Connect"))
                    }
                }
                Picker("Power source", selection: $model.powerSource) {
                    Text("Trainer · no extra sensor").tag(PowerSource.trainer)
                    Text("External power meter · optional").tag(PowerSource.externalPowerMeter)
                }
                if model.powerSource == .externalPowerMeter {
                    Button { deviceRole = .pedals } label: {
                        LabeledContent("External power meter", value: model.bluetooth.names[.pedals] ?? "Connect")
                    }
                }
                Text("An external power meter is a separate sensor on your pedals, crank or hub. You can use your trainer’s own power measurement instead.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Cadence source", value: model.cadenceSource.title)
                if model.cadenceSource == .unavailable {
                    Text("No fresh cadence signal. Automatic low-cadence finishing is disabled: tap Finish ramp when you cannot continue. Power recording and test limits still work.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.bluetooth.trainerCanPrepare && !model.bluetooth.trainerReady {
                    Button("Enable trainer control") {
                        Task { do { try await model.bluetooth.prepareTrainer() } catch { model.errorMessage = error.localizedDescription } }
                    }
                }
                Label(model.bluetooth.trainerReady ? "ERG control confirmed" : model.bluetooth.status,
                      systemImage: model.bluetooth.trainerReady ? "checkmark.shield" : "antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
                if let range = model.bluetooth.powerRange {
                    Text("Trainer: \(range.minimum)–\(range.maximum) W · \(range.increment) W increments").font(.caption)
                }
            }
        }
        Section("After the test") {
            Text(model.connection.map { "Saved locally first. We’ll ask before uploading to \($0.athleteName) on Intervals.icu." }
                 ?? "Results stay on this device. Connect Intervals.icu in Settings to upload an activity.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Test limits: 600 W or 30 minutes of ramp. Stop at any time.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DevicePicker: View {
    @Bindable var model: AppModel
    let role: DeviceRole
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(role == .pedals
                         ? "Wake the meter by pedaling. Choose a Bluetooth Cycling Power sensor. For dual-sided pedals, select the master sensor that reports total power."
                         : "Wake the sensor and close other apps controlling the trainer.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Scan again") { model.bluetooth.scan() }
                    Text(model.bluetooth.status).font(.caption)
                }
                ForEach(model.bluetooth.nearby.filter { $0.roles.contains(role) }) { device in
                    Button {
                        model.bluetooth.connect(device, as: role)
                        if role == .pedals { model.powerSource = .externalPowerMeter }
                        dismiss()
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
            }.navigationTitle(role.title).toolbar { Button("Done") { dismiss() } }
                .onAppear { model.bluetooth.scan() }.onDisappear { model.bluetooth.stopScanning() }
        }
    }
}
