import SwiftUI
import FTPunkDomain
import FTPunkDevices

/// Every ride passes through this checklist. Start is always visible; when it is disabled, the
/// reason sits directly above it. Phase 2 covers the FTP test, free ERG and resistance rides.
struct PreflightView: View {
    @Bindable var model: AppModel
    let kind: RideKind
    @State private var showRiders = false
    @State private var showDevices = false
    @State private var showProtocols = false
    @State private var info: TestInfo?
    @State private var warmupValid = true
    @State private var cooldownValid = true

    private var durationsValid: Bool {
        guard kind == .ftpTest else { return true }
        if model.demoMode && model.quickDebugTest { return true }
        let manualValid = model.automaticWarmup || Int(model.manualWarmup).map { (1...32767).contains($0) } == true
        return warmupValid && cooldownValid && manualValid
    }
    private var workout: AppModel.WorkoutDetail? { if case .workout(let ref) = kind { model.workoutDetail(for: ref) } else { nil } }
    private var removed: Bool { if case .workout = kind { workout == nil } else { false } }
    private var blocker: StartBlocker? {
        model.startBlocker(for: kind.id, durationsValid: durationsValid, needsFTP: workout?.needsFTP == true,
                           plan: workout?.plan, intensity: model.preflightIntensity)
    }
    private var title: String {
        switch kind { case .ftpTest: "FTP test"; case .freeERG: "Free ERG ride"; case .resistance: "Resistance ride"; case .workout: workout?.title ?? "Workout" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if model.demoMode {
                    StatusPill(text: "Debug · mock sensors", symbol: "ladybug", tone: .warning)
                }
                commonRows
                switch kind {
                case .ftpTest: testRows
                case .freeERG: ergRows
                case .resistance: resistanceRows
                case .workout: workoutRows
                }
                if model.debugUnlocked && model.demoMode { debugGroup }
                Text(footer).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(Space.l).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryActionBar(title: startTitle, systemImage: "play.fill", reason: removed ? "This workout was removed." : blocker?.reason,
                             isEnabled: blocker == nil && !model.isBusy && !removed, action: start) {
                if model.isStarting { Button("Cancel start", role: .destructive, action: model.stop).buttonStyle(FTPunkSecondaryButtonStyle()) }
            }
        }
        .onAppear { model.applyRecommendedProtocol() }
        .onChange(of: model.weight) { _, _ in model.applyRecommendedProtocol() }
        .sheet(isPresented: $showRiders) { RiderSheet(model: model) }
        .sheet(isPresented: $showDevices) { DevicesSheet(model: model) }
        .sheet(isPresented: $showProtocols) { ProtocolChooserSheet(model: model) }
        .sheet(item: $info) { ProtocolInfoView(topic: $0) }
    }

    private var startTitle: String {
        if model.isStarting { return "Preparing…" }
        switch kind {
        case .ftpTest: return model.demoMode ? "Start debug test" : "Start FTP test"
        case .freeERG: return "Start free ERG ride"
        case .resistance: return "Start resistance ride"
        case .workout: return "Start workout"
        }
    }

    private func start() {
        Task {
            switch kind {
            case .ftpTest: await model.start()
            case .freeERG:
                do { await model.start(training: try .freeRide(watts: model.freeRideWatts)) }
                catch { model.errorMessage = error.localizedDescription }
            case .resistance:
                do {
                    guard let range = model.resistanceLimits else { throw BluetoothError.unsupported }
                    await model.start(training: try .resistanceRide(level: range.quantized(model.resistanceLevel)))
                } catch { model.errorMessage = error.localizedDescription }
            case .workout(let ref): await model.startWorkout(ref)
            }
        }
    }

    @ViewBuilder private var commonRows: some View {
        ChecklistCard {
            ChecklistRow(symbol: "person.fill", title: "Rider", value: riderSummary, action: { showRiders = true })
            Divider()
            let cadence = CadenceStatus.make(source: model.cadenceSource, devicesConnected: model.bluetooth.names[.trainer] != nil)
            ChecklistRow(symbol: "antenna.radiowaves.left.and.right", title: "Devices", value: devicesSummary,
                         status: model.deviceSummary.trainer == .attention ? .attention : .normal,
                         detail: "Cadence: \(cadence.text)", action: { showDevices = true })
        }
    }

