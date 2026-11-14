import SwiftUI
import FTPunkDomain

struct DashHeader: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    let scale: Double
    let phone: Bool
    let showDebug: () -> Void
    @AppStorage("dashboardShowsMoreReadings") private var more = false
    private var training: Bool { engine.session.training != nil }
    private var free: Bool { engine.session.training?.kind == .freeRide }
    private var focus: Bool { !training && engine.phase == .ramp }
    private var paused: Bool { engine.phase == .paused }
    private var busy: Bool { model.trainingTransition != nil || model.isFinishing }
    var body: some View {
        if phone { compactHeader } else { wideHeader }
    }
    private var wideHeader: some View {
        HStack(spacing: 16 * scale) {
            Button { model.cockpitPresented = false } label: { Image(systemName: "chevron.down") }
                .accessibilityLabel("Minimise ride").accessibilityIdentifier("minimise-ride")
            Text(training ? free ? "FREE RIDE" : "WORKOUT" : "FTP TEST")
                .font(.ftp(15 * scale, weight: .bold)).foregroundStyle(RideStyle.ground)
                .padding(.horizontal, 14 * scale).frame(height: 30 * scale).background(RideStyle.lime, in: Capsule())
            if free {
                HStack(spacing: 0) {
                    modeButton(phone ? "ERG" : "ERG · hold watts", resistance: false)
                    modeButton(phone ? "Resistance" : "Resistance · fixed level", resistance: true)
                }.background(RideStyle.raised, in: Capsule())
            } else if !phone {
                Text(training ? engine.session.activityTitle : ftpTitle)
                    .font(.ftp(24 * scale, weight: .bold)).lineLimit(1).minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
            if !focus && !phone {
                HStack(spacing: 14 * scale) {
                    deviceDot("Trainer", connected: model.demoMode || model.bluetooth.names[.trainer] != nil)
                    deviceDot("Power", connected: engine.lastPower.map { model.elapsed - $0.time <= 2 } == true)
                    deviceDot("Heart rate", connected: model.freshHeartRate != nil)
                }
                Text(model.previewDashboardReadings["headerClock"] ?? clockText(model.elapsed)).font(.ftp(24 * scale, weight: .bold)).monospacedDigit()
            }
            if engine.session.isDemo {
                debugChip(size: 12 * scale)
            }
            if training {
                Button { paused ? model.resumeTraining() : model.pauseTraining() } label: {
                    Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill")
                }.disabled(busy).keyboardShortcut("p", modifiers: [.command, .shift]).accessibilityIdentifier("pause-resume")
                .background {
                    Button("") { paused ? model.resumeTraining() : model.pauseTraining() }
                        .keyboardShortcut(.space, modifiers: []).disabled(busy).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                }
            }
            if focus {
                HoldToConfirmButton(title: "Hold to finish", systemImage: "flag.checkered", accessibilityActionName: "Finish ramp now",
                                    shortcut: KeyboardShortcut("f", modifiers: [.command, .shift]), identifier: "hold-to-finish", dashboardScale: scale) { model.finishRamp() }
                    .frame(maxWidth: 190 * scale)
            }
            Button("Stop & save") { model.stop() }.keyboardShortcut(".", modifiers: .command).accessibilityIdentifier("stop-save")
            Menu {
                if training { Button((model.previewDashboardMore ?? more) ? "Chart" : "More metrics") { let value = model.previewDashboardMore ?? more; model.previewDashboardMore = nil; more = !value }.keyboardShortcut("m", modifiers: []) }
                RideVisualMenu(model: model)
                if engine.session.isDemo { Button("Debug controls…", action: showDebug) }
            } label: { optionsLabel }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("More options")
        }.buttonStyle(DashButtonStyle(scale: scale))
    }
    private var compactHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button { model.cockpitPresented = false } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Minimise ride").accessibilityIdentifier("minimise-ride")
                Text(training ? free ? "FREE RIDE" : "WORKOUT" : "FTP TEST").font(.ftp(15, weight: .bold))
                    .foregroundStyle(RideStyle.lime)
                Spacer(minLength: 0)
                if engine.session.isDemo { debugChip(size: 10) }
                Menu {
                    if training {
                        Button((model.previewDashboardMore ?? more) ? "Chart" : "More metrics") {
                            let value = model.previewDashboardMore ?? more; model.previewDashboardMore = nil; more = !value
                        }.keyboardShortcut("m", modifiers: [])
                    }
                    RideVisualMenu(model: model)
                    if engine.session.isDemo { Button("Debug controls…", action: showDebug) }
                } label: { optionsLabel }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).accessibilityLabel("More options")
            }
            if free { HStack(spacing: 0) { modeButton(phone ? "ERG" : "ERG · hold watts", resistance: false); modeButton(phone ? "Resistance" : "Resistance · fixed level", resistance: true) } }
            HStack {
                if training {
                    Button(paused ? "Resume" : "Pause") { paused ? model.resumeTraining() : model.pauseTraining() }
                        .disabled(busy).keyboardShortcut("p", modifiers: [.command, .shift]).accessibilityIdentifier("pause-resume")
                        .background {
                            Button("") { paused ? model.resumeTraining() : model.pauseTraining() }
                                .keyboardShortcut(.space, modifiers: []).disabled(busy).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                        }
                }
                if focus {
                    HoldToConfirmButton(title: "Hold to finish", accessibilityActionName: "Finish ramp now",
                                        shortcut: KeyboardShortcut("f", modifiers: [.command, .shift]), identifier: "hold-to-finish", dashboardScale: scale) { model.finishRamp() }
                }
                Button("Stop & save") { model.stop() }.keyboardShortcut(".", modifiers: .command).accessibilityIdentifier("stop-save")
            }
        }.buttonStyle(DashButtonStyle(scale: max(0.8, scale)))
    }
    private var ftpTitle: String {
        let protocolName = engine.session.configuration.preset.title
        switch engine.phase {
        case .ramp: return "Ramp · " + protocolName
        case .warmup, .waiting: return "Warm-up · then ramp " + protocolName
        case .cooldown: return "Cool-down · " + protocolName
        default: return protocolName
        }
    }
    private var optionsLabel: some View {
        Image(systemName: "ellipsis").font(.ftp(20 * scale, weight: .bold)).foregroundStyle(RideStyle.text)
            .frame(width: 44 * scale, height: 44 * scale).background(RideStyle.raised, in: Circle())
    }
    private func debugChip(size: Double) -> some View {
        Text("Debug · mock sensors").font(.ftp(size, weight: .bold)).foregroundStyle(RideStyle.warning)
            .padding(.horizontal, 8 * scale).padding(.vertical, 5 * scale)
            .background(RideStyle.warning.opacity(0.12), in: Capsule())
    }
    private func modeButton(_ title: String, resistance: Bool) -> some View {
        Button { model.switchFreeRideMode(resistance: resistance) } label: {
            Text(title).font(.ftp(18 * scale, weight: .bold)).lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, 18 * scale).frame(height: 44 * scale)
                .foregroundStyle((engine.resumeResistance != nil) == resistance ? RideStyle.ground : RideStyle.dim)
                .background((engine.resumeResistance != nil) == resistance ? RideStyle.lime : .clear, in: Capsule())
        }.buttonStyle(.plain).disabled(model.resistanceLimits == nil || busy)
            .help(model.resistanceLimits == nil ? "Trainer doesn't offer resistance" : "Change trainer mode")
    }
    private func deviceDot(_ title: String, connected: Bool) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: connected ? "circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10 * scale)).foregroundStyle(connected ? RideStyle.lime : RideStyle.warning)
            Text(title).font(.ftp(16 * scale, weight: .bold)).foregroundStyle(RideStyle.dim)
        }.accessibilityLabel("\(title): \(connected ? "connected" : "No signal")")
    }
}

