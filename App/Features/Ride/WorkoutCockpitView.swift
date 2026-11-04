import SwiftUI
import FTPunkDomain

/// The cockpit for library workouts, free ERG and resistance rides. It reuses the FTP test layout:
/// large target and actual numbers, supporting readings, and Pause/Resume as the primary action
/// with Stop & save always one tap away.
struct WorkoutCockpitView: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showDebug = false
    @State private var width = 0.0

    private var plan: TrainingPlan { engine.session.training! }
    private var isWorkout: Bool { plan.kind == .workout }
    private var isResistance: Bool { engine.resumeResistance != nil }
    private var paused: Bool { engine.phase == .paused }
    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var row: AnyLayout { stacked ? AnyLayout(VStackLayout(spacing: Space.m)) : AnyLayout(HStackLayout(spacing: Space.m)) }
    private var livePower: Int? { engine.lastPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts.rounded()) : nil } }
    private var liveCadence: Double? { engine.lastCadence.flatMap { model.elapsed - $0.time <= 2 ? $0.rpm : nil } }
    private var layout: CockpitLayout {
        CockpitLayout.make(phase: engine.phase, accessibilitySize: stacked, rideVisual: model.rideVisualPlacement,
                           containerWidth: width, regularWidthClass: sizeClass != .compact, kind: isWorkout ? .workout : .freeRide)
    }
    private var busy: Bool { model.trainingTransition != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.m) {
                header
                banners
                if layout.sideBySide {
                    HStack(alignment: .top, spacing: Space.l) {
                        VStack(spacing: Space.m) { ForEach(layout.leftColumn, id: \.self) { block($0) } }.frame(maxWidth: .infinity)
                        VStack(spacing: Space.m) { ForEach(layout.rightColumn, id: \.self) { block($0) } }.frame(maxWidth: 420)
                    }
                } else {
                    if isWorkout { profile }
                    if layout.visual == .hero { hero } else { heroTiles }
                    if layout.visual == .strip { RideVisualStrip(model: model, engine: engine) }
                    lowerContent
                }
            }
            .padding(Space.l).frame(maxWidth: layout.maximumContentWidth).frame(maxWidth: .infinity)
        }
        .modifier(ReadWidth(width: $width))
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
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

    @ViewBuilder private var profile: some View {
        WorkoutProfileChart(plan: plan, intensity: engine.intensity, progressSeconds: engine.trainingElapsed, height: 64)
        stepBlock
    }
    /// Below the readings in the single column. (The profile sits above the readings there.)
    @ViewBuilder private var lowerContent: some View {
        block(.tiles); block(.controls); block(.notes)
    }

    /// One part of the cockpit. The wide Large layout places these in two columns (`CockpitLayout`).
    @ViewBuilder private func block(_ block: CockpitBlock) -> some View {
        switch block {
        case .scene: hero
        case .progress: if isWorkout { profile }
        case .tiles: supportTiles
        case .controls: adjustControls
        case .notes: Text(footer).font(.callout).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hero: some View { RideVisualHero(model: model, engine: engine, readout: heroReadout) }
    private var heroReadout: HeroReadout {
        var detail: String?
        if isWorkout, let current = engine.currentStep { detail = "STEP \(current.index + 1)/\(plan.steps.count) · \(clockText(current.remaining))" }
        let actual = livePower.map(String.init)
        if let level = engine.resumeResistance {
            return HeroReadout(targetTitle: paused ? "RESUME LEVEL" : "RESISTANCE", target: String(format: "%.1f", Double(level) / 10), unit: "", actual: actual, detail: detail)
        }
        if paused { return HeroReadout(targetTitle: "PAUSED", target: engine.resumeTarget.map(String.init), actual: actual, detail: detail) }
        return HeroReadout(target: engine.targetPower.map(String.init), actual: actual, detail: detail)
    }

    // MARK: Header and banners

    @ViewBuilder private var header: some View {
        if stacked { compactHeader } else { regularHeader }
    }

    /// Accessibility text sizes: the title and the time only, so nothing wraps letter by letter and the readings stay above the fold.
    private var compactHeader: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Button { model.cockpitPresented = false } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Minimise ride").accessibilityHint("Keeps the ride going behind the live-ride bar")
            .accessibilityIdentifier("minimise-ride")
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.session.activityTitle).font(.headline).foregroundStyle(Theme.accent).lineLimit(2).minimumScaleFactor(0.7)
                Text(clockText(isWorkout ? engine.trainingElapsed : model.elapsed)).font(.headline).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(engine.session.activityTitle)
            .accessibilityValue("\(isWorkout ? "Workout time" : "Ride time") \(clockText(isWorkout ? engine.trainingElapsed : model.elapsed)). \(paused ? "Paused" : engine.phase == .waiting ? "Start pedaling" : "Riding")")
            Spacer(minLength: 0)
            RideVisualMenu(model: model)
            if engine.session.isDemo {
                RideOptionsMenu(showDebug: { showDebug = true }).equatable()
            }
        }
    }

    private var regularHeader: some View {
        HStack(spacing: Space.m) {
            Button { model.cockpitPresented = false } label: {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Minimise ride").accessibilityHint("Keeps the ride going behind the live-ride bar")
            .accessibilityIdentifier("minimise-ride")
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.session.activityTitle).font(.headline).foregroundStyle(Theme.accent).lineLimit(2)
                Text("\(engine.session.riderName) · \(paused ? "Paused" : engine.phase == .waiting ? "Start pedaling" : "Riding")")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(clockText(isWorkout ? engine.trainingElapsed : model.elapsed)).font(.headline).monospacedDigit()
                Text(isWorkout ? "WORKOUT TIME" : "RIDE TIME").font(.caption2).foregroundStyle(Theme.secondary)
            }
            RideVisualMenu(model: model)
            if engine.session.isDemo {
                RideOptionsMenu(showDebug: { showDebug = true }).equatable()
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if engine.session.isDemo { StatusPill(text: model.mockPaused ? "Debug · stream paused" : "Debug · mock sensors", symbol: "ladybug", tone: .warning) }
        if let transition = model.trainingTransition {
            Text(transition).font(.headline).foregroundStyle(Theme.warning)
        } else if paused {
            Label("Trainer released. Progress is paused. Pedal before resuming.", systemImage: "pause.circle")
                .font(.callout).foregroundStyle(Theme.warning).frame(maxWidth: .infinity, alignment: .leading)
        }
        if model.isFinishing { Label("Confirming trainer stop…", systemImage: "hourglass").font(.headline).foregroundStyle(Theme.warning) }
    }

    // MARK: Workout steps

    @ViewBuilder private var stepBlock: some View {
        if let current = engine.currentStep {
            let next = current.index + 1 < plan.steps.count ? plan.steps[current.index + 1] : nil
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(current.step.name).font(.title3.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: Space.s)
                    Text(clockText(current.remaining)).font(.title2.bold()).monospacedDigit()
                        .accessibilityLabel("Step time left").accessibilityValue(clockText(current.remaining))
                }
                Text("Step \(current.index + 1) of \(plan.steps.count)").font(.footnote).foregroundStyle(Theme.secondary)
                if let next {
                    Text("Next: \(next.name) · \(DurationFormat.compact(next.seconds)) · \(scaled(next.watts)) W").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    Text("Last step").font(.subheadline).foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
        } else if engine.phase == .waiting {
            Text("Start pedaling to begin.").font(.title3).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func scaled(_ watts: Int) -> Int { Int((Double(watts) * Double(engine.intensity) / 100).rounded()) }

    // MARK: Tiles

    private var heroTiles: some View {
        row {
            if let level = engine.resumeResistance {
                MetricTile(title: paused ? "RESUME LEVEL" : "RESISTANCE", value: String(format: "%.1f", Double(level) / 10),
                           tone: .accent, caption: "Trainer level · no ERG", role: .hero)
            } else if paused {
                MetricTile(title: "PAUSED", value: nil, tone: .warning, caption: engine.resumeTarget.map { "Resumes at \($0) W" } ?? "Trainer released", role: .hero)
            } else {
                MetricTile(title: "TARGET", value: engine.targetPower.map(String.init), unit: "W", tone: .accent,
                           caption: engine.targetPower == nil ? nil : "ERG target", role: .hero)
            }
            MetricTile(title: "ACTUAL", value: livePower.map(String.init), unit: "W", caption: "\(engine.session.configuration.resolvedPowerSource.title) power", role: .hero)
        }
    }

    private var supportTiles: some View {
        row {
            MetricTile(title: "HEART RATE", value: model.freshHeartRate.map(String.init), unit: "bpm", symbol: "heart.fill", tone: .heart)
            MetricTile(title: "CADENCE", value: liveCadence.map { String(Int($0)) }, unit: "rpm", symbol: "figure.indoor.cycle")
        }
    }

    // MARK: Adjustments and actions

    @ViewBuilder private var adjustControls: some View {
        if isWorkout {
            adjuster(title: "Intensity", value: "\(engine.intensity) %", minus: ("−5 %", { model.adjustIntensity(by: -5) }, engine.intensity <= 50, "intensity-minus"),
                     plus: ("+5 %", { model.adjustIntensity(by: 5) }, engine.intensity >= 150, "intensity-plus"))
        } else if isResistance {
            adjuster(title: "Resistance", value: String(format: "%.1f", Double(engine.resumeResistance ?? 0) / 10),
                     minus: ("− level", { model.adjustResistance(by: -1) }, false, "resistance-minus"),
                     plus: ("+ level", { model.adjustResistance(by: 1) }, false, "resistance-plus"))
        } else {
            adjuster(title: "ERG target", value: "\(engine.targetPower ?? engine.resumeTarget ?? 0) W",
                     minus: ("−10 W", { model.adjustERG(by: -10) }, false, "erg-minus"), plus: ("+10 W", { model.adjustERG(by: 10) }, false, "erg-plus"))
        }
    }
    private func adjuster(title: String, value: String, minus: (String, () -> Void, Bool, String), plus: (String, () -> Void, Bool, String)) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.m))
        return layout {
            Button(minus.0, action: minus.1).disabled(minus.2 || busy).accessibilityIdentifier(minus.3)
            VStack(spacing: 2) {
                Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                Text(value).font(.title2.bold()).monospacedDigit()
            }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
            Button(plus.0, action: plus.1).disabled(plus.2 || busy).accessibilityIdentifier(plus.3)
        }
        .buttonStyle(FTPunkSecondaryButtonStyle()).controlSize(.large)
    }

    private var footer: String {
        if isResistance { return "Use your gears and cadence to choose the effort. Levels are trainer-specific, not watts." }
        if paused { return "Pedal until fresh power and cadence arrive, then resume." }
        // The same rule as the avatar: when Chaindance stands up, so does the text.
        return CoachingText.line(for: RideVisualState.make(RideVisualInput(model: model, engine: engine)), phase: engine.phase)
    }

    private var actions: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.m))
        return layout {
            Button { paused ? model.resumeTraining() : model.pauseTraining() } label: {
                Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(FTPunkPrimaryButtonStyle()).controlSize(.large).frame(minHeight: 52)
            .disabled(busy).keyboardShortcut("p", modifiers: [.command, .shift]).accessibilityIdentifier("pause-resume")
            Button(role: .destructive) { model.stop() } label: {
                Label("Stop & save", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(FTPunkSecondaryButtonStyle()).controlSize(.large).frame(minHeight: 52)
            .keyboardShortcut(".", modifiers: .command)
            .accessibilityIdentifier("stop-save")
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m).frame(maxWidth: .infinity).background(.bar)
    }
}
