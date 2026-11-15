import SwiftUI
import FTPunkDomain
import FTPunkDevices
#if os(macOS)
import AppKit
#endif

/// Settings are grouped and short: one line of footer text per group, with "Learn more" sheets for detail.
enum SettingsGroup: String, CaseIterable, Identifiable, Hashable {
    case riders, devices, rideDisplay, intervals, backup, debug, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .riders: "Riders"
        case .devices: "Devices"
        case .rideDisplay: "Ride screen"
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
    @AppStorage("ridePowerWindow") private var ridePowerWindow = 3
    @AppStorage("dashboardCompactNumbers") private var dashboardCompactNumbers = false
    @AppStorage("rideStepSound") private var rideStepSound = true
    @AppStorage("appFont") private var appFont = "tektur"
    @AppStorage("extraLargeRideNumbers") private var extraLargeRideNumbers = false
    @State private var captureURL: URL?
    @State private var topic: SettingsTopic?
    @State private var info: TestInfo?
    @State private var showRiders = false
    @State private var showDevices = false
    @State private var deviceRole: DeviceRole?
    @State private var apiKeyExpanded = false
    @State private var selectedGroup: SettingsGroup = .rideDisplay
    @State private var confirmDisconnect = false
    @State private var settingsPath: [SettingsGroup] = []

    var body: some View {
        Group {
            #if os(macOS)
            if !model.previewPhoneLayout { macSettings } else { phoneSettings }
            #else
            phoneSettings
            #endif
        }
        .sheet(item: $topic) { LearnMoreSheet(topic: $0) }
        .sheet(item: $info) { ProtocolInfoView(topic: $0) }
        .sheet(isPresented: $showRiders) { RiderSheet(model: model) }
        .sheet(isPresented: $showDevices) { DevicesSheet(model: model) }
        .confirmationDialog("Disconnect Intervals.icu for this rider?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectIntervals() } }
        } message: { Text("Local rides are kept. Connect again to sync this rider’s account.") }
    }
    private var phoneSettings: some View {
        NavigationStack(path: $settingsPath) {
            Form {
                ForEach(SettingsGroup.visible(debugUnlocked: model.debugUnlocked)) { group in
                    NavigationLink(group == .about ? "About and help" : group.title, value: group).accessibilityIdentifier("settings-\(group.rawValue)")
                }
            }.navigationTitle("Settings")
                .navigationDestination(for: SettingsGroup.self) { group in
                    Form { content(for: group) }.formStyle(.grouped).navigationTitle(group == .about ? "About and help" : group.title)
                        .buttonStyle(FTPunkSecondaryButtonStyle()).scrollDismissesKeyboard(.interactively)
                }
                .task(id: model.previewSettingsAnchor) {
                    if let anchor = model.previewSettingsAnchor, let group = SettingsGroup(rawValue: anchor) { settingsPath = [group]; apiKeyExpanded = true }
                    if ProcessInfo.processInfo.arguments.contains("--preview-about") { settingsPath = [.about] }
                }
        }
    }

