import SwiftUI
import FTPunkDomain
import AudioToolbox
#if os(macOS)
import AppKit
#endif

/// One geometry-driven cockpit. The engine remains the only source of ride phase and targets.
struct RideDashboard: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ridePowerWindow") private var powerWindow = 3
    @AppStorage("dashboardCompactNumbers") private var compactNumbers = false
    @AppStorage("dashboardShowsMoreReadings") private var more = false
    @AppStorage("rideStepSound") private var sound = true
    @AppStorage("appFont") private var appFont = "tektur"
    @State private var showDebug = false
    @State private var previousRemaining: Double?
    @State private var previousStep: Int?
    @State private var previousCadence: RampCadenceState = .normal
    @State private var lastTickSound: Int?
    @State private var targetPulse = false

    private var workout: Bool { engine.session.training?.kind == .workout }
    private var training: Bool { engine.session.training != nil }
    private var free: Bool { training && !workout }
    private var resistance: Bool { engine.resumeResistance != nil }
    private var focus: Bool { DashboardSlots.make(kind: workout ? .workout : free ? .freeRide : .ftpTest, phase: engine.phase).focus }
    private var paused: Bool { engine.phase == .paused }
    private var busy: Bool { model.trainingTransition != nil || model.isFinishing }
    private var phaseTime: Double { max(0, model.elapsed - engine.phaseStartedAt) }
    private var configuration: SessionConfiguration { engine.session.configuration }
    private var power: Double? { LivePower.average(samples: engine.session.samples, at: model.elapsed, window: powerWindow, pauses: RidePause.list(engine.session)) }
    private var cadence: Double? { engine.lastCadence.flatMap { model.elapsed - $0.time <= 2 ? $0.rpm : nil } }
    private var cadenceState: RampCadenceState { .make(cadence: cadence, at: model.elapsed, lowCadenceSince: engine.lowCadenceSince) }
    private var summary: RideSummary { RideSummary.make(engine.session) }
    private var nextRemaining: Double { configuration.preset.stepSeconds - phaseTime.truncatingRemainder(dividingBy: configuration.preset.stepSeconds) }
    private func whole(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "—" }

    var body: some View {
        GeometryReader { geometry in
            let phone = geometry.size.width < 700 || typeSize.isAccessibilitySize || model.previewPhoneLayout
            let metrics = DashboardMetrics.make(width: phone ? 1000 : geometry.size.width, height: phone ? 920 : geometry.size.height,
                                                accessibilitySize: typeSize.isAccessibilitySize, compact: model.previewDashboardCompact ?? compactNumbers)
            Group {
                if phone {
                    ScrollView {
                        VStack(spacing: metrics.gap) {
                            header(metrics, phone: true).frame(minHeight: 60)
                            powerTile(metrics).frame(height: typeSize.isAccessibilitySize ? 450 : 300)
                            if focus { cadenceTile(metrics, hero: true).frame(height: typeSize.isAccessibilitySize ? 450 : 300) }
                            else { timeTile(metrics).frame(height: typeSize.isAccessibilitySize ? 450 : 300) }
                            HStack(spacing: metrics.gap) {
                                heartTile(metrics)
                                if focus { rampNextTile(metrics) } else { cadenceTile(metrics) }
                            }.frame(height: typeSize.isAccessibilitySize ? 270 : 180)
                            if !focus { thirdTile(metrics).frame(height: 200) }
                            strip(metrics).frame(height: 160)
                        }.padding(12)
                    }
                } else { desktop(metrics) }
            }
        }
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        .background(RideWindowChrome().frame(width: 0, height: 0))
        #endif
        .background(RideStyle.ground.ignoresSafeArea()).environment(\.colorScheme, .dark)
        .foregroundStyle(RideStyle.text)
        .sheet(isPresented: $showDebug) {
            NavigationStack {
                ScrollView { DebugControlsView(model: model).padding() }.navigationTitle("Debug controls")
                    .toolbar { Button("Done") { showDebug = false } }
            }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 520)
            #endif
        }
        .onChange(of: model.elapsed) { _, _ in cues() }
        .onChange(of: engine.targetPower) { _, _ in
            guard !reduceMotion else { return }
            targetPulse = true
        }
        .task(id: engine.targetPower) {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            withAnimation(.easeOut(duration: 0.25)) { targetPulse = false }
        }
        .background { shortcuts }
    }

    private func desktop(_ m: DashboardMetrics) -> some View {
        let s = m.scale
        return VStack(spacing: m.gap) {
            header(m, phone: false).frame(height: m.headerHeight)
            if model.rideVisualPlacement == .hero {
                RideVisualHero(model: model, engine: engine, readout: HeroReadout(target: (engine.targetPower ?? engine.resumeTarget).map(String.init), actual: whole(power), detail: engine.currentStep?.step.name))
                    .frame(maxHeight: .infinity)
                HStack(spacing: m.gap) { heartTile(m); cadenceTile(m); thirdTile(m) }.frame(height: m.readingHeight)
                strip(m).frame(height: m.stripHeight)
            } else if focus {
                HStack(spacing: m.gap) { powerTile(m); cadenceTile(m, hero: true) }.frame(height: 440 * s)
                HStack(spacing: m.gap) {
                    heartTile(m).frame(maxWidth: .infinity)
                    rampNextTile(m).frame(maxWidth: .infinity).layoutPriority(1)
                        .frame(width: (1470 - 48 - 16) * s * 2 / 3)
                }.frame(height: 250 * s)
                rampFooter(m).frame(maxHeight: .infinity)
            } else {
                HStack(spacing: m.gap) { powerTile(m); timeTile(m) }.frame(height: m.heroHeight)
                HStack(spacing: m.gap) { heartTile(m); cadenceTile(m); thirdTile(m) }.frame(height: m.readingHeight)
                strip(m).frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, m.padding).padding(.top, 20 * s).padding(.bottom, 24 * s)
    }

    private func header(_ m: DashboardMetrics, phone: Bool) -> some View {
        DashHeader(model: model, engine: engine, scale: m.scale, phone: phone, showDebug: { showDebug = true })
    }

    private func powerTile(_ m: DashboardMetrics) -> some View {
        let s = m.scale
        return DashTile(scale: s) {
            VStack(spacing: 0) {
                HStack {
                    Menu {
                        ForEach(LivePower.windows, id: \.self) { seconds in Button("\(seconds) s") { powerWindow = seconds } }
                    } label: {
                        HStack(spacing: 12 * s) {
                            DashCaption(text: power == nil ? "No signal" : "Power · \(powerWindow) s", size: m.caption, color: power == nil ? RideStyle.warning : RideStyle.dim, symbol: power == nil ? "exclamationmark.triangle" : "bolt.fill")
                            Image(systemName: "chevron.down").font(.ftp(16 * s, weight: .bold)).foregroundStyle(power == nil ? RideStyle.warning : RideStyle.dim)
                        }
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().padding(10 * s).background(RideStyle.raised, in: Capsule())
                    .accessibilityLabel("Power average, \(powerWindow) seconds. Change")
                    Spacer(minLength: 0)
                    if training { targetStepper(m) }
                }.frame(height: 68 * s)
                Spacer(minLength: 0)
                DashNumber(text: whole(power), size: focus ? 300 * s : m.hero, unit: "W", unitSize: (focus ? 64 : 56) * s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Actual power").accessibilityValue(power.map { "\(Int($0.rounded())) watts" } ?? "No recent signal")
                HStack(alignment: .firstTextBaseline, spacing: 16 * s) {
                    DashCaption(text: resistance ? "Level" : "Target", size: m.caption)
                    DashNumber(text: resistance ? String(format: "%.1f", Double(engine.resumeResistance ?? 0) / 10) : (engine.targetPower ?? engine.resumeTarget).map(String.init) ?? (engine.isFreewheelCooldown ? "Easy" : "—"),
                               size: focus ? 84 * s : m.target, color: targetColor.opacity(targetPulse && !reduceMotion ? 0.65 : 1), unit: resistance || engine.isFreewheelCooldown ? "" : "W", unitSize: (focus ? 36 : 34) * s)
                    if configuration.resolvedPowerSource == .externalPowerMeter {
                        Text("Trainer \(engine.lastTrainerPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts).description : nil } ?? "—") W")
                            .font(.ftp(20 * s, weight: .bold)).foregroundStyle(RideStyle.dim)
                    }
                }
            }
        }
    }

    private var targetColor: Color {
        guard workout, let plan = engine.session.training, let ftp = plan.ftpWatts, ftp > 0, let target = engine.resumeTarget else { return RideStyle.lime }
        return zoneText(.zone(forFraction: Double(target) / ftp))
    }
    private func zoneText(_ zone: IntensityZone) -> Color {
        let value = ZonePalette.dashboardText(for: zone)
        return Color(red: value.red, green: value.green, blue: value.blue)
    }

    private func targetStepper(_ m: DashboardMetrics) -> some View {
        DashStepper(value: workout ? "\(engine.intensity) %" : resistance ? "Level \(String(format: "%.1f", Double(engine.resumeResistance ?? 0)/10))" : nil,
                    minus: free && !resistance ? "−5" : "−", plus: free && !resistance ? "+5" : "+",
                    minusID: workout ? "intensity-minus" : resistance ? "resistance-minus" : "erg-minus",
                    plusID: workout ? "intensity-plus" : resistance ? "resistance-plus" : "erg-plus",
                    lowerDisabled: busy || (workout && engine.intensity <= 50), upperDisabled: busy || (workout && engine.intensity >= 150), scale: m.scale,
                    lower: { adjust(-1) }, raise: { adjust(1) })
    }
    private func adjust(_ direction: Int, large: Bool = false) {
        if workout { model.adjustIntensity(by: direction * (large ? 5 : 1)) }
        else if resistance { model.adjustResistance(by: direction * (large ? 5 : 1)) }
        else { model.adjustERG(by: direction * (large ? 25 : 5)) }
    }

    private func timeTile(_ m: DashboardMetrics) -> some View {
        let s = m.scale
        let left = workout ? engine.currentStep?.remaining ?? 0 : engine.phase == .warmup ? configuration.warmupSeconds - phaseTime : configuration.cooldownSeconds - phaseTime
        let caption = free ? "Ride time" : workout ? "Step left" : engine.phase == .cooldown ? "Cool-down left" : "Ramp starts in"
        return DashTile(scale: s, fill: paused ? RideStyle.warning : RideStyle.tile) {
            VStack(alignment: .leading, spacing: 0) {
                DashCaption(text: paused ? "Paused" : caption, size: m.caption, color: paused ? RideStyle.ground : RideStyle.dim, symbol: paused ? "pause.fill" : "stopwatch")
                    .frame(height: 68 * s)
                if engine.phase == .waiting {
                    Text("Start pedalling").font(.ftp(60 * s)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DashNumber(text: clockText(free ? (engine.session.samples.last?.time ?? 0) : max(0, left).rounded(.up)), size: m.hero, color: paused ? RideStyle.ground : RideStyle.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if free {
                    let track = RideTrack.make(engine.session)
                    Text("\(model.previewDashboardReadings["Work"] ?? String(Int(track.kilojoules))) kJ · \(model.previewDashboardReadings["Distance"] ?? String(format: "%.1f", track.distance / 1000)) km simulated")
                        .font(.ftp(40 * s, weight: .bold)).foregroundStyle(RideStyle.dim).lineLimit(1).minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true).frame(height: 40 * s)
                } else {
                    HStack(spacing: 14 * s) {
                        if workout { RoundedRectangle(cornerRadius: 7 * s).fill(targetColor).frame(width: 22 * s, height: 22 * s) }
                        Text(workout ? engine.currentStep?.step.name ?? "" : engine.phase == .cooldown ? "Cool-down · spin easy" : "Warm-up · spin easy")
                            .font(.ftp(40 * s, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
                    }.fixedSize(horizontal: false, vertical: true).frame(height: 40 * s)
                    GeometryReader { geo in
                        let duration = workout ? engine.currentStep?.step.seconds ?? 1 : engine.phase == .warmup ? configuration.warmupSeconds : configuration.cooldownSeconds
                        Capsule().fill(RideStyle.raised).overlay(alignment: .leading) {
                            Capsule().fill(workout ? targetColor : RideStyle.progressGrey).frame(width: geo.size.width * min(1, max(0, 1 - left / max(1, duration))))
                        }
                    }.frame(height: 16 * s).padding(.top, 14 * s)
                }
            }
        }
        .foregroundStyle(paused ? RideStyle.ground : RideStyle.text)
    }

    private func reading(_ title: String, value: String, unit: String, color: Color = RideStyle.text, corner: String? = nil, symbol: String? = nil, m: DashboardMetrics) -> some View {
        DashTile(scale: m.scale, fill: color == RideStyle.cyan ? RideStyle.coolTile : RideStyle.tile, horizontalPadding: 28, verticalPadding: 22) {
            VStack(spacing: 0) {
                HStack {
                    DashCaption(text: value == "—" ? "No signal · " + title : title, size: m.caption, color: value == "—" ? RideStyle.warning : color == RideStyle.text ? RideStyle.dim : color, symbol: value == "—" ? "exclamationmark.triangle" : title == "Heart rate" ? "heart.fill" : symbol)
                    Spacer(minLength: 0)
                    if let corner { Text(corner).font(.ftp((focus ? 24 : 30) * m.scale, weight: .bold)).foregroundStyle(RideStyle.dim).lineLimit(1).minimumScaleFactor(0.5) }
                }
                DashNumber(text: value, size: focus ? 150 * m.scale : m.reading, color: color, unit: unit, unitSize: (focus ? 44 : 38) * m.scale).frame(maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(value == "—" ? "No recent signal" : "\(value) \(unit)")
    }
    private func heartTile(_ m: DashboardMetrics) -> some View {
        reading("Heart rate", value: model.freshHeartRate.map(String.init) ?? "—", unit: "bpm", color: RideStyle.heart,
                corner: focus ? summary.maximumHeartRate.map { "Max \($0)" } : free ? "Avg \(whole(summary.averageHeartRate))" : nil, m: m)
    }
    private func cadenceTile(_ m: DashboardMetrics, hero: Bool = false) -> some View {
        let state = cadenceState
        let warning = focus && (state == .speedUp || engine.lowCadenceSince != nil)
        let ending: Int? = { if case .ending(let n) = state { return n }; return nil }()
        return DashTile(scale: m.scale, fill: warning ? (ending != nil ? RideStyle.heart : RideStyle.warning) : RideStyle.tile, horizontalPadding: hero ? 32 : 28, verticalPadding: hero ? 26 : 22) {
            VStack(spacing: 0) {
                HStack {
                    DashCaption(text: warning ? "Speed up" : cadence == nil ? "No signal" : "Cadence", size: m.caption, color: warning ? RideStyle.ground : cadence == nil ? RideStyle.warning : RideStyle.dim, symbol: cadence == nil ? "exclamationmark.triangle" : "speedometer")
                    Spacer(minLength: 0)
                    if free { Text("Avg \(model.previewDashboardReadings["averageCadence"] ?? whole(summary.averageCadence))").font(.ftp(30 * m.scale, weight: .bold)).foregroundStyle(RideStyle.dim) }
                    if hero && !warning { Text("keep it turning").font(.ftp(28 * m.scale, weight: .bold)).foregroundStyle(RideStyle.dim) }
                }.frame(height: hero ? 68 * m.scale : nil)
                DashNumber(text: whole(cadence), size: hero ? 300 * m.scale : m.reading, color: warning ? RideStyle.ground : RideStyle.text, unit: "rpm", unitColor: warning ? RideStyle.ground : RideStyle.dim, unitSize: (hero ? 64 : 38) * m.scale).frame(maxHeight: .infinity)
                if hero {
                    if let ending {
                        Text("Ramp ends in \(ending)").font(.ftp(40 * m.scale, weight: .bold)).foregroundStyle(RideStyle.ground)
                    } else {
                        HStack(spacing: 14 * m.scale) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    HStack(spacing: 0) { RideStyle.heart.opacity(0.6).frame(width: geo.size.width * 45/120); (warning ? RideStyle.gaugeAmberOnWarning : RideStyle.warning.opacity(0.6)).frame(width: geo.size.width * 15/120); RideStyle.raised }
                                    Circle().fill(RideStyle.text).frame(width: 28 * m.scale).offset(x: max(0, min(geo.size.width - 28 * m.scale, geo.size.width * (cadence ?? 0)/120)))
                                }.clipShape(Capsule())
                            }.frame(height: 24 * m.scale)
                            Text("ends below 45").font(.ftp(28 * m.scale, weight: .bold)).foregroundStyle(warning ? RideStyle.ground : RideStyle.dim)
                        }
                    }
                }
            }
        }.accessibilityElement(children: .combine).accessibilityLabel("Cadence")
    }

    @ViewBuilder private func thirdTile(_ m: DashboardMetrics) -> some View {
        if workout { nextTile(m) }
        else if free { reading("Avg power", value: whole(summary.averagePower), unit: "W", color: RideStyle.cyan, corner: "NP \(model.previewDashboardReadings["NP"] ?? whole(summary.normalizedPower))", symbol: "line.3.horizontal", m: m) }
        else if engine.phase == .cooldown {
            reading("Best 60 s", value: model.previewDashboardReadings["bestMinute"] ?? whole(engine.session.result?.bestMinutePower ?? engine.liveBestMinutePower), unit: "W", color: RideStyle.cyan, m: m)
        } else {
            reading("First step", value: String(configuration.preset.startingPower), unit: "W", color: RideStyle.cyan,
                    corner: "+\(configuration.preset.stepWatts) W / \(Int(configuration.preset.stepSeconds)) s", symbol: "forward.fill", m: m)
        }
    }
    private func nextTile(_ m: DashboardMetrics) -> some View {
        let plan = engine.session.training!
        let index = (engine.currentStep?.index ?? 0) + 1
        let next = plan.steps.indices.contains(index) ? plan.steps[index] : nil
        let countdown = (engine.currentStep?.remaining ?? 100) <= 10
        let zone = next.flatMap { step in plan.ftpWatts.map { IntensityZone.zone(forFraction: Double(step.watts) * Double(engine.intensity)/100 / $0) } }
        let color = countdown ? RideStyle.cyan : zone.map(zoneText) ?? RideStyle.cyan
        return Button { model.skipStep() } label: {
            DashTile(scale: m.scale, fill: countdown ? RideStyle.cyan.opacity(0.20) : zone.map { ZonePalette.color(for: $0).opacity(0.14) } ?? RideStyle.tile, horizontalPadding: 28, verticalPadding: 22) {
                VStack(spacing: 0) {
                    HStack {
                        DashCaption(text: next == nil ? "Last step" : "Next", size: m.caption, color: color, symbol: next == nil ? nil : "forward.fill")
                        Spacer(minLength: 0)
                        if let next { Text(clockText(next.seconds)).font(.ftp(30 * m.scale, weight: .bold)).foregroundStyle(RideStyle.text) }
                    }
                    DashNumber(text: next.map { String(Int((Double($0.watts) * Double(engine.intensity)/100).rounded())) } ?? "—", size: m.reading, color: color, unit: "W", unitSize: 38 * m.scale).frame(maxHeight: .infinity)
                }
            }
        }.buttonStyle(.plain).disabled(!engine.canSkipStep || busy)
            .accessibilityLabel(next.map { "Next: \($0.name), \(Int((Double($0.watts) * Double(engine.intensity)/100).rounded())) watts, \(DurationFormat.compact($0.seconds).replacingOccurrences(of: " min", with: " minutes").replacingOccurrences(of: " s", with: " seconds")). Skip to it now" } ?? "Last step")
            .accessibilityIdentifier("skip-step").keyboardShortcut(.rightArrow, modifiers: .command)
    }
    private func rampNextTile(_ m: DashboardMetrics) -> some View {
        DashTile(scale: m.scale) {
            VStack(spacing: 0) {
                DashCaption(text: "Next step", size: m.caption).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 28 * m.scale) {
                    DashNumber(text: "+\(configuration.preset.stepWatts)", size: 150 * m.scale, color: RideStyle.lime, unit: "W", unitSize: 44 * m.scale)
                    DashNumber(text: String(Int(ceil(nextRemaining))), size: 150 * m.scale, unit: "s", unitSize: 44 * m.scale)
                }.frame(maxHeight: .infinity)
                SegmentCountdown(filled: StepSegments.filled(remaining: nextRemaining, stepSeconds: configuration.preset.stepSeconds), scale: m.scale)
            }
        }
    }

    @ViewBuilder private func strip(_ m: DashboardMetrics) -> some View {
        if model.isFinishing || paused || model.trainingTransition != nil {
            DashTile(scale: m.scale, horizontalPadding: 24, verticalPadding: 12) {
                Text(model.isFinishing ? "Confirming trainer stop…" : model.trainingTransition ?? "Paused · pedal to resume")
                    .font(.ftp(m.caption, weight: .bold)).foregroundStyle(RideStyle.warning).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if training && (model.previewDashboardMore ?? more) { DashMoreMetrics(session: engine.session, scale: m.scale, more: Binding(get: { model.previewDashboardMore ?? more }, set: { model.previewDashboardMore = nil; more = $0 }), previewReadings: model.previewDashboardReadings) }
        else if model.rideVisualPlacement == .strip { RideVisualStrip(model: model, engine: engine) }
        else if !training { phaseStrip(m) }
        else {
            DashTile(scale: m.scale, horizontalPadding: 24, verticalPadding: 12) {
                VStack(spacing: 6 * m.scale) {
                    HStack(spacing: 16 * m.scale) {
                        if workout, let plan = engine.session.training {
                            Text("\(clockText((engine.session.samples.last?.time ?? 0))) ridden").frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(clockText(max(0, plan.duration - engine.trainingElapsed))) to go")
                        } else {
                            Text("Last 10 min").frame(maxWidth: .infinity, alignment: .leading)
                            chartLegend("Power", color: RideStyle.lime, scale: m.scale)
                            chartLegend("Target", color: RideStyle.dim, dashed: true, scale: m.scale)
                            chartLegend("Heart rate", color: RideStyle.heart, scale: m.scale)
                        }
                        Button { model.previewDashboardMore = nil; more = true } label: {
                            HStack(spacing: 8 * m.scale) { Text("More metrics"); Image(systemName: "chevron.up") }
                        }.buttonStyle(DashButtonStyle(scale: m.scale, size: 15, height: 36)).accessibilityIdentifier("dashboard-toggle")
                    }.font(.ftp(22 * m.scale, weight: .bold)).foregroundStyle(RideStyle.dim)
                    if workout, let plan = engine.session.training {
                        WorkoutProfileChart(plan: plan, intensity: engine.intensity, progressSeconds: engine.trainingElapsed, height: 52 * m.scale,
                                            heartRate: WorkoutClock.heartRate(engine.session), stepHeartRates: StepHeartRate.averages(session: engine.session), dashboard: true)
                    } else { LivePowerChart(session: engine.session, showsHeartRate: true, compact: true) }
                }
            }
        }
    }
    private func chartLegend(_ title: String, color: Color, dashed: Bool = false, scale: Double) -> some View {
        HStack(spacing: 8 * scale) {
            if dashed { Rectangle().stroke(color, style: StrokeStyle(lineWidth: 3 * scale, dash: [5 * scale, 3 * scale])).frame(width: 24 * scale, height: 1) }
            else { Capsule().fill(color).frame(width: 24 * scale, height: 4 * scale) }
            Text(title).foregroundStyle(RideStyle.dim)
        }
    }
    private func phaseStrip(_ m: DashboardMetrics) -> some View {
        DashTile(scale: m.scale, horizontalPadding: 24, verticalPadding: 16) {
            VStack(spacing: 0) {
                HStack {
                    Text("Warm-up · \(clockText(configuration.warmupSeconds))").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Ramp · until you stop").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cool-down · \(clockText(configuration.cooldownSeconds))")
                }.font(.ftp(24 * m.scale, weight: .bold)).foregroundStyle(RideStyle.dim)
                Spacer(minLength: 12 * m.scale)
                HStack(spacing: 6 * m.scale) {
                    GeometryReader { geo in
                        Capsule().fill(RideStyle.raised).overlay(alignment: .leading) {
                            Capsule().fill(RideStyle.progressGrey).frame(width: geo.size.width * (engine.phase == .warmup ? min(1, phaseTime / max(1, configuration.warmupSeconds)) : engine.phase == .cooldown ? 1 : 0))
                        }
                    }
                    Capsule().fill(LinearGradient(colors: [Color(red: 61/255, green: 74/255, blue: 28/255), RideStyle.lime], startPoint: .leading, endPoint: .trailing)).opacity(0.55)
                    GeometryReader { geo in
                        Capsule().fill(RideStyle.raised).overlay(alignment: .leading) {
                            Capsule().fill(RideStyle.lime).frame(width: geo.size.width * (engine.phase == .cooldown ? min(1, phaseTime / max(1, configuration.cooldownSeconds)) : 0))
                        }
                    }.frame(maxWidth: 160 * m.scale)
                }.frame(height: 32 * m.scale)
            }
        }
    }
    private func rampFooter(_ m: DashboardMetrics) -> some View {
        HStack {
            (Text("Ramp time ") + Text(clockText(phaseTime)).foregroundColor(RideStyle.text))
            Spacer()
            (Text("Best 60 s ") + Text("\(model.previewDashboardReadings["bestMinute"] ?? whole(engine.liveBestMinutePower)) W").foregroundColor(RideStyle.cyan))
            Spacer()
            Text(configuration.resolvedCadenceSource == .unavailable ? "No cadence source · hold to finish" : "Stop pedalling to finish").lineLimit(1).minimumScaleFactor(0.6)
        }.font(.ftp(28 * m.scale, weight: .bold)).foregroundStyle(RideStyle.dim)
    }

    private var shortcuts: some View {
        Group {
            Button("") { adjust(1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { adjust(-1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { adjust(1, large: true) }.keyboardShortcut(.upArrow, modifiers: .shift)
            Button("") { adjust(-1, large: true) }.keyboardShortcut(.downArrow, modifiers: .shift)
        }.disabled(!training || busy).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
    private func cues() {
        defer { previousCadence = cadenceState }
        if workout, engine.phase == .riding, let current = engine.currentStep {
            if current.index == previousStep, sound {
                for _ in StepCue.due(remaining: current.remaining, previous: previousRemaining) { RideCueSound.play(.step) }
            }
            previousStep = current.index; previousRemaining = current.remaining
        } else { previousRemaining = nil }
        guard focus, sound else { return }
        if previousCadence == .normal && cadence.map({ $0 < 60 }) == true { RideCueSound.play(.low) }
        if case .ending(let n) = cadenceState, lastTickSound != n { RideCueSound.play(.tick); lastTickSound = n }
        if engine.lowCadenceSince == nil { lastTickSound = nil }
    }
}

private enum RideCueSound {
    enum Cue { case step, low, tick }
    static func play(_ cue: Cue) {
        #if os(macOS)
        let name = cue == .low ? "Basso" : cue == .tick ? "Tink" : "Pop"
        NSSound(named: NSSound.Name(name))?.play()
        #else
        AudioServicesPlaySystemSound(cue == .low ? 1053 : 1104)
        #endif
    }
}
