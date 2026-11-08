import SwiftUI
import FTPunkDomain

/// The night-city strip (`RideVisualBranding.name`) in both cockpits, in the same place in every phase. Its rider
/// shows the smoothed intensity of the ride. It reads the ride and never touches the trainer.
struct RideVisualStrip: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    /// The Large view: the same scene with `HeroLayout.skyRows` of extra sky above it.
    var hero = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @ViewState private var clock = RideVisualClock()
    @ViewState private var onScreen = true

    /// About 12 frames a second, and none at all when the strip is off screen, the app is in the background, Reduce
    /// Motion is on, the debug stream is paused or the ride has ended.
    private var animating: Bool {
        onScreen && scenePhase == .active && !reduceMotion && !(model.demoMode && model.mockPaused) && engine.phase.isActive
    }

    var body: some View {
        let summary = RideVisualState.make(RideVisualInput(model: model, engine: engine)).accessibilitySummary
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !animating)) { timeline in
            let state = RideVisualState.make(RideVisualInput(model: model, engine: engine))
            let scene = clock.scene(state: state, date: timeline.date, animating: animating, animated: !reduceMotion,
                                    highContrast: contrast == .increased, skyRows: hero ? HeroLayout.skyRows : 0)
            RideVisualImage(scene: scene)
        }
        .modifier(TrackVisibility(visible: $onScreen))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("ride-visual")
    }
}

/// What the hero overlay shows over the scene: the numbers a rider needs without looking down.
struct HeroReadout {
    var targetTitle = "TARGET"
    var target: String?
    var unit = "W"
    var actual: String?
    /// Trainer watts, shown small beside the actual power when an external meter is the power source.
    var trainerActual: String?
    /// Step or countdown, e.g. "STEP 3/9 · 2:34".
    var detail: String?
    var showsTrainer = false
    var accessibilityText: String {
        var parts = [target.map { "\(targetTitle.lowercased().capitalized) \($0) \(unit == "W" ? "watts" : unit)" } ?? "\(targetTitle.lowercased().capitalized) not set",
                     actual.map { "Actual \($0) watts" } ?? "Actual power not available"]
        if showsTrainer { parts.append(CornerReading(title: "TRAINER", value: trainerActual).accessibilityText) }
        if let detail { parts.append(detail) }
        return parts.joined(separator: ". ")
    }
}

/// The Large view: Chaindance with extra sky above the rider, and target, power and step in that sky. The readout lives
/// in the top `HeroLayout.readoutFraction` of the view and has no material behind it, only a light scrim that fades out
/// downwards, so it can never cover the rider and the digits keep their contrast against the night sky.
struct RideVisualHero: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    let readout: HeroReadout

    var body: some View {
        RideVisualStrip(model: model, engine: engine, hero: true)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    HStack(alignment: .lastTextBaseline, spacing: Space.l) {
                        column(readout.targetTitle, readout.target, tint: Theme.accent)
                        column("ACTUAL", readout.actual, tint: .white)
                        if readout.showsTrainer {
                            CornerReadingBox(reading: CornerReading(title: "TRAINER", value: readout.trainerActual)).alignmentGuide(.lastTextBaseline) { $0[.top] + 24 }
                        }
                        Spacer(minLength: 0)
                        if let detail = readout.detail {
                            Text(detail).font(.headline.monospacedDigit()).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                    .padding(.horizontal, Space.m).padding(.top, Space.xs)
                    .frame(height: proxy.size.height * HeroLayout.readoutFraction, alignment: .top)
                    .background(LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .environment(\.colorScheme, .dark)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(readout.accessibilityText)
                .accessibilityIdentifier("ride-visual-readout")
            }
    }

    private func column(_ title: String, _ value: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value ?? "—").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(readout.unit).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

/// Reports the width of the view it is attached to, for layout decisions that depend on the window size.
struct ReadWidth: ViewModifier {
    @Binding var width: Double
    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { width = $1 }
            }
        }
    }
}

/// The menu that sets how the strip shows: off, a strip between the readings, or the hero scene.
///
/// The cockpit redraws several times a second (power, clock, countdown). On macOS a `Menu` that is redrawn while it is
/// open rebuilds its NSMenu and flickers. `RideVisualMenuView` is therefore `Equatable` on the placement alone and is
/// shown with `.equatable()`, so ride updates never touch it.
struct RideVisualMenu: View {
    @Bindable var model: AppModel
    var body: some View {
        RideVisualMenuView(placement: model.rideVisualPlacement, select: { [model] in model.rideVisualPlacement = $0 }).equatable()
    }
}

