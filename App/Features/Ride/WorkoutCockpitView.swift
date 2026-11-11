import SwiftUI
import FTPunkDomain

/// The dashboard for library workouts, free ERG and resistance rides, styled after the Chaindance (RG/SP) mockups.
/// In a workout the time left in the step is the biggest number; target (with its −/+ controls inside the box) and
/// actual stand beside it. Then the workout profile with the heart-rate line and Skip, a boxed row of heart rate,
/// cadence and intensity, and every other ride figure below. Pause/Resume and Stop & save stay one tap away.
struct WorkoutCockpitView: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showDebug = false

    private var plan: TrainingPlan { engine.session.training! }
    private var isWorkout: Bool { plan.kind == .workout }
    private var isResistance: Bool { engine.resumeResistance != nil }
    private var paused: Bool { engine.phase == .paused }
    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }
    /// Narrow screens put the big box on its own row, with target and actual side by side beneath it.
    private var narrow: Bool { sizeClass == .compact || stacked }
    private var livePower: Int? { engine.lastPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts.rounded()) : nil } }
    private var trainerPower: Int? { engine.lastTrainerPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts.rounded()) : nil } }
    private var showsTrainer: Bool { engine.session.configuration.resolvedPowerSource == .externalPowerMeter }
    private var liveCadence: Double? { engine.lastCadence.flatMap { model.elapsed - $0.time <= 2 ? $0.rpm : nil } }
    private var busy: Bool { model.trainingTransition != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.m) {
                header
                banners
                mainRow
                if isWorkout { profileBlock }
                readingsRow
                RideMoreReadings(session: engine.session)
                Text(footer).font(.callout).foregroundStyle(Chaindance.dim).frame(maxWidth: .infinity, alignment: .leading)
                LivePowerChart(session: engine.session)
            }
            .padding(Space.l).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .background(Chaindance.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showDebug) {
            NavigationStack {
                ScrollView { DebugControlsView(model: model).padding() }
                    .navigationTitle("Debug controls")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDebug = false } } }
            }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 520)
            #endif
        }
    }

    // MARK: Header and banners

    private var rideClock: String { clockText(isWorkout ? engine.trainingElapsed : model.elapsed) }
    private var stateText: String { paused ? "Paused" : engine.phase == .waiting ? "Start pedaling" : "Riding" }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Button { model.cockpitPresented = false } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).foregroundStyle(Chaindance.text)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Minimise ride").accessibilityHint("Keeps the ride going behind the live-ride bar")
            .accessibilityIdentifier("minimise-ride")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Text(isWorkout ? "WORKOUT" : isResistance ? "RESISTANCE" : "FREE RIDE")
                        .font(.system(.caption, design: .rounded).weight(.heavy)).tracking(1)
                        .foregroundStyle(Chaindance.background).padding(.horizontal, 6).padding(.vertical, 2).background(Chaindance.lime)
                    Text(engine.session.activityTitle).font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Chaindance.text).lineLimit(stacked ? 2 : 1).minimumScaleFactor(0.7)
                }
                Text("\(engine.session.riderName) · \(stateText)").font(.caption).foregroundStyle(Chaindance.dim)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                ChaindanceNumber(text: rideClock, size: 34)
                Text(isWorkout ? "WORKOUT TIME" : "RIDE TIME").chaindanceCaption()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isWorkout ? "Workout time" : "Ride time").accessibilityValue("\(rideClock). \(stateText)")
            if engine.session.isDemo {
                RideOptionsMenu(showDebug: { showDebug = true }).equatable()
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if engine.session.isDemo { StatusPill(text: model.mockPaused ? "Debug · stream paused" : "Debug · mock sensors", symbol: "ladybug", tone: .warning) }
        if let transition = model.trainingTransition {
            Text(transition).font(.headline).foregroundStyle(Chaindance.amber)
        } else if paused {
            Label("Trainer released. Progress is paused. Pedal before resuming.", systemImage: "pause.circle")
                .font(.headline).foregroundStyle(Chaindance.amber).frame(maxWidth: .infinity, alignment: .leading)
        }
        if model.isFinishing { Label("Confirming trainer stop…", systemImage: "hourglass").font(.headline).foregroundStyle(Chaindance.amber) }
    }

    // MARK: Big numbers

    @ViewBuilder private var mainRow: some View {
        if narrow {
            VStack(spacing: Space.m) {
                bigBox
                if isWorkout {
                    (stacked ? AnyLayout(VStackLayout(spacing: Space.m)) : AnyLayout(HStackLayout(alignment: .top, spacing: Space.m))) { targetBox; actualBox }
                } else { targetBox }
            }
        } else {
            HStack(alignment: .top, spacing: Space.m) {
                bigBox.frame(maxWidth: .infinity)
                VStack(spacing: Space.m) {
                    targetBox
                    if isWorkout { actualBox }
                }
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Workout: time left in the step. Free ride: the actual power.
    @ViewBuilder private var bigBox: some View {
        if isWorkout {
            if let current = engine.currentStep {
                let left = clockText(current.remaining.rounded(.up))
                ChaindanceBox(caption: "Step left", accent: paused ? .amber : .none, corner: "STEP \(current.index + 1)/\(plan.steps.count)", minHeight: 200) {
                    VStack(spacing: Space.xs) {
                        ChaindanceNumber(text: left, size: 128, color: paused ? Chaindance.amber : Chaindance.text)
                        Text(current.step.name).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Chaindance.text).lineLimit(1)
                    }
                    .frame(maxHeight: .infinity)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step time left").accessibilityValue("\(left), \(current.step.name), step \(current.index + 1) of \(plan.steps.count)")
            } else {
                ChaindanceBox(caption: "Step left", minHeight: 200) {
                    Text(engine.phase == .waiting ? "START PEDALING" : "—").font(.system(.largeTitle, design: .rounded).weight(.black))
                        .foregroundStyle(Chaindance.lime).frame(maxHeight: .infinity)
                }
            }
        } else {
            ChaindanceBox(caption: "Actual", corner: showsTrainer ? nil : "\(engine.session.configuration.resolvedPowerSource.title) power", minHeight: 200) {
                powerReading(livePower, size: 128)
            }
            .overlay(alignment: .bottomLeading) { trainerLabel }
            .accessibilityElement(children: .ignore).accessibilityLabel("Actual power")
            .accessibilityValue(livePower.map { "\($0) watts" } ?? "No recent signal")
        }
    }

    private func powerReading(_ value: Int?, size: CGFloat, color: Color = Chaindance.text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            ChaindanceNumber(text: value.map(String.init) ?? "—", size: size, color: color)
            if value != nil { Text("W").chaindanceCaption() }
        }
        .frame(maxHeight: .infinity)
    }

    /// The trainer's own watts, bottom-left, while a power meter is the source (the big number is then the meter's).
    @ViewBuilder private var trainerLabel: some View {
        if showsTrainer {
            HStack(spacing: 4) {
                Text("TR").chaindanceCaption()
                Text(trainerPower.map(String.init) ?? "—").font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(Chaindance.text)
            }
            .padding(Space.m).accessibilityElement(children: .combine).accessibilityLabel("Trainer power")
            .accessibilityValue(trainerPower.map { "\($0) watts" } ?? "not available")
        }
    }

    private var actualBox: some View {
        ChaindanceBox(caption: "Actual", corner: showsTrainer ? nil : engine.session.configuration.resolvedPowerSource.title) {
            powerReading(livePower, size: 72)
        }
        .overlay(alignment: .bottomLeading) { trainerLabel }
        .accessibilityElement(children: .ignore).accessibilityLabel("Actual power")
        .accessibilityValue(livePower.map { "\($0) watts" } ?? "No recent signal")
    }

    /// The target, with its −/+ controls inside the box: intensity in a workout, watts in ERG, the level in resistance.
    private var targetBox: some View {
        let caption: String, value: String?, unit: String
        if let level = engine.resumeResistance {
            caption = paused ? "Resume level" : "Resistance"; value = String(format: "%.1f", Double(level) / 10); unit = ""
        } else if paused {
            caption = "Paused · resumes at"; value = engine.resumeTarget.map(String.init); unit = "W"
        } else {
            caption = "Target"; value = (engine.targetPower ?? engine.resumeTarget).map(String.init); unit = "W"
        }
        return ChaindanceBox(caption: caption, accent: paused ? .amber : .lime, corner: isWorkout ? "\(engine.intensity) %" : nil) {
            VStack(spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    ChaindanceNumber(text: value ?? "—", size: 72, color: paused ? Chaindance.amber : Chaindance.lime)
                    if value != nil, !unit.isEmpty { Text(unit).chaindanceCaption() }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(caption).accessibilityValue(value.map { "\($0) \(unit)" } ?? "none")
                targetControls
            }
        }
    }

    @ViewBuilder private var targetControls: some View {
        if isWorkout {
            stepper(minus: ("−5 %", "Lower intensity", { model.adjustIntensity(by: -5) }, engine.intensity <= 50, "intensity-minus"),
                    plus: ("+5 %", "Raise intensity", { model.adjustIntensity(by: 5) }, engine.intensity >= 150, "intensity-plus"))
        } else if isResistance {
            stepper(minus: ("− LEVEL", "Lower resistance", { model.adjustResistance(by: -1) }, false, "resistance-minus"),
                    plus: ("+ LEVEL", "Raise resistance", { model.adjustResistance(by: 1) }, false, "resistance-plus"))
        } else {
            stepper(minus: ("−10 W", "Lower ERG target", { model.adjustERG(by: -10) }, false, "erg-minus"),
                    plus: ("+10 W", "Raise ERG target", { model.adjustERG(by: 10) }, false, "erg-plus"))
        }
    }
    private typealias StepAction = (title: String, label: String, action: () -> Void, disabled: Bool, id: String)
    private func stepper(minus: StepAction, plus: StepAction) -> some View {
        HStack(spacing: Space.s) {
            Button(minus.title, action: minus.action).disabled(minus.disabled || busy).accessibilityLabel(minus.label).accessibilityIdentifier(minus.id)
                .keyboardShortcut(.downArrow, modifiers: [])
            Button(plus.title, action: plus.action).disabled(plus.disabled || busy).accessibilityLabel(plus.label).accessibilityIdentifier(plus.id)
                .keyboardShortcut(.upArrow, modifiers: [])
        }
        .buttonStyle(ChaindanceStepButtonStyle())
    }

    // MARK: Profile, next step and Skip

    @ViewBuilder private var profileBlock: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            WorkoutProfileChart(plan: plan, intensity: engine.intensity, progressSeconds: engine.trainingElapsed, height: 96,
                                heartRate: WorkoutClock.heartRate(engine.session))
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.m))) {
                nextText
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Rectangle().fill(Chaindance.heartLine).frame(width: 16, height: 3)
                    Text("Heart rate").font(.caption).foregroundStyle(Chaindance.dim)
                }
                .accessibilityHidden(true)
                Button { model.skipStep() } label: { Label("Skip step", systemImage: "forward.end.fill") }
                    .buttonStyle(ChaindanceOutlineButtonStyle())
                    .disabled(!engine.canSkipStep || busy)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .accessibilityHint("Moves on to the next step. The last step can't be skipped; use Stop & save.")
                    .accessibilityIdentifier("skip-step")
            }
        }
    }

    @ViewBuilder private var nextText: some View {
        if let current = engine.currentStep {
            let next = current.index + 1 < plan.steps.count ? plan.steps[current.index + 1] : nil
            Group {
                if let next {
                    Text("NEXT ▸ ").foregroundStyle(Chaindance.dim) + Text("\(next.name) · \(DurationFormat.compact(next.seconds)) · \(scaled(next.watts)) W").foregroundStyle(Chaindance.text)
                } else {
                    Text("LAST STEP").foregroundStyle(Chaindance.dim)
                }
            }
            .font(.system(.headline, design: .rounded).weight(.semibold))
        } else if engine.phase == .waiting {
            Text("Start pedaling to begin.").font(.headline).foregroundStyle(Chaindance.text)
        }
    }
    private func scaled(_ watts: Int) -> Int { Int((Double(watts) * Double(engine.intensity) / 100).rounded()) }

    // MARK: Readings

    private var readingsRow: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.m)) : AnyLayout(HStackLayout(spacing: Space.m))
        let heart = model.freshHeartRate.map(String.init)
        let cadence = liveCadence.map { String(Int($0)) }
        return layout {
            reading(caption: "♥ BPM", value: heart, accent: .pink, spoken: "Heart rate")
            reading(caption: "RPM", value: cadence, accent: .none, spoken: "Cadence")
            if isWorkout {
                reading(caption: "Intensity", value: "\(engine.intensity)", unit: "%", accent: .cyan, spoken: "Intensity")
            } else {
                let kilojoules = RideTrack.make(engine.session).kilojoules
                reading(caption: "Work", value: String(Int(kilojoules.rounded())), unit: "kJ", accent: .cyan, spoken: "Work")
            }
        }
    }
    private func reading(caption: String, value: String?, unit: String = "", accent: Chaindance.Accent, spoken: String) -> some View {
        ChaindanceBox(caption: caption, accent: accent) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                ChaindanceNumber(text: value ?? "—", size: 60, color: accent.color ?? Chaindance.text)
                if value != nil, !unit.isEmpty { Text(unit).chaindanceCaption() }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(spoken)
        .accessibilityValue(value.map { "\($0) \(unit)" } ?? "No recent signal")
    }

    private var footer: String {
        if isResistance { return "Use your gears and cadence to choose the effort. Levels are trainer-specific, not watts." }
        if paused { return "Pedal until fresh power and cadence arrive, then resume." }
        return CoachingText.line(for: RideVisualState.make(RideVisualInput(model: model, engine: engine)), phase: engine.phase)
    }

    // MARK: Actions

    private var actions: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.m))
        return layout {
            Button { paused ? model.resumeTraining() : model.pauseTraining() } label: {
                Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(FTPunkPrimaryButtonStyle()).controlSize(.large).frame(minHeight: 52)
            .disabled(busy).keyboardShortcut("p", modifiers: [.command, .shift]).accessibilityIdentifier("pause-resume")
            // The space bar does the same (hardware keyboard on Mac and iPad); a second shortcut needs its own hidden button.
            .background {
                Button("") { paused ? model.resumeTraining() : model.pauseTraining() }
                    .keyboardShortcut(.space, modifiers: []).disabled(busy).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
            Button(role: .destructive) { model.stop() } label: {
                Label("Stop & save", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(FTPunkSecondaryButtonStyle()).controlSize(.large).frame(minHeight: 52)
            .keyboardShortcut(".", modifiers: .command)
            .accessibilityIdentifier("stop-save")
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m).frame(maxWidth: .infinity)
        .background(Chaindance.panel)
        .overlay(alignment: .top) { Rectangle().fill(Chaindance.line).frame(height: 3) }
    }
}

/// Every other ride figure, always on the dashboard: power (average, normalized, maximum), heart rate (average,
/// maximum), average cadence, work, calories, simulated speed and distance, and pedal balance when it is reported.
struct RideMoreReadings: View {
    let session: TestSession

    private struct Item: Identifiable {
        let caption: String, value: String?, unit: String, note: String?
        var id: String { caption }
    }
    private var items: [Item] {
        let summary = RideSummary.make(session), track = RideTrack.make(session)
        let ridden = !track.points.isEmpty
        let whole: (Double?) -> String? = { $0.map { String(Int($0.rounded())) } }
        var result = [
            Item(caption: "Avg power", value: whole(summary.averagePower), unit: "W", note: nil),
            Item(caption: "NP", value: whole(summary.normalizedPower), unit: "W", note: nil),
            Item(caption: "Max power", value: whole(summary.maximumPower), unit: "W", note: nil),
            Item(caption: "Avg HR", value: whole(summary.averageHeartRate), unit: "bpm", note: nil),
            Item(caption: "Max HR", value: summary.maximumHeartRate.map(String.init), unit: "bpm", note: nil),
            Item(caption: "Avg RPM", value: whole(summary.averageCadence), unit: "rpm", note: nil),
            Item(caption: "Work", value: ridden ? String(Int(track.kilojoules.rounded())) : nil, unit: "kJ", note: nil),
            Item(caption: "Calories", value: ridden ? String(Int(track.kilocalories.rounded())) : nil, unit: "kcal", note: "Est."),
            Item(caption: "Speed", value: ridden ? RideFigures.kilometresPerHour(track.speed(at: session.samples.last?.time ?? 0)) : nil, unit: "km/h", note: "Sim."),
            Item(caption: "Distance", value: ridden ? RideFigures.kilometres(track.distance) : nil, unit: "km", note: "Sim."),
        ]
        if let left = RideBalance.live(session.samples) {
            result.append(Item(caption: "Balance", value: RideFigures.balance(left), unit: "L/R", note: nil))
        }
        return result
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.m)], spacing: Space.m) {
            ForEach(items) { item in
                ChaindanceBox(caption: item.caption, corner: item.note) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        ChaindanceNumber(text: item.value ?? "—", size: 34)
                        if item.value != nil { Text(item.unit).chaindanceCaption() }
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(item.caption)
                .accessibilityValue(item.value.map { "\($0) \(item.unit)" + (item.note.map { ", \($0 == "Sim." ? "simulated" : "estimated")" } ?? "") } ?? "Not yet")
            }
        }
    }
}
