import SwiftUI
import Charts
import FTPunkDomain

struct RideView: View {
    @Bindable var model: AppModel
    @ViewState private var info: TestInfo? = nil
    @ViewState private var confirmingStop = false
    var body: some View {
        NavigationStack {
            ScrollView {
                if let engine = model.engine {
                    VStack(spacing: 20) {
                        header(engine)
                        if engine.session.isDemo {
                            Label(model.mockPaused && model.isActive ? "DEBUG · STREAM PAUSED" : "DEBUG · MOCK SENSOR STREAM", systemImage: "ladybug")
                                .font(.caption.bold()).foregroundStyle(.orange)
                        }
                        if model.isActive {
                            liveDashboard(engine)
                        } else if let result = engine.session.result {
                            ResultCard(result: result)
                            Button { info = .estimate } label: { Label("How this estimate is calculated", systemImage: "info.circle") }
                        } else {
                            ContentUnavailableView("No FTP estimate", systemImage: "waveform.path",
                                                   description: Text("A valid, continuous 60-second ramp window is required."))
                        }
                        if let result = engine.session.result, model.isActive { ResultCard(result: result) }
                        PowerChart(session: engine.session)
                        if let reason = engine.session.endReason { Text(reason).foregroundStyle(.orange) }
                        if model.isActive {
                            if engine.session.isDemo {
                                DisclosureGroup("Debug controls") { DebugControlsView(model: model) }
                            }
                        } else {
                            Label("\(engine.session.outcome?.title ?? "Finished") · saved locally", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                            if !engine.session.isDemo {
                                if engine.session.result != nil {
                                    Button("Use this FTP for \(engine.session.riderName)") { model.adopt(engine.session) }
                                }
                                if model.connection != nil {
                                    Button("Upload to Intervals.icu…") { model.requestUpload(engine.session) }
                                        .disabled(model.jobs.contains { $0.sessionID == engine.session.id && $0.accountID == model.connection?.athleteID })
                                }
                            }
                            Button("Set up another test") { model.selectedTab = 0 }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                        }
                    }.padding().frame(maxWidth: 850)
                        .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Ready when you are", systemImage: "bicycle")
                    } description: { Text("Choose a rider and protocol to get started.") }
                    actions: { Button("Set up a test") { model.selectedTab = 0 }.buttonStyle(.borderedProminent) }
                        .padding(.top, 60)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.isActive {
                    HStack(spacing: 12) {
                        if model.engine?.phase == .ramp {
                            Button("Finish ramp", action: model.finishRamp)
                                .buttonStyle(.borderedProminent)
                                .accessibilityHint("End the scored ramp and begin cooldown")
                        }
                        Button("Stop & save", role: .destructive) { confirmingStop = true }
                            .buttonStyle(.bordered).tint(.red)
                    }.controlSize(.large).frame(maxWidth: .infinity).padding().background(.bar)
                }
            }
            .navigationTitle(model.isActive ? "Ride" : "Your result")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .sheet(item: $info) { ProtocolInfoView(topic: $0) }
                .confirmationDialog("Stop the test and save the recording?", isPresented: $confirmingStop, titleVisibility: .visible) {
                    Button("Stop and save", role: .destructive, action: model.stop)
                } message: { Text("If the ramp has enough valid data, an estimate will be calculated. You can finish the ramp normally to include a cooldown.") }
        }
    }
    private func header(_ engine: RampEngine) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.phase.title.uppercased()).font(.headline).foregroundStyle(Theme.accent)
                Text("\(engine.session.riderName) · \(engine.session.configuration.preset.title)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(clock(model.elapsed)).font(.headline).monospacedDigit()
                Text("TOTAL TIME").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func liveDashboard(_ engine: RampEngine) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                powerTile("TARGET", value: engine.targetPower, tint: Theme.accent)
                powerTile("PEDAL POWER", value: freshPower(engine), tint: .primary)
            }
            VStack(spacing: 8) {
                if engine.phase == .ramp {
                    let step = engine.session.configuration.preset.stepSeconds
                    let phaseTime = max(0, model.elapsed - engine.phaseStartedAt)
                    let remaining = step - phaseTime.truncatingRemainder(dividingBy: step)
                    HStack {
                        Text("Next +\(engine.session.configuration.preset.stepWatts) W")
                        Spacer()
                        Text("in \(Int(ceil(remaining))) s").bold().monospacedDigit()
                    }.font(.title3)
                    ProgressView(value: step - remaining, total: step)
                    HStack {
                        Text("Step \(Int(phaseTime / step) + 1)")
                        Spacer()
                        Text("Ramp \(clock(phaseTime))").monospacedDigit()
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    let duration = engine.phase == .warmup ? engine.session.configuration.warmupSeconds : engine.session.configuration.cooldownSeconds
                    let phaseTime = max(0, model.elapsed - engine.phaseStartedAt)
                    HStack {
                        Text(engine.phase == .waiting ? "Start pedaling" : engine.phase == .warmup ? "Ramp starts in" : "Cooldown remaining")
                        Spacer()
                        if engine.phase != .waiting { Text(clock(max(0, duration - phaseTime))).bold().monospacedDigit() }
                    }.font(.title3)
                    if duration > 0 { ProgressView(value: min(duration, phaseTime), total: duration) }
                }
            }
            HStack {
                RideMetric(title: "CADENCE", value: engine.lastCadence.flatMap { model.elapsed - $0.time <= 2 ? "\(Int($0.rpm))" : nil } ?? "—", unit: "rpm")
                RideMetric(title: "HEART RATE", value: model.freshHeartRate.map(String.init) ?? "—", unit: "bpm")
            }
            Label(model.demoMode ? "Mock sensors · no trainer commands" : model.bluetooth.trainerReady ? "ERG control · pedal power source" : "Trainer connection needs attention",
                  systemImage: model.demoMode ? "play.rectangle" : "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary)
            Text(engine.phase == .cooldown ? "Ramp scored. Spin gently to cool down." : "Stay seated. Keep a steady, comfortable cadence.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private func freshPower(_ engine: RampEngine) -> Int? {
        engine.lastPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts.rounded()) : nil }
    }
    private func powerTile(_ title: String, value: Int?, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .foregroundStyle(tint)
            Text("WATTS").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }
    private func clock(_ value: Double) -> String { "\(Int(value) / 60):\(String(format: "%02d", Int(value) % 60))" }
}