struct DashMoreMetrics: View {
    let session: TestSession
    let scale: Double
    @Binding var more: Bool
    var previewReadings: [String: String] = [:]
    var body: some View {
        let summary = RideSummary.make(session), track = RideTrack.make(session)
        let values: [(String, String, String)] = [
            ("Normalized", whole(summary.normalizedPower), "W"), ("Max power", whole(summary.maximumPower), "W"),
            ("Work", whole(summary.kilojoules), "kJ"), ("Calories", whole(summary.kilocalories), "kcal"),
            ("Speed", RideFigures.kilometresPerHour(track.speed(at: session.samples.last?.time ?? 0)), "km/h"),
            ("Distance", RideFigures.kilometres(track.distance), "km"),
            ("Balance", summary.leftBalance.map(RideFigures.balance) ?? "—", ""),
            ("Max HR", summary.maximumHeartRate.map(String.init) ?? "—", "bpm")]
        DashTile(scale: scale, horizontalPadding: 14, verticalPadding: 14) {
            HStack(spacing: 10 * scale) {
                ForEach(values.indices, id: \.self) { index in
                    let item = values[index]
                    VStack(alignment: .leading, spacing: 8 * scale) {
                        Text(item.0.uppercased()).font(.ftp(15 * scale, weight: .bold)).foregroundStyle(RideStyle.dim)
                        DashNumber(text: previewReadings[item.0] ?? item.1, size: 38 * scale, unit: item.2, unitSize: 18 * scale)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.horizontal, 14 * scale).background(RideStyle.raised, in: RoundedRectangle(cornerRadius: 18 * scale)).accessibilityElement(children: .combine)
                }
                if session.configuration.resolvedPowerSource == .externalPowerMeter {
                    VStack { Text("Trainer").font(.ftp(18 * scale)); DashNumber(text: whole(summary.trainerAveragePower), size: 36 * scale, unit: "W") }
                }
                Button { more = false } label: {
                    VStack(spacing: 6 * scale) { Image(systemName: "chevron.down"); Text("Chart") }
                        .font(.ftp(15 * scale, weight: .bold)).foregroundStyle(RideStyle.text)
                        .padding(.horizontal, 16 * scale).frame(maxHeight: .infinity)
                        .background(RideStyle.raised, in: RoundedRectangle(cornerRadius: 18 * scale))
                }.buttonStyle(.plain).accessibilityIdentifier("dashboard-toggle")
            }
        }
    }
    private func whole(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "—" }
}