    private var riderSummary: String {
        let name = model.riderName.isEmpty ? model.profile.name : model.riderName
        let weight = model.riderWeight.map { "\(Int($0.rounded())) kg" } ?? "no weight"
        let ftp = model.selectedFTP.map { "FTP \(Int($0.watts.rounded())) W" } ?? "no FTP"
        return "\(name) · \(weight) · \(ftp)"
    }
    private var devicesSummary: String {
        if model.demoMode { return "Mock sensors" }
        return DevicesLine.make(trainerName: model.bluetooth.names[.trainer], powerSource: model.powerSource,
                                meterName: model.bluetooth.names[.pedals], heartRateName: model.bluetooth.names[.heartRate])
    }

    @ViewBuilder private var testRows: some View {
        ChecklistCard(title: "Test setup") {
            ChecklistRow(symbol: "chart.line.uptrend.xyaxis", title: "Protocol", value: model.preset.title,
                         detail: model.presetChosen ? "Chosen by you" : "Recommended: \(model.recommendedProtocol.reason)",
                         action: { showProtocols = true })
            Divider()
            ChecklistRow(symbol: "percent", title: "Estimate", value: "72 % of your best minute",
                         detail: "Conservative and fixed. The 72–77 % range is explained in the result.", action: { info = .estimate })
            Divider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Space.m) {
                    durationControl("Warm-up", minutes: $model.warmupMinutes, valid: $warmupValid)
                    durationControl("Cool-down", minutes: $model.cooldownMinutes, valid: $cooldownValid)
                    Toggle("Use 50% of FTP for the warm-up", isOn: $model.automaticWarmup)
                    if !model.automaticWarmup {
                        LabeledContent("Warm-up watts") { TextField("100", text: $model.manualWarmup).numberEntry().labelsHidden() }
                    }
                    if model.selectedFTP == nil && model.automaticWarmup {
                        Text("No FTP selected: the warm-up uses the protocol’s default target.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    Text("Set either duration to zero to skip that phase. After automatic exhaustion the trainer releases its load; you can stop and save at any time.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }.padding(.top, Space.xs)
            } label: {
                ChecklistRow(symbol: "flame", title: "Warm-up and cool-down", value: warmupCooldownSummary,
                             detail: "Adjust")
            }
            Divider()
            pixelRideRow
        }
    }
    private var pixelRideRow: some View {
        Toggle(isOn: $model.rideVisualEnabled) {
            ChecklistRow(symbol: "building.2", title: "Show \(RideVisualBranding.name) during the ride", value: "Night-city scene that shows your effort")
        }.accessibilityIdentifier("pixel-ride-toggle")
    }
    private var warmupCooldownSummary: String {
        if model.demoMode && model.quickDebugTest { return "10 s · 10 s (debug timing)" }
        func part(_ minutes: Int) -> String { minutes == 0 ? "skip" : "\(minutes) min" }
        return "Warm-up \(part(model.warmupMinutes)) at \(model.warmupPreview) · cool-down \(part(model.cooldownMinutes))"
    }
    @ViewBuilder private func durationControl(_ title: String, minutes: Binding<Int>, valid: Binding<Bool>) -> some View {
        if model.demoMode && model.quickDebugTest {
            LabeledContent(title, value: "10 seconds · debug override")
        } else {
            DurationInputField(title: title, minutes: minutes, isValid: valid)
        }
    }

    @ViewBuilder private var ergRows: some View {
        ChecklistCard(title: "Ride setup") {
            Stepper(value: $model.freeRideWatts, in: 10...1000, step: 10) {
                ChecklistRow(symbol: "bolt.fill", title: "Starting target", value: "\(model.freeRideWatts) W",
                             detail: "Change by 10 W while riding. Stop & save releases the trainer.")
            }.disabled(model.isBusy)
        }
    }

    @ViewBuilder private var resistanceRows: some View {
        ChecklistCard(title: "Ride setup") {
            if let range = model.resistanceLimits {
                Stepper(value: Binding(get: { range.quantized(model.resistanceLevel) }, set: { model.resistanceLevel = range.quantized($0) }),
                        in: range.minimum...range.maximum, step: range.increment) {
                    ChecklistRow(symbol: "dial.medium", title: "Starting level", value: String(format: "%.1f", Double(range.quantized(model.resistanceLevel)) / 10),
                                 detail: "Trainer-specific levels, not watts. Use gears and cadence to choose the effort. Power matching is off.")
                }.disabled(model.isBusy)
            } else {
                ChecklistRow(symbol: "dial.medium", title: "Resistance", value: "Not available", status: .attention,
                             detail: "Pair a trainer that advertises resistance control and a supported level range.")
            }
        }
    }