private struct RideMetric: View {
    let title: String
    let value: String
    let unit: String
    var body: some View {
        VStack(spacing: 5) {
            Text("\(value) \(unit)").font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct PowerChart: View {
    let session: TestSession
    private struct Point: Identifiable {
        let id: Int
        let time: Double
        let power: Double
        let segment: Int
    }
    private var points: [Point] {
        var result: [Point] = [], segment = 0
        var previous: Double?
        for (i, sample) in session.samples.enumerated() {
            guard let power = sample.power else { continue }
            if let previous, sample.time - previous > 2 { segment += 1 }
            result.append(Point(id: i, time: sample.time, power: power, segment: segment)); previous = sample.time
        }
        return result
    }
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Minutes", point.time / 60), y: .value("Pedal power", point.power),
                     series: .value("Continuous signal", point.segment))
                .foregroundStyle(Theme.accent)
        }.chartXAxisLabel("Minutes").chartYAxisLabel("Pedal W").frame(height: 160)
            .accessibilityLabel("Recorded pedal power over time")
    }
}

struct ResultCard: View {
    let result: FTPResult
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ESTIMATED FTP").font(.caption.bold()).foregroundStyle(Theme.accent)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { resultValues }
                VStack(alignment: .leading) { resultValues }
            }
            Text("72–77% range: \(Int(result.lowerFTP.rounded()))–\(Int(result.upperFTP.rounded())) W")
            Text("\(Int(result.factor * 100))% of best 60 seconds · \(Int(result.bestMinutePower.rounded())) W. A training estimate.")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }
    @ViewBuilder private var resultValues: some View {
        Text("\(Int(result.estimatedFTP.rounded())) W").font(.largeTitle.bold())
        if let wkg = result.wattsPerKG { Text("\(wkg, specifier: "%.2f") W/kg").font(.title3).foregroundStyle(.secondary) }
    }
}