struct RideVisualMenuView: View, Equatable {
    let placement: RideVisualPlacement
    let select: (RideVisualPlacement) -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.placement == rhs.placement }

    var body: some View {
        Menu {
            // Inline: the three choices appear directly in the menu with a checkmark. A plain Picker in a Menu becomes a
            // nested submenu on macOS.
            Picker(RideVisualBranding.name, selection: Binding(get: { placement }, set: { select($0) })) {
                ForEach(RideVisualPlacement.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: placement == .off ? "sparkles.tv" : "sparkles.tv.fill")
                .font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .iconMenuStyle()
        .accessibilityLabel("\(RideVisualBranding.name) view")
        .accessibilityValue(placement.title)
        .accessibilityIdentifier("ride-visual-menu")
    }
}

/// The cockpit's "…" menu (debug controls in mock rides). Equatable with no inputs, for the same reason as
/// `RideVisualMenuView`: it must not be rebuilt while open.
struct RideOptionsMenu: View, Equatable {
    let showDebug: () -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
    var body: some View {
        Menu {
            Button("Debug controls…", action: showDebug)
        } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .iconMenuStyle().accessibilityLabel("More ride options").accessibilityIdentifier("ride-options")
    }
}

extension View {
    /// An icon-only header menu. Without this, macOS draws a menu as a pop-up button that stretches across the header.
    func iconMenuStyle() -> some View {
        menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// One frame, enlarged with nearest-neighbour sampling in a rounded frame that follows the theme.
struct RideVisualImage: View {
    let scene: RideVisualScene
    @Environment(\.colorSchemeContrast) private var contrast
    private var ratio: Double { Double(RideVisualRaster.width) / Double(RideVisualRaster.height + scene.skyRows) }
    var body: some View {
        Group {
            if let image = RideVisualRaster.image(scene) {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
                    .aspectRatio(ratio, contentMode: .fit)
            } else { Color.black.aspectRatio(ratio, contentMode: .fit) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0.22), lineWidth: contrast == .increased ? 2 : 1))
        .frame(maxWidth: .infinity)
    }
}

/// Keeps the strip from animating while it is scrolled out of view (iOS 18 and macOS 15 report this).
private struct TrackVisibility: ViewModifier {
    @Binding var visible: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content.onScrollVisibilityChange(threshold: 0.05) { visible = $0 }
        } else { content }
    }
}

/// Accumulates scroll distance, crank turns and announced signs between frames. It is plain bookkeeping of what has
/// been drawn, so a frame never depends on the ride's length.
@MainActor final class RideVisualClock {
    private var motion = RideVisualMotion()
    private var last: Date?
    private var warmedUp = false

    func scene(state: RideVisualState, date: Date, animating: Bool, animated: Bool, highContrast: Bool, skyRows: Int = 0) -> RideVisualScene {
        guard animated else { return RideVisualScene(state: state, animated: false, highContrast: highContrast, skyRows: skyRows, spriteRider: true) }
        if !warmedUp {
            // Start a few seconds into the ride's scenery, so signs already ahead of the rider are in view.
            warmedUp = true
            for _ in 0..<40 { motion.advance(by: 0.1, state: state) }
        }
        if animating, let last { motion.advance(by: date.timeIntervalSince(last), state: state) }
        last = date
        return RideVisualScene(state: state, motion: motion, animated: true, highContrast: highContrast, skyRows: skyRows, spriteRider: true)
    }
}

extension RideVisualInput {
    /// Reads the live ride: smoothed power, fresh cadence, the FTP the ride uses and where it is in its plan.
    @MainActor init(model: AppModel, engine: RampEngine) {
        let session = engine.session, configuration = session.configuration, now = model.elapsed
        let training = session.training
        let mode: RideVisualMode = training == nil ? .ftpTest : training?.kind == .workout ? .workout : engine.resumeResistance != nil ? .resistance : .freeERG
        let phaseSeconds = max(0, now - engine.phaseStartedAt)
        var ramp: Ramp?, step: Step?, target: Int?
        if training == nil {
            let rampSeconds: Double
            if engine.phase == .ramp { rampSeconds = phaseSeconds }
            else if let start = session.rampStart, let end = session.rampEnd { rampSeconds = max(0, end - start) }
            else { rampSeconds = 0 }
            ramp = Ramp(phaseSeconds: phaseSeconds, warmupSeconds: configuration.warmupSeconds, cooldownSeconds: configuration.cooldownSeconds,
                        stepSeconds: configuration.preset.stepSeconds, rampSeconds: rampSeconds, bestMinuteWatts: session.result?.bestMinutePower)
        } else if let training, let current = engine.currentStep {
            let scale = Double(engine.intensity) / 100
            func scaled(_ watts: Int) -> Double { Double(watts) * scale }
            let next = current.index + 1 < training.steps.count ? training.steps[current.index + 1] : nil
            step = Step(index: current.index, count: training.steps.count, startWatts: scaled(current.step.watts),
                        endWatts: scaled(current.step.endWatts ?? current.step.watts), seconds: current.step.seconds, remaining: current.remaining,
                        next: next.map { Step.Next(seconds: $0.seconds, startWatts: scaled($0.watts), endWatts: scaled($0.endWatts ?? $0.watts)) })
        }
        if mode == .freeERG { target = engine.targetPower ?? engine.resumeTarget }
        if mode == .resistance { target = engine.resumeResistance }
        self.init(mode: mode, phase: engine.phase, power: RideVisualSmoothing.power(session.samples, now: now),
                  cadence: engine.lastCadence.flatMap { now - $0.time <= 2 ? $0.rpm : nil },
                  cadenceAvailable: configuration.resolvedCadenceSource != .unavailable,
                  ftp: training?.ftpWatts ?? configuration.priorFTP?.watts, playbackSpeed: model.demoMode ? model.mockSpeed : 1,
                  ramp: ramp, step: step, target: target, weightKG: configuration.weightKG,
                  sprintPower: RideVisualSmoothing.sprintPower(session.samples, now: now),
                  sprintPeak: RideVisualSmoothing.sprintPeak(session.samples, now: now))
    }
}
