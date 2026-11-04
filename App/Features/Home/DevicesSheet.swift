import SwiftUI
import FTPunkDomain
import FTPunkDevices

/// One shared place for trainer, power meter and heart-rate connections.
struct DevicesSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var role: DeviceRole?
    @State private var showMatchingInfo = false

    private var meterConnected: Bool { model.bluetooth.names[.pedals] != nil }
    private var powerMode: Binding<PowerMode> {
        Binding(
            get: { PowerMode.resolve(powerSource: model.powerSource, matchingEnabled: model.powerMatchingEnabled, meterConnected: meterConnected) },
            set: { mode in
                let values = mode.settings(currentMatching: model.powerMatchingEnabled)
                model.powerSource = values.powerSource
                model.powerMatchingEnabled = values.matchingEnabled
            })
    }

    /// "Trainer reads 4 % high at 200 W", from this ride's estimate (or the last ride's, once it is over).
    private var trainerReading: String? {
        guard case .matching = model.powerMatcher.status, let error = model.powerMatcher.trainerError(atReported: 200) else { return nil }
        let percent = Int((abs(error) * 100).rounded())
        let text = percent == 0 ? "Trainer reads about right at 200 W" : "Trainer reads \(percent) % \(error > 0 ? "high" : "low") at 200 W"
        return model.isBusy ? text : "Last ride: " + text.prefix(1).lowercased() + text.dropFirst()
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.demoMode {
                    Section {
                        Label("Mock sensor stream · never uploads", systemImage: "play.rectangle").foregroundStyle(Theme.warning)
                        Text("Debug mode simulates a trainer, power, cadence and heart rate. No Bluetooth commands are sent.")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                    }
                } else {
                    Section("Connections") {
                        ForEach([DeviceRole.trainer, .pedals, .heartRate]) { role in
                            DeviceStatusRow(role: role, connectedName: model.bluetooth.names[role],
                                            detail: role == .trainer ? (model.bluetooth.trainerReady ? "ERG ready" : model.bluetooth.status) : nil) { self.role = role }
                                .disabled(model.isBusy)
                        }
                    }
                    Section {
                        if meterConnected {
                            SelectionRow("Power source", selection: powerMode) {
                                ForEach(PowerMode.allCases) { Text($0.title).tag($0) }
                            }.disabled(model.isBusy)
                        } else {
                            Text("Power: measured by the trainer")
                        }
                        LabeledContent("Cadence", value: model.cadenceSource.title)
                        if let reading = trainerReading { Text(reading).font(.footnote).foregroundStyle(Theme.secondary) }
                        Button { showMatchingInfo = true } label: { Label("About power matching", systemImage: "info.circle") }
                    } header: { Text("Measurement") } footer: { Text("Fixed when a ride starts.") }
                    Section("Trainer control") {
                        if model.bluetooth.trainerCanPrepare && !model.bluetooth.trainerReady {
                            Button("Enable trainer control") {
                                Task { do { try await model.bluetooth.prepareTrainer() } catch { model.errorMessage = error.localizedDescription } }
                            }
                        }
                        Label(model.bluetooth.trainerReady ? "ERG control confirmed" : model.bluetooth.status,
                              systemImage: model.bluetooth.trainerReady ? "checkmark.shield" : "antenna.radiowaves.left.and.right")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                        if let range = model.bluetooth.powerRange {
                            Text("Trainer: \(range.minimum)–\(range.maximum) W · \(range.increment) W increments").font(.footnote)
                        }
                    }
                }
            }
            .formStyle(.grouped).buttonStyle(FTPunkRowButtonStyle())
            .navigationTitle("Devices")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $role) { DevicePicker(model: model, role: $0) }
            .sheet(isPresented: $showMatchingInfo) { LearnMoreSheet(topic: .powerMatching) }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 480)
        #endif
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
                        .font(.callout).foregroundStyle(Theme.secondary)
                    Button("Scan again") { model.bluetooth.scan() }
                    Text(model.bluetooth.status).font(.footnote)
                }
                ForEach(model.bluetooth.nearby.filter { $0.roles.contains(role) }) { device in
                    Button {
                        model.bluetooth.connect(device, as: role)
                        if role == .pedals { model.powerSource = .externalPowerMeter }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("\(device.signal) dBm · \(device.id.uuidString.suffix(8))").font(.footnote).foregroundStyle(Theme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                }
                if model.bluetooth.names[role] != nil {
                    Button("Disconnect \(role.title)", role: .destructive) {
                        model.bluetooth.disconnect(role)
                        if role == .pedals { model.powerSource = .trainer }
                        dismiss()
                    }
                }
            }.buttonStyle(FTPunkRowButtonStyle())
                .navigationTitle(role.title).toolbar { Button("Done") { dismiss() } }
                .onAppear { model.bluetooth.scan() }.onDisappear { model.bluetooth.stopScanning() }
        }
    }
}