    #if os(macOS)
    private var macSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(.ftp(34))
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    ForEach(SettingsGroup.visible(debugUnlocked: model.debugUnlocked)) { group in
                        Button { selectedGroup = group } label: {
                            HStack {
                                Text(group == .devices ? "Devices and trainer control" : group == .about ? "About and help" : group.title)
                                Spacer(minLength: 0)
                                if group == .intervals && model.connection != nil { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
                            }.ftpText(.headline, weight: .semibold).padding(.horizontal, 14).frame(minHeight: 44, alignment: .leading)
                                .foregroundStyle(selectedGroup == group ? Theme.text : Theme.secondary)
                                .background(selectedGroup == group ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }.frame(width: 216)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedGroup == .rideDisplay { macRideSettings }
                        else if selectedGroup == .devices {
                            SettingRow(title: "Devices and trainer control", detail: model.deviceSummary.description) {
                                Button("Connect and manage devices") { showDevices = true }.buttonStyle(FTPunkPrimaryButtonStyle())
                            }
                            VStack(alignment: .leading, spacing: 16) { devicesSection }.padding(22).ftpCard(fill: 0)
                        } else {
                            VStack(alignment: .leading, spacing: 16) { groupContent(selectedGroup) }.padding(22).frame(maxWidth: .infinity, alignment: .leading).ftpCard(fill: 0)
                        }
                    }.buttonStyle(FTPunkSecondaryButtonStyle()).padding(.bottom, 24)
                }
            }
        }.padding(.horizontal, 32).padding(.vertical, 28).frame(maxWidth: 1440, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity).background(Theme.ground)
            .task(id: model.previewSettingsAnchor) { if let anchor = model.previewSettingsAnchor, let group = SettingsGroup(rawValue: anchor) { selectedGroup = group; apiKeyExpanded = true } }
    }
    private var macRideSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DASHBOARD").ftpText(.caption, weight: .bold).foregroundStyle(Theme.secondary).padding(.leading, 22)
            settingsCard {
                SettingRow(title: "Power average", detail: "The big number on the ride screen. Recordings always keep every sample.", grouped: true) {
                    RideChoiceRow(title: "", selection: $ridePowerWindow, choices: LivePower.windows.map { ("\($0) s", $0) })
                }
                Divider().overlay(Theme.raised)
                SettingRow(title: "Number size", detail: "Fit to screen fills the window, sized to read from about 2 m in full screen.", grouped: true) {
                    RideChoiceRow(title: "", selection: $dashboardCompactNumbers, choices: [("Fit to screen", false), ("Compact", true)])
                }
                Divider().overlay(Theme.raised)
                SettingRow(title: "Sound before each step", detail: "Three short beeps in the last 3 s of a workout step.", grouped: true) {
                    Toggle("Sound before each step", isOn: $rideStepSound).labelsHidden().toggleStyle(RideSwitchStyle())
                }
                Divider().overlay(Theme.raised)
                SettingRow(title: "Pause when I stop pedalling", detail: "Workouts and free rides. Never during the FTP test.", grouped: true) {
                    Toggle("Pause when I stop pedalling", isOn: $model.autoPauseEnabled).labelsHidden().toggleStyle(RideSwitchStyle()).accessibilityIdentifier("auto-pause-toggle")
                }
            }
            Text("CHAINDANCE").ftpText(.caption, weight: .bold).foregroundStyle(Theme.secondary).padding(.leading, 22).padding(.top, 10)
            settingsCard {
                SettingRow(title: "Show the night-city ride", detail: "Off by default. When on, it takes the place of the timeline strip.", grouped: true) {
                    Toggle("Show Chaindance", isOn: $model.rideVisualEnabled).labelsHidden().toggleStyle(RideSwitchStyle()).accessibilityIdentifier("pixel-ride-toggle")
                }
                if model.rideVisualEnabled {
                    Divider().overlay(Theme.raised)
                    SettingRow(title: "Chaindance layout", detail: "Strip replaces the timeline. Large shows the city with readings on top.", grouped: true) {
                        RideChoiceRow(title: "", selection: $model.rideVisualPlacement, choices: [("Strip", RideVisualPlacement.strip), ("Large", RideVisualPlacement.hero)])
                    }
                }
            }
            Text("APPEARANCE").ftpText(.caption, weight: .bold).foregroundStyle(Theme.secondary).padding(.leading, 22).padding(.top, 10)
            settingsCard {
                SettingRow(title: "Font", detail: "Used for the whole app, ride screen included.", grouped: true) {
                    RideChoiceRow(title: "", selection: $appFont, choices: [("Tektur", "tektur"), ("SF Rounded", "sfRounded"), ("System", "system")])
                }
                Divider().overlay(Theme.raised)
                SettingRow(title: "Theme", detail: "The ride screen is always dark.", grouped: true) {
                    RideChoiceRow(title: "", selection: $appearance, choices: AppearanceMode.allCases.map { ($0.title, $0.rawValue) })
                }
            }
        }
    }
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
    #endif

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

    @ViewBuilder private func learnMore(_ topic: SettingsTopic) -> some View { EmptyView() }

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
                                    detail: role == .trainer ? (model.bluetooth.trainerReady ? "ERG ready" : model.bluetooth.status) : nil,
                                    problem: model.bluetooth.problems[role]) { showDevices = true }
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
            RideChoiceRow(title: "Font", selection: $appFont, choices: [("Tektur", "tektur"), ("SF Rounded", "sfRounded"), ("System", "system")], detail: "Tektur, SF Rounded or the system typeface.")
            RideChoiceRow(title: "Theme", selection: $appearance, choices: AppearanceMode.allCases.map { ($0.title, $0.rawValue) }, detail: "The ride screen is always dark.")
            RideChoiceRow(title: "Power average", selection: $ridePowerWindow, choices: LivePower.windows.map { ("\($0) s", $0) }, detail: "The big number on the ride screen. Recordings always keep every sample.")
            #if os(macOS)
            RideChoiceRow(title: "Number size", selection: $dashboardCompactNumbers, choices: [("Fit to screen", false), ("Compact", true)], detail: "Fit to screen fills the window, sized to read from about 2 m in full screen.")
            #else
            Toggle("Extra-large ride numbers", isOn: $extraLargeRideNumbers).toggleStyle(RideSwitchStyle())
            #endif
            Toggle(isOn: $rideStepSound) {
                rideSettingLabel("Sound before each step", detail: "Three short beeps in the last 3 s of a workout step.")
            }.toggleStyle(RideSwitchStyle())
            Toggle(isOn: $model.autoPauseEnabled) {
                rideSettingLabel("Pause workouts when I stop pedalling", detail: "Workouts and free rides. Never during the FTP test.")
            }.toggleStyle(RideSwitchStyle()).accessibilityIdentifier("auto-pause-toggle")
            Toggle(isOn: $model.rideVisualEnabled) {
                rideSettingLabel("Show \(RideVisualBranding.name) during rides", detail: "Off by default. When on, it takes the place of the timeline strip.")
            }.toggleStyle(RideSwitchStyle()).accessibilityIdentifier("pixel-ride-toggle")
            if model.rideVisualEnabled {
                RideChoiceRow(title: "\(RideVisualBranding.name) layout", selection: $model.rideVisualPlacement,
                              choices: [("Strip", RideVisualPlacement.strip), ("Large", RideVisualPlacement.hero)],
                              detail: "Strip replaces the timeline. Large shows the city with readings on top.")
            }
        } header: { Text(SettingsGroup.rideDisplay.title) } footer: {
            Text("Numbers follow your system text size; extra-large is easier to read from the bike. \(RideVisualBranding.name) is off by default: a neon night-city ride that follows your power. It never controls the trainer. You can also change it during a ride. Increase Contrast, Bold Text and Reduce Motion are supported.")
        }
    }

    private func rideSettingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail).ftpText(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var intervalsSection: some View {
        Section {
            if let connection = model.connection {
                LabeledContent("Connected as \(connection.athleteName)", value: "for \(model.profile.name)")
                Text(connection.usesOAuth ? "Connected with secure sign-in" : "Connected with a personal API key").ftpText(.footnote).foregroundStyle(Theme.secondary)
                Toggle("Ask to upload after each ride", isOn: $model.askToUploadAfterRide)
                Text("Every upload still needs your confirmation. With this off you can upload from the result screen or an activity.")
                    .ftpText(.footnote).foregroundStyle(Theme.secondary)
                athleteSyncRows
                Button("Retry approved pending uploads") { Task { await model.flushUploads(manual: true) } }
                Button("Disconnect", role: .destructive) { confirmDisconnect = true }.buttonStyle(FTPunkDestructiveButtonStyle())
            } else {
                DisclosureGroup("Connect with an API key", isExpanded: $apiKeyExpanded) {
                    Text("In Intervals.icu, open Settings → Developer settings and copy your personal API key. FTPunk stores it securely in Keychain.")
                        .ftpText(.footnote).foregroundStyle(Theme.secondary)
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
                Text("Disconnect and connect again to allow reading FTP and weight. Nothing else is needed.").ftpText(.footnote).foregroundStyle(Theme.secondary)
            } else {
                LabeledContent("Last synced", value: model.athleteSync.lastSynced.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet")
            }
            if let note = model.athleteSyncNote { Text(note).ftpText(.footnote).foregroundStyle(Theme.accent) }
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
                    .ftpText(.footnote).foregroundStyle(Theme.secondary)
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
                    Image(systemName: "info.circle.fill").ftpText(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FTPunk").ftpText(.headline)
                        Text(AppInfo.versionLabel).ftpText(.subheadline)
                        Text(AppInfo.credits).ftpText(.footnote).foregroundStyle(Theme.secondary)
                        if model.debugUnlocked {
                            Label("Debug tools enabled", systemImage: "ladybug").ftpText(.footnote)
                        } else if model.aboutTapCount >= 3 {
                            Text("\(10 - model.aboutTapCount) more taps to enable debug tools").ftpText(.footnote).foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary).padding(12).contentShape(Rectangle())
                    .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
                .accessibilityLabel("About FTPunk. \(AppInfo.versionLabel). \(AppInfo.credits).")
                .accessibilityValue(model.debugUnlocked ? "Debug tools enabled" : "\(10 - model.aboutTapCount) activations remaining")
                .accessibilityHint(model.debugUnlocked ? "Debug tools are enabled above." : "Activate ten times to unlock debug tools.")
                .accessibilityIdentifier("about-button")
            Button { info = .protocols } label: { Label("Ramp protocols and rider guidelines", systemImage: "info.circle") }
            Button { info = .estimate } label: { Label("Understanding the 72–77 % estimate", systemImage: "percent") }
            Button { info = .bestMinute } label: { Label("Live max power over 60 seconds", systemImage: "timer") }
            ForEach([SettingsTopic.riders, .powerMatching, .intervals, .privacy]) { item in
                Button(item.title) { topic = item }.buttonStyle(FTPunkSecondaryButtonStyle())
            }
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