    @ViewBuilder private var workoutRows: some View {
        if let workout {
            ChecklistCard(title: "Workout") {
                VStack(alignment: .leading, spacing: Space.s) {
                    ChecklistRow(symbol: "list.bullet.rectangle", title: workout.title,
                                 value: [workout.category?.title, workout.source, DurationFormat.workout(workout.duration)].compactMap { $0 }.joined(separator: " · "),
                                 detail: workout.plan.map(IntensityLabel.label(for:)))
                    if let preview = workout.previewPlan { WorkoutProfileChart(plan: preview, intensity: model.preflightIntensity, height: 80).padding(.bottom, Space.s) }
                }
                Divider()
                ChecklistRow(symbol: "bolt.fill", title: "FTP used", value: ftpUsedText(workout), status: workout.needsFTP ? .attention : .normal, detail: ftpDetail(workout))
                Divider()
                Stepper(value: $model.preflightIntensity, in: 50...150, step: 5) {
                    ChecklistRow(symbol: "slider.horizontal.3", title: "Intensity", value: "\(model.preflightIntensity) %",
                                 detail: "Scales every target. You can change it by 5 % during the ride.")
                }.disabled(model.isBusy).accessibilityIdentifier("intensity-stepper")
                Divider()
                pixelRideRow
            }
        } else {
            Label("This workout was removed.", systemImage: "trash").foregroundStyle(Theme.warning)
        }
    }
    private func ftpUsedText(_ workout: AppModel.WorkoutDetail) -> String {
        if workout.needsFTP { return "Needs FTP" }
        if let used = workout.plan?.ftpWatts { return "\(Int(used.rounded())) W" }
        return "Fixed watts"
    }
    private func ftpDetail(_ workout: AppModel.WorkoutDetail) -> String? {
        guard let used = workout.plan?.ftpWatts, workout.cached != nil, let current = model.libraryFTP, abs(used - current) > 0.5 else { return nil }
        return "Saved at \(Int(used.rounded())) W; your current FTP is \(Int(current.rounded())) W. This workout does not rescale."
    }

    private var debugGroup: some View {
        ChecklistCard(title: "Debug") {
            VStack(alignment: .leading, spacing: Space.s) {
                Label("Mock sensors · never uploads", systemImage: "ladybug").foregroundStyle(Theme.warning).padding(.top, Space.s)
                if kind == .ftpTest { Toggle("Quick warm-up and cool-down · 10 s each", isOn: $model.quickDebugTest) }
                SelectionRow("Playback speed", selection: $model.mockSpeed) {
                    ForEach([1.0, 4.0, 12.0, 60.0], id: \.self) { Text("\(Int($0))×").tag($0) }
                }
            }
        }
    }

    private var footer: String {
        let upload = model.connection.map { "Saved locally first. You will be asked before anything is uploaded to \($0.athleteName) on Intervals.icu." }
            ?? "Results stay on this device. Connect Intervals.icu in Settings to upload an activity."
        switch kind {
        case .ftpTest: return "Stay seated and hold a comfortable, steady cadence. The trainer sets the load. Test limits: 600 W or 30 minutes of ramp. Stop at any time. " + upload
        default: return upload
        }
    }
}

/// The three ramps and a pointer to the explanation. Choosing one overrides the recommendation.
struct ProtocolChooserSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var info: TestInfo?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Recommended: \(model.recommendedProtocol.reason)").font(.callout).foregroundStyle(Theme.secondary)
                }
                Section("Choose your ramp") {
                    ForEach([RampPreset.gentle, .standard, .zwift]) { preset in
                        Button { model.choosePreset(preset); dismiss() } label: {
                            HStack(alignment: .top, spacing: Space.m) {
                                Image(systemName: model.preset == preset ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(model.preset == preset ? Theme.accent : .secondary).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(preset.title).font(.headline).foregroundStyle(.primary)
                                    Text(preset.summary).foregroundStyle(.primary)
                                    Text(preset.audience).font(.footnote).foregroundStyle(Theme.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, Space.s).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityAddTraits(model.preset == preset ? .isSelected : [])
                    }
                    Button { info = .protocols } label: { Label("Which protocol, and why?", systemImage: "info.circle") }
                        .buttonStyle(FTPunkRowButtonStyle())
                }
                if model.presetChosen {
                    Section { Button("Use the recommendation") { model.presetChosen = false; model.applyRecommendedProtocol(); dismiss() }.buttonStyle(FTPunkRowButtonStyle()) }
                }
            }
            .formStyle(.grouped).navigationTitle("Protocol")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $info) { ProtocolInfoView(topic: $0) }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 480, minHeight: 480)
        #endif
    }
}
