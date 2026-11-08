import SwiftUI
import FTPunkDomain
import FTPunkDevices
#if os(macOS)
import AppKit
#endif

/// Settings are grouped and short: one line of footer text per group, with "Learn more" sheets for detail.
enum SettingsGroup: String, CaseIterable, Identifiable {
    case riders, devices, rideDisplay, intervals, backup, debug, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .riders: "Riders"
        case .devices: "Devices"
        case .rideDisplay: "Ride display"
        case .intervals: "Intervals.icu"
        case .backup: "Backup & transfer"
        case .debug: "Debug"
        case .about: "About"
        }
    }
    /// Debug stays hidden until the rider unlocks it from About.
    static func visible(debugUnlocked: Bool) -> [SettingsGroup] { allCases.filter { $0 != .debug || debugUnlocked } }
}

enum SettingsTopic: String, Identifiable {
    case riders, powerMatching, intervals, privacy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .riders: "Riders"
        case .powerMatching: "Power matching"
        case .intervals: "Intervals.icu"
        case .privacy: "Your data"
        }
    }
    var paragraphs: [String] {
        switch self {
        case .riders: [
            "Each rider has their own FTP history, weight and recordings. Choose the rider from the chip on Home; this list manages the others.",
            "An adopted test result updates the rider who took the test, even when someone else is selected."]
        case .powerMatching: [
            "With an external power meter, power matching makes the meter read the workout target. A trainer's own reading depends on when it was last calibrated, the room temperature and how warm it is, so FTPunk measures that error against your pedals all ride long. It starts from nothing each ride and keeps no profile between rides.",
            "It never makes a ramp harder when you fade: if the trainer cannot hold its own target, the correction is frozen and cannot grow. It also pauses while you stop pedalling or your cadence drops. The choice is fixed when a ride starts, and without an external meter the trainer controls power using its own measurement.",
            "For the best starting point, calibrate the trainer (spin-down in Elite's app) after about 10 minutes of riding. Turn off Elite's Power Meter Link while matching is on. Validate the response at a low load before a maximal test."]
        case .intervals: [
            "Connecting lets FTPunk download your planned workouts for the next 14 days and, only after you confirm each time, upload a finished ride. The confirmation names the rider and the Intervals.icu account.",
            "Your key is stored in the Keychain and never leaves it in backups. Uploads never change your FTP, weight or wellness settings on Intervals.icu.",
            "FTPunk reads your FTP and weight from Intervals.icu for the linked rider; you can still change them here. A value is only replaced when it changes on Intervals.icu."]
        case .privacy: [
            "Riders, recordings and FTP history stay on this device unless you approve an upload. iPhone, Mac and web history are independent; backups move them by hand.",
            "This is a hardware prototype: validate trainer control and Stop at a low load before a maximal test."]
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("extraLargeRideNumbers") private var extraLargeRideNumbers = false
    @State private var captureURL: URL?
    @State private var topic: SettingsTopic?
    @State private var info: TestInfo?
    @State private var showRiders = false
    @State private var showDevices = false
    @State private var deviceRole: DeviceRole?
    @State private var apiKeyExpanded = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                Form {
                    ForEach(orderedGroups) { group in
                        content(for: group)
                    }
                }
                .formStyle(.grouped).buttonStyle(FTPunkRowButtonStyle()).navigationTitle("Settings")
                .scrollDismissesKeyboard(.interactively)
                .sheet(item: $topic) { LearnMoreSheet(topic: $0) }
                .sheet(item: $info) { ProtocolInfoView(topic: $0) }
                .sheet(isPresented: $showRiders) { RiderSheet(model: model) }
                .sheet(isPresented: $showDevices) { DevicesSheet(model: model) }
                .sheet(item: $deviceRole) { DevicePicker(model: model, role: $0) }
                .task(id: model.previewSettingsAnchor) {
                    if let anchor = model.previewSettingsAnchor {
                        apiKeyExpanded = true
                        try? await Task.sleep(for: .milliseconds(300))
                        scroll.scrollTo(anchor, anchor: .top)
                    }
                }
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--preview-about") {
                        try? await Task.sleep(for: .milliseconds(300))
                        scroll.scrollTo("app-about", anchor: .center)
                    }
                }
            }
        }
    }

    /// Preview captures put the requested group first (a grouped Form on macOS does not scroll to a section).
    private var orderedGroups: [SettingsGroup] {
        let groups = SettingsGroup.visible(debugUnlocked: model.debugUnlocked)
        #if os(iOS)
        // The iOS Form scrolls to the section (see the task above), so the order stays the real one.
        return groups
        #else
        guard let anchor = model.previewSettingsAnchor, let first = groups.first(where: { $0.rawValue == anchor }) else { return groups }
        return [first] + groups.filter { $0 != first }
        #endif
    }

    @ViewBuilder private func content(for group: SettingsGroup) -> some View {
        // About keeps its own id ("app-about") for the --preview-about capture.
        if group == .about { groupContent(group) } else { groupContent(group).id(group.rawValue) }
    }

    @ViewBuilder private func groupContent(_ group: SettingsGroup) -> some View {
        switch group {
        case .riders: ridersSection
        case .devices: devicesSection
        case .rideDisplay: rideDisplaySection
        case .intervals: intervalsSection
        case .backup: ArchiveTransferView(model: model)
        case .debug: debugSections
        case .about: aboutSection
        }
    }

    private func learnMore(_ topic: SettingsTopic) -> some View {
        Button { self.topic = topic } label: { Label("Learn more", systemImage: "info.circle") }
    }

    // MARK: Groups

    private var ridersSection: some View {
        Section {
            ForEach(model.riders) { rider in
                LabeledContent(rider.name, value: rider.currentFTP.map { "FTP \(Int($0.watts.rounded())) W" } ?? "No FTP yet")
            }
            Button { showRiders = true } label: { Label("Manage riders…", systemImage: "person.2") }
            learnMore(.riders)
        } header: { Text(SettingsGroup.riders.title) } footer: { Text("Each rider keeps separate FTP, weight and history.") }
    }

    private var devicesSection: some View {
        Section {
            if model.demoMode {
                Label("Mock sensor stream · never uploads", systemImage: "play.rectangle").foregroundStyle(Theme.warning)
            } else {
                ForEach([DeviceRole.trainer, .pedals, .heartRate]) { role in
                    DeviceStatusRow(role: role, connectedName: model.bluetooth.names[role],
                                    detail: role == .trainer ? (model.bluetooth.trainerReady ? "ERG ready" : model.bluetooth.status) : nil) { deviceRole = role }
                        .disabled(model.isBusy)
                }
            }
            Button { showDevices = true } label: { Label("Measurement & trainer control…", systemImage: "slider.horizontal.3") }
            learnMore(.powerMatching)
        } header: { Text(SettingsGroup.devices.title) } footer: {
            Text("A smart trainer with ERG control is required. A power meter and a heart rate monitor are optional.")
        }
    }

    private var rideDisplaySection: some View {
        Section {
            if dynamicTypeSize.isAccessibilitySize {
                SelectionRow("Theme", selection: $appearance) { ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) } }
            } else {
                Picker("Theme", selection: $appearance) { ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) } }
                    .pickerStyle(.segmented).tint(Theme.controlTint)
            }
            Toggle("Extra-large ride numbers", isOn: $extraLargeRideNumbers)
            Toggle("Pause workouts when I stop pedaling", isOn: $model.autoPauseEnabled).accessibilityIdentifier("auto-pause-toggle")
            Toggle("Show \(RideVisualBranding.name) during rides", isOn: $model.rideVisualEnabled).accessibilityIdentifier("pixel-ride-toggle")
            if model.rideVisualEnabled {
                SelectionRow("\(RideVisualBranding.name) layout", selection: $model.rideVisualPlacement) {
                    Text("Strip between the readings").tag(RideVisualPlacement.strip)
                    Text("Large scene with readings on top").tag(RideVisualPlacement.hero)
                }
            }
        } header: { Text(SettingsGroup.rideDisplay.title) } footer: {
            Text("Numbers follow your system text size; extra-large is easier to read from the bike. \(RideVisualBranding.name) is a neon night-city ride that follows your power. It never controls the trainer. You can also change it during a ride. Increase Contrast, Bold Text and Reduce Motion are supported.")
        }
    }

    @ViewBuilder private var intervalsSection: some View {
        Section {
            if let connection = model.connection {
                LabeledContent("Connected as \(connection.athleteName)", value: "for \(model.profile.name)")
                Text(connection.usesOAuth ? "Connected with secure sign-in" : "Connected with a personal API key").font(.footnote).foregroundStyle(Theme.secondary)
                Toggle("Ask to upload after each ride", isOn: $model.askToUploadAfterRide)
                Text("Every upload still needs your confirmation. With this off you can upload from the result screen or an activity.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                athleteSyncRows
                Button("Retry approved pending uploads") { Task { await model.flushUploads(manual: true) } }
                Button("Disconnect", role: .destructive) { Task { await model.disconnectIntervals() } }
            } else {
                DisclosureGroup("Connect with an API key", isExpanded: $apiKeyExpanded) {
                    Text("In Intervals.icu, open Settings → Developer settings and copy your personal API key. FTPunk stores it securely in Keychain.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    Link(destination: URL(string: "https://intervals.icu/settings")!) {
                        Label("Open Intervals.icu settings", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    LabeledContent("API key") {
                        HStack(spacing: Space.s) {
                            // macOS draws a SecureField's title as a separate label inside a Form; use a hidden label and a prompt.
                            SecureField("API key", text: $model.apiKeyInput, prompt: Text("Paste your personal API key"))
                                .labelsHidden()
                                .multilineTextAlignment(.leading)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 260, maxWidth: .infinity)
                                #if os(iOS)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                #endif
                            #if os(macOS)
                            Button {
                                if let text = NSPasteboard.general.string(forType: .string) { model.apiKeyInput = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                            } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                                .buttonStyle(.bordered)
                            #else
                            PasteButton(payloadType: String.self) { strings in
                                if let text = strings.first { model.apiKeyInput = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                            }
                            #endif
                        }
                    }
                    Button(model.connecting ? "Connecting…" : "Connect with API key") { Task { await model.connectIntervalsWithAPIKey() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.connecting)
                }
            }
            learnMore(.intervals)
        } header: { Text(SettingsGroup.intervals.title) } footer: {
            Text("Each rider has their own Intervals.icu connection. Rides are saved locally first. Every upload asks you to confirm the rider and account. Debug rides never upload.")
        }
    }

    @ViewBuilder private var athleteSyncRows: some View {
        Toggle("Use FTP and weight from Intervals.icu", isOn: Binding(get: { model.athleteSync.enabled }, set: { model.setAthleteSyncEnabled($0) }))
        if model.athleteSync.enabled {
            if model.athleteSyncNeedsReconnect {
                Text("Disconnect and connect again to allow reading FTP and weight. Nothing else is needed.").font(.footnote).foregroundStyle(Theme.secondary)
            } else {
                LabeledContent("Last synced", value: model.athleteSync.lastSynced.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
            }
            if let note = model.athleteSyncNote { Text(note).font(.footnote).foregroundStyle(Theme.accent) }
            Button(model.athleteSyncing ? "Syncing…" : "Sync now") { Task { await model.syncAthleteSettings(manual: true) } }
                .disabled(model.isBusy || model.athleteSyncing)
        }
    }

    @ViewBuilder private var debugSections: some View {
        Section {
            Toggle("Mock sensors · no cycling devices", isOn: $model.demoMode).disabled(model.isBusy)
            Button("Hide debug tools", action: model.hideDebugTools).disabled(model.isBusy)
            DisclosureGroup("Bluetooth diagnostics") {
                Toggle("Capture Bluetooth packets", isOn: Binding(get: { model.bluetooth.captureEnabled }, set: { model.bluetooth.captureEnabled = $0 }))
                SelectionRow("Trainer resistance field", selection: Binding(get: { model.bluetooth.resistanceLayout }, set: { model.bluetooth.resistanceLayout = $0 })) {
                    Text("Standard · 1 byte").tag(ResistanceLayout.standardOneByte)
                    Text("Reference layout · 2 bytes").tag(ResistanceLayout.legacyTwoBytes)
                }.disabled(model.isBusy)
                Text("Use the standard layout unless a packet capture confirms the reference layout. Captures keep the latest 500 packets locally.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                Button("Prepare packet capture") { captureURL = model.captureFile() }
                if let captureURL { ShareLink("Share packet capture", item: captureURL) }
            }
        } header: { Label(SettingsGroup.debug.title, systemImage: "ladybug") } footer: {
            Text("Mock rides are marked as debug recordings and never upload. Sensor mode stays fixed while a ride is running.")
        }
    }

    private var aboutSection: some View {
        Section {
            Button(action: model.tapAboutInfo) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "info.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FTPunk").font(.headline)
                        Text(AppInfo.versionLabel).font(.subheadline)
                        Text(AppInfo.credits).font(.footnote).foregroundStyle(Theme.secondary)
                        if model.debugUnlocked {
                            Label("Debug tools enabled", systemImage: "ladybug").font(.footnote)
                        } else if model.aboutTapCount >= 3 {
                            Text("\(10 - model.aboutTapCount) more taps to enable debug tools").font(.footnote).foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary).padding(12).contentShape(Rectangle())
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("About FTPunk. \(AppInfo.versionLabel). \(AppInfo.credits).")
                .accessibilityValue(model.debugUnlocked ? "Debug tools enabled" : "\(10 - model.aboutTapCount) activations remaining")
                .accessibilityHint(model.debugUnlocked ? "Debug tools are enabled above." : "Activate ten times to unlock debug tools.")
                .accessibilityIdentifier("about-button")
            Button { info = .protocols } label: { Label("Ramp protocols and rider guidelines", systemImage: "info.circle") }
            Button { info = .estimate } label: { Label("Understanding the 72–77 % estimate", systemImage: "percent") }
            Button { info = .bestMinute } label: { Label("Live max power over 60 seconds", systemImage: "timer") }
            learnMore(.privacy)
        } header: { Text(SettingsGroup.about.title) } footer: {
            Text("Local by default: nothing leaves this device unless you approve an upload.")
        }.id("app-about")
    }
}

struct LearnMoreSheet: View {
    let topic: SettingsTopic
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List { ForEach(topic.paragraphs, id: \.self) { Text($0) } }
                .navigationTitle(topic.title).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.frame(minWidth: 320, idealWidth: 480, minHeight: 360)
    }
}
