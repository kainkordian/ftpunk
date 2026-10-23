import SwiftUI
import FTPunkDevices

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @ViewState private var captureURL: URL? = nil
    @ViewState private var info: TestInfo? = nil
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                }
                Section("Intervals.icu") {
                    if let connection = model.connection {
                        LabeledContent("Connected account", value: connection.athleteName)
                        Text(connection.usesOAuth ? "Connected with secure sign-in" : "Connected with a personal API key")
                            .font(.caption).foregroundStyle(.secondary)
                        Label("Ask before every new activity upload", systemImage: "checkmark.bubble")
                        Text("Each prompt names the rider and the destination account. Previously approved queued uploads retry when online.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Retry approved pending uploads") { Task { await model.flushUploads(manual: true) } }
                        Button("Disconnect", role: .destructive) { Task { await model.disconnectIntervals() } }
                    } else {
                        Button { Task { await model.connectIntervals() } } label: {
                            Label(model.connecting ? "Connecting…" : "Sign in to Intervals.icu", systemImage: "person.crop.circle.badge.checkmark")
                        }.buttonStyle(.borderedProminent).disabled(model.connecting)
                        Text("Sign in on Intervals.icu’s page and approve activity uploads. FTPunk never sees your password.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !model.oauthConfigured {
                            Text("Sign-in awaits FTPunk’s app registration approval. You can connect with your API key below today.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Connect with an API key") {
                            Text("In Intervals.icu, open Settings → Developer settings and copy your personal API key. FTPunk stores it securely in Keychain.")
                                .font(.caption).foregroundStyle(.secondary)
                            Link("Open Intervals.icu settings", destination: URL(string: "https://intervals.icu/settings")!)
                            SecureField("Personal API key", text: $model.apiKeyInput)
                            Button(model.connecting ? "Connecting…" : "Connect with API key") { Task { await model.connectIntervalsWithAPIKey() } }
                                .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.connecting)
                        }
                    }
                    Text("Tests are saved locally first. Debug tests never upload. Disconnecting leaves activities already uploaded on Intervals.icu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Learn about the test") {
                    Button { info = .protocols } label: { Label("Protocols and rider guidelines", systemImage: "info.circle") }
                    Button { info = .estimate } label: { Label("Understanding the 72–77% estimate", systemImage: "percent") }
                }
                Section("Bluetooth diagnostics") {
                    DisclosureGroup("Advanced options") {
                        Toggle("Capture Bluetooth packets", isOn: Binding(get: { model.bluetooth.captureEnabled }, set: { model.bluetooth.captureEnabled = $0 }))
                        Picker("Trainer resistance field", selection: Binding(get: { model.bluetooth.resistanceLayout }, set: { model.bluetooth.resistanceLayout = $0 })) {
                            Text("Standard · 1 byte").tag(ResistanceLayout.standardOneByte)
                            Text("Reference layout · 2 bytes").tag(ResistanceLayout.legacyTwoBytes)
                        }.disabled(model.isActive)
                        Text("Use the standard layout unless a packet capture confirms the reference layout. Captures keep the latest 500 packets locally.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Prepare packet capture") { captureURL = model.captureFile() }
                        if let captureURL { ShareLink("Share packet capture", item: captureURL) }
                    }
                }
                Section("Local by default") {
                    Text("Riders, recordings and FTP history stay on this device unless you approve an upload. iPhone and Mac history are independent; cloud sync can be added later.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Hardware prototype: validate trainer control and stop behavior at a low load before a maximal test.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).navigationTitle("Settings")
                .sheet(item: $info) { ProtocolInfoView(topic: $0) }
        }
    }
}
