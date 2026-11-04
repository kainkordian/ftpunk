import SwiftUI
import FTPunkDomain

/// The FTP test cockpit. Glanceable from the saddle: big target and actual numbers, the ramp step
/// and a countdown to the next one, and nothing that moves while the rider is working. Finishing
/// needs a deliberate hold; Stop & save is always one tap.
struct FTPCockpitView: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showDebug = false
    @State private var width = 0.0

    private var config: SessionConfiguration { engine.session.configuration }
    private var phaseTime: Double { max(0, model.elapsed - engine.phaseStartedAt) }
    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var layout: CockpitLayout { CockpitLayout.make(phase: engine.phase, accessibilitySize: stacked, rideVisual: model.rideVisualPlacement,
                                                                                          containerWidth: width, regularWidthClass: sizeClass != .compact, kind: .ftpTest) }
    private var stepSeconds: Double { config.preset.stepSeconds }
    private var stepNumber: Int { Int(phaseTime / stepSeconds) + 1 }
    private var livePower: Int? { engine.lastPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts.rounded()) : nil } }
    private var liveCadence: Double? { engine.lastCadence.flatMap { model.elapsed - $0.time <= 2 ? $0.rpm : nil } }
    private var cadenceAvailable: Bool { config.resolvedCadenceSource != .unavailable }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.m) {
                header
                PhaseTimelineView(timeline: timeline, current: engine.phase, showsLabels: layout.showsTimelineLabels)
                banners
                if layout.sideBySide {
                    HStack(alignment: .top, spacing: Space.l) {
                        VStack(spacing: Space.m) { ForEach(layout.leftColumn, id: \.self) { block($0) } }.frame(maxWidth: .infinity)
                        VStack(spacing: Space.m) { ForEach(layout.rightColumn, id: \.self) { block($0) } }.frame(maxWidth: 420)
                    }
                } else {
                    if layout.visual == .hero { hero } else { heroTiles }
                    if layout.visual == .strip { RideVisualStrip(model: model, engine: engine) }
                    lowerContent
                }
            }
            .padding(Space.l).frame(maxWidth: layout.maximumContentWidth).frame(maxWidth: .infinity)
        }
        .modifier(ReadWidth(width: $width))
        // Content always ends clear of the pinned action bar, so nothing important sits behind it at the initial position.
        .contentMargins(.bottom, Space.l, for: .scrollContent)
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

    private var hero: some View { RideVisualHero(model: model, engine: engine, readout: heroReadout) }
    private var heroReadout: HeroReadout {
        let detail: String? = switch engine.phase {
        case .ramp: "STEP \(stepNumber) · \(clockText(nextStepRemaining))"
        case .warmup: "WARM-UP · \(clockText(max(0, config.warmupSeconds - phaseTime)))"
        case .cooldown: "COOL-DOWN · \(clockText(max(0, config.cooldownSeconds - phaseTime)))"
        default: nil
        }
        if engine.isFreewheelCooldown { return HeroReadout(target: "EASY", unit: "", actual: livePower.map(String.init), detail: detail) }
        return HeroReadout(targetTitle: engine.phase == .cooldown ? "COOL-DOWN" : "TARGET", target: engine.targetPower.map(String.init),
                           actual: livePower.map(String.init), detail: detail)
    }

    /// Everything below the readings in the single column: what is coming, then the tiles and notes.
    @ViewBuilder private var lowerContent: some View {
        block(.progress); block(.tiles); block(.notes)
    }

    /// One part of the cockpit. The wide Large layout places these in two columns (`CockpitLayout`).
    @ViewBuilder private func block(_ block: CockpitBlock) -> some View {
        switch block {
        case .scene: hero
        case .progress:
            if engine.phase == .ramp {
                StepCountdownRing(fraction: nextStepRemaining / stepSeconds, remainingSeconds: Int(ceil(nextStepRemaining)),
                                  nextChange: "+\(config.preset.stepWatts) W")
            } else {
                phaseBlock
            }
        case .tiles:
            supportTiles
            if !cadenceAvailable && engine.phase == .ramp {
                Label("No cadence source: hold to finish when you cannot continue.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.warning).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .controls: EmptyView()
        case .notes:
            if layout.showsCoachingLine {
                Text(coachingText).font(.callout).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var coachingText: String {
        if engine.phase == .warmup, config.usesPowerMatching, case .warming = model.powerMatcher.status {
            return "Trainer warming up — power matching is settling."
        }
        return CoachingText.line(for: RideVisualState.make(RideVisualInput(model: model, engine: engine)), phase: engine.phase)
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if layout.compactHeader { compactHeader } else { regularHeader }
    }

    private var minimiseButton: some View {
        Button { model.cockpitPresented = false } label: {
            Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Minimise ride").accessibilityHint("Keeps the test running behind the live-ride bar")
        .accessibilityIdentifier("minimise-ride")
    }
    private var optionsMenu: some View { RideOptionsMenu(showDebug: { showDebug = true }).equatable() }
    /// The visual control, and the options menu only when it has something in it (debug controls).
    @ViewBuilder private var headerControls: some View {
        RideVisualMenu(model: model)
        if engine.session.isDemo { optionsMenu }
    }

    private var regularHeader: some View {
        HStack(alignment: .center, spacing: Space.m) {
            minimiseButton
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle).font(.headline).foregroundStyle(Theme.accent).lineLimit(2)
                if layout.showsHeaderSubtitle {
                    Text("\(engine.session.riderName) · \(engine.session.activityTitle)").font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(headerClock).font(.headline).monospacedDigit()
                Text(headerClockLabel).font(.caption2).foregroundStyle(Theme.secondary)
            }
            headerControls
        }
    }

    /// Accessibility text sizes: the phase and the time, nothing else, so the readings stay above the fold.
    private var compactHeader: some View {
        HStack(alignment: .top, spacing: Space.s) {
            minimiseButton
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle).font(.headline).foregroundStyle(Theme.accent).lineLimit(2).minimumScaleFactor(0.7)
                Text(CockpitLayout.compactClock(headerClock, phase: engine.phase)).font(.headline).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headerTitle.capitalized)
            .accessibilityValue("\(headerClockLabel.capitalized) \(headerClock)")
            Spacer(minLength: 0)
            headerControls
        }
    }
    private var headerTitle: String {
        switch engine.phase {
        case .waiting: "START PEDALING"
        case .warmup: "WARM-UP"
        case .ramp: "RAMP · Step \(stepNumber)"
        case .cooldown: engine.isFreewheelCooldown ? "COOL-DOWN · free spin" : "COOL-DOWN"
        default: engine.phase.title.uppercased()
        }
    }
    private var headerClock: String {
        switch engine.phase {
        case .ramp: clockText(phaseTime)
        case .warmup: clockText(max(0, config.warmupSeconds - phaseTime))
        case .cooldown: clockText(max(0, config.cooldownSeconds - phaseTime))
        default: clockText(model.elapsed)
        }
    }
    private var headerClockLabel: String {
        switch engine.phase { case .ramp: "RAMP TIME"; case .warmup: "WARM-UP LEFT"; case .cooldown: "COOL-DOWN LEFT"; default: "TOTAL TIME" }
    }
    private var timeline: PhaseTimeline {
        PhaseTimeline.make(phase: engine.phase, warmup: config.warmupSeconds, cooldown: config.cooldownSeconds,
                           elapsedInPhase: phaseTime, rampElapsed: engine.phase == .ramp ? phaseTime : nil)
    }
    private var nextStepRemaining: Double { stepSeconds - phaseTime.truncatingRemainder(dividingBy: stepSeconds) }

    // MARK: Content

    @ViewBuilder private var banners: some View {
        if engine.session.isDemo {
            StatusPill(text: model.mockPaused ? "Debug · stream paused" : "Debug · mock sensors", symbol: "ladybug", tone: .warning)
        }
        if model.isFinishing {
            Label("Confirming trainer stop…", systemImage: "hourglass").font(.headline).foregroundStyle(Theme.warning)
        }
    }

    @ViewBuilder private var heroTiles: some View {
        if layout.metricRows {
            VStack(spacing: Space.s) {
                if engine.isFreewheelCooldown {
                    MetricRow(title: "FREE SPIN", value: "EASY", tone: .accent, caption: "No ERG target", showsCaption: false)
                } else {
                    MetricRow(title: engine.phase == .cooldown ? "COOL-DOWN TARGET" : "TARGET", value: engine.targetPower.map(String.init), unit: "W",
                              tone: .accent, caption: engine.targetPower == nil ? nil : "ERG target", showsCaption: false)
                }
                MetricRow(title: "ACTUAL", value: livePower.map(String.init), unit: "W", caption: "\(config.resolvedPowerSource.title) power", showsCaption: false)
            }
        } else {
            HStack(spacing: Space.m) {
                if engine.isFreewheelCooldown {
                    MetricTile(title: "FREE SPIN", value: "EASY", tone: .accent, caption: "No ERG target", role: .hero)
                } else {
                    MetricTile(title: engine.phase == .cooldown ? "COOL-DOWN TARGET" : "TARGET", value: engine.targetPower.map(String.init), unit: "W",
                               tone: .accent, caption: engine.targetPower == nil ? nil : "ERG target", role: .hero)
                }
                MetricTile(title: "ACTUAL", value: livePower.map(String.init), unit: "W", caption: "\(config.resolvedPowerSource.title) power", role: .hero)
            }
        }
    }

    @ViewBuilder private var supportTiles: some View {
        let guardState = CadenceGuard.state(cadence: liveCadence, phase: engine.phase, cadenceAvailable: cadenceAvailable)
        let warmingUp = engine.phase == .warmup || engine.phase == .waiting
        let best = (engine.session.result?.bestMinutePower ?? engine.liveBestMinutePower).map { String(Int($0.rounded())) }
        if layout.metricRows {
            VStack(spacing: Space.s) {
                MetricRow(title: "HEART RATE", value: model.freshHeartRate.map(String.init), unit: "bpm", symbol: "heart.fill", tone: .heart)
                MetricRow(title: "CADENCE", value: liveCadence.map { String(Int($0)) }, unit: "rpm", symbol: "figure.indoor.cycle",
                          tone: guardState == .low ? .warning : .normal, caption: guardState == .low ? CadenceGuard.message : nil)
                if warmingUp {
                    MetricRow(title: "RAMP STARTS IN", value: engine.phase == .warmup ? clockText(max(0, config.warmupSeconds - phaseTime)) : nil,
                              symbol: "timer", placeholder: "Pedal", missingDescription: "Start pedaling to begin the warm-up")
                } else {
                    MetricRow(title: "MAX 60 S", value: best, unit: "W", symbol: "timer", missingDescription: "No complete 60-second window yet")
                }
            }
        } else {
            HStack(spacing: Space.m) {
                MetricTile(title: "HEART RATE", value: model.freshHeartRate.map(String.init), unit: "bpm", symbol: "heart.fill", tone: .heart)
                MetricTile(title: "CADENCE", value: liveCadence.map { String(Int($0)) }, unit: "rpm", symbol: "figure.indoor.cycle",
                           tone: guardState == .low ? .warning : .normal, caption: guardState == .low ? CadenceGuard.message : nil)
                if warmingUp {
                    MetricTile(title: "RAMP STARTS IN", value: engine.phase == .warmup ? clockText(max(0, config.warmupSeconds - phaseTime)) : nil,
                               symbol: "timer", placeholder: "Pedal", missingDescription: "Start pedaling to begin the warm-up")
                } else {
                    MetricTile(title: "MAX 60 S", value: best, unit: "W", symbol: "timer", caption: "Best full minute so far",
                               missingDescription: "No complete 60-second window yet")
                }
            }
        }
    }

    @ViewBuilder private var phaseBlock: some View {
        switch engine.phase {
        case .cooldown:
            if let result = engine.session.result {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("PROVISIONAL RESULT").ftpLabel().foregroundStyle(Theme.accent)
                    Text("\(Int(result.estimatedFTP.rounded())) W estimated FTP").font(.title2.bold())
                    Text("\(Int(result.factor * 100)) % of your best minute, \(Int(result.bestMinutePower.rounded())) W. The final result appears when you save.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading).ftpCard(tint: Theme.accent, fill: 0.06)
                .accessibilityElement(children: .combine)
            } else {
                Label("No FTP estimate from this ramp. You can still save the ride.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        default: EmptyView() // Warm-up time left is in the header and the "Ramp starts in" tile; no third copy.
        }
    }

    // MARK: Actions

    private var stopButton: some View {
        Button(role: .destructive) { model.stop() } label: {
            Label("Stop & save", systemImage: "stop.circle").frame(maxWidth: .infinity)
        }
        .controlSize(.large).frame(minHeight: 52)
        .keyboardShortcut(".", modifiers: .command)
        .accessibilityIdentifier("stop-save")
    }

    @ViewBuilder private var actions: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.m))
        layout {
            if engine.phase == .ramp {
                HoldToConfirmButton(title: "Hold to finish", systemImage: "flag.checkered", accessibilityActionName: "Finish ramp now",
                                    shortcut: KeyboardShortcut("f", modifiers: [.command, .shift]), identifier: "hold-to-finish") { model.finishRamp() }
                    .accessibilityHint("Ends the scored ramp and begins the cool-down. Press and hold for one and a half seconds. Stop & save is a separate single-tap button.")
            }
            // Stop stays a single tap and looks the same in every phase: an outline, never the primary style.
            stopButton.buttonStyle(FTPunkSecondaryButtonStyle())
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m).frame(maxWidth: .infinity).background(.bar)
    }
}
