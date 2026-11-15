import SwiftUI
import FTPunkDomain

/// Result and saved-history detail share the same presentation and existing model actions.
struct RideSummaryView: View {
    @Bindable var model: AppModel
    let session: TestSession
    var history = false
    let done: () -> Void
    var delete: (() -> Void)? = nil
    @State private var hover = RideChartHover(showsFloatingCard: false)
    @State private var info: TestInfo?
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var rider: RiderProfile? { model.riders.first { $0.id == session.riderID } }
    private var currentFTP: Double? { rider?.currentFTP?.watts }
    private var adopted: Bool { session.result.map { FTPAdoption.isAdopted(rider: rider, result: $0, sessionStart: session.startedAt) } ?? false }
    private var canAdopt: Bool { session.training == nil && session.result != nil && !session.isDemo && !adopted }
    private var canUpload: Bool { !session.isDemo && session.endedAtOffset != nil && model.connections[session.riderID] != nil }
    private var job: ActivityUploadJob? { model.jobs.first { $0.sessionID == session.id } }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1100 && !model.previewPhoneLayout
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(wide: wide)
                    if session.isDemo { StatusPill(text: "Debug · mock sensor data · never uploads", symbol: "ladybug", tone: .warning) }
                    if model.isFinishing { Label("Confirming trainer stop…", systemImage: "hourglass").foregroundStyle(Theme.warning) }
                    if wide {
                        HStack(alignment: .top, spacing: 20) {
                            hero(wide: true).frame(width: 540, height: 244)
                            figures.frame(maxWidth: .infinity).frame(height: 244)
                        }
                    } else { hero(wide: false); figures }
                    CombinedRideChart(session: session, hover: hover, height: wide ? max(220, geometry.size.height - 564) : 240)
                    disclosures(wide: wide)
                    if adopted && !session.isDemo, let result = session.result {
                        Text("Library workouts now use \(Int(result.estimatedFTP.rounded())) W. Earlier rides keep their original FTP.").ftpText(.callout).foregroundStyle(Theme.secondary).accessibilityIdentifier("training-handoff")
                    }
                    if session.training != nil { steps }
                    DisclosureGroup("This activity") { metadata }.padding(22).ftpCard(fill: 0)
                }.padding(.horizontal, wide ? 32 : 16).padding(.vertical, 28).frame(maxWidth: 1600).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !wide && canAdopt { adoptionActions.padding(16).background(Theme.surface) }
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        #if os(macOS)
        .toolbar(.hidden, for: .windowToolbar)
        #endif
        .sheet(item: $info) { ProtocolInfoView(topic: $0) }
    }
    private func header(wide: Bool) -> some View {
        (wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.activityTitle).font(.ftp(24))
                Text("\(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(session.riderName) · saved on this device")
                    .ftpText(.callout).foregroundStyle(Theme.secondary)
            }
            if wide { Spacer(minLength: 8) }
            uploadChip
            ActivityExportControls(model: model, session: session, compact: true)
            Button("Done", action: done).buttonStyle(FTPunkPrimaryButtonStyle()).disabled(model.isFinishing).accessibilityIdentifier(canAdopt ? "summary-done" : "primary-action")
            if let delete {
                Menu { Button("Delete…", role: .destructive, action: delete).disabled(model.isActive && model.engine?.session.id == session.id) } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Activity options").accessibilityIdentifier("detail-menu")
            }
        }
    }
    private func hero(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result = session.result, session.training == nil {
                Text("ESTIMATED FTP").ftpText(.caption, weight: .bold).foregroundStyle(Theme.accent)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    DashNumber(text: String(Int(result.estimatedFTP.rounded())), size: 92, color: Theme.text, unit: "W", unitColor: Theme.secondary, unitSize: 40)
                    if let wkg = result.wattsPerKG { Text(String(format: "%.2f W/kg", wkg)).font(.ftp(22, weight: .semibold)).foregroundStyle(Theme.secondary) }
                }
                let delta = ResultDelta(newFTP: result.estimatedFTP, currentFTP: currentFTP)
                Text("\(delta.text) · \(Int((result.factor * 100).rounded())) % of best minute \(Int(result.bestMinutePower.rounded())) W")
                    .ftpText(.subheadline, weight: .semibold).foregroundStyle(delta.watts < 0 ? Theme.warning : Theme.secondary)
                if canAdopt && wide { adoptionActions }
                else if adopted && !session.isDemo { Label("\(session.riderName)’s FTP is now \(Int(result.estimatedFTP.rounded())) W", systemImage: "checkmark.circle.fill").accessibilityIdentifier("ftp-adopted") }
            } else {
                Text(session.outcome == .interrupted ? "Ride interrupted" : "Ride saved").font(.ftp(34)).foregroundStyle(session.outcome == .interrupted ? Theme.warning : Theme.accent)
                Text(session.activityTitle).ftpText(.headline, weight: .bold)
                Text(DurationFormat.clock(session.endedAtOffset ?? 0)).font(.ftp(60)).monospacedDigit()
                if session.outcome == .interrupted { Text(InterruptionSummary.make(session).reason).foregroundStyle(Theme.secondary) }
                else if session.training == nil { Text("No FTP estimate. A valid, continuous 60-second ramp window is required.").ftpText(.callout).foregroundStyle(Theme.secondary) }
            }
        }.padding(.horizontal, 26).padding(.vertical, 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).ftpCard(tint: Theme.accent, fill: 0.06)
    }
    private var adoptionActions: some View {
        HStack(spacing: 10) {
            if let result = session.result {
                Button("Use \(Int(result.estimatedFTP.rounded())) W as \(session.riderName)’s FTP") { model.adopt(session) }
                    .buttonStyle(FTPunkPrimaryButtonStyle()).disabled(model.isBusy).accessibilityIdentifier(history ? "detail-adopt" : "primary-action")
                Button(currentFTP.map { "Keep \(Int($0.rounded())) W" } ?? "Not now", action: done)
                    .buttonStyle(FTPunkSecondaryButtonStyle()).disabled(model.isFinishing).accessibilityIdentifier("keep-ftp")
            }
        }
    }
    private var figures: some View {
        let summary = RideSummary.make(session)
        let values: [(String, String, String)] = [
            ("Time", DurationFormat.clock(summary.duration), ""),
            session.result.map { ("Best minute", String(Int($0.bestMinutePower.rounded())), "W") } ?? ("Average power", whole(summary.averagePower), "W"),
            session.result != nil ? ("Average power", whole(summary.averagePower), "W") : ("Max power", whole(summary.maximumPower), "W"),
            ("Normalized power", whole(summary.normalizedPower), "W"),
            ("Average heart rate", whole(summary.averageHeartRate), "bpm"), ("Max heart rate", summary.maximumHeartRate.map(String.init) ?? "—", "bpm"),
            ("Average cadence", whole(summary.averageCadence), "rpm"), ("Work", whole(summary.kilojoules), "kJ")]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: sizeClass == .compact || model.previewPhoneLayout ? 2 : 4), spacing: 12) {
            ForEach(values.indices, id: \.self) { index in
                let item = values[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0.uppercased()).ftpText(.caption, weight: .bold).foregroundStyle(item.0.contains("heart") ? Theme.heart : Theme.secondary)
                    DashNumber(text: model.previewSummaryValues[item.0] ?? item.1, size: 34, color: item.0.contains("heart") ? Theme.heart : Theme.text, unit: item.2, unitColor: Theme.secondary, unitSize: 16)
                }.padding(18).frame(maxWidth: .infinity, minHeight: 116, alignment: .leading).ftpCard(fill: 0)
            }
        }.accessibilityIdentifier("ride-summary")
    }
    private func disclosures(wide: Bool) -> some View {
        (wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))) {
            DisclosureGroup {
                if let hrv = HeartRateVariability.make(session) { RideAlphaChart(session: session, hrv: hrv, hover: hover) }
                else { Text("No beat-to-beat intervals recorded.").foregroundStyle(Theme.secondary) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Heart-rate variability").ftpText(.headline, weight: .bold)
                    Text(HeartRateVariability.make(session)?.rmssd.map { String(format: "RMSSD %.1f ms · DFA α1 chart", $0) } ?? "RR intervals from your heart-rate strap").ftpText(.footnote).foregroundStyle(Theme.secondary)
                }
            }.padding(22).frame(maxWidth: .infinity).ftpCard(fill: 0)
            DisclosureGroup {
                if let balance = RideBalance.make(session) { RideBalanceChart(balance: balance, session: session, hover: hover) }
                else { Text("No balance data recorded.").foregroundStyle(Theme.secondary) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pedal balance").ftpText(.headline, weight: .bold)
                    if let left = RideBalance.make(session)?.left {
                        Text("Left \(Int(left.rounded())) % · right \(100 - Int(left.rounded())) %").ftpText(.footnote).foregroundStyle(Theme.secondary)
                    } else { Text("Left and right work").ftpText(.footnote).foregroundStyle(Theme.secondary) }
                }
            }.padding(22).frame(maxWidth: .infinity).ftpCard(fill: 0)
            VStack { CalculationNote(result: session.result) { info = .estimate } }.padding(22).frame(maxWidth: .infinity).ftpCard(fill: 0)
        }
    }
    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps").ftpText(.title3, weight: .bold)
            HStack { Text("Step").frame(maxWidth: .infinity, alignment: .leading); Text("Time").frame(width: 70); Text("Target").frame(width: 110); Text("Avg power").frame(width: 95); Text("Avg HR").frame(width: 80) }.foregroundStyle(Theme.secondary)
            ForEach(Array(StepRideAverages.make(session: session).enumerated()), id: \.offset) { _, step in
                HStack {
                    Text(step.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(DurationFormat.clock(step.seconds)).frame(width: 70)
                    Text(step.target).frame(width: 110)
                    Text(whole(step.power) + " W").frame(width: 95)
                    Text(whole(step.heartRate) + " bpm").frame(width: 80)
                }.ftpText(.callout).monospacedDigit().accessibilityElement(children: .combine)
            }
        }.padding(22).ftpCard(fill: 0)
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Power: \(session.configuration.resolvedPowerSource.title) · Cadence: \(session.configuration.resolvedCadenceSource.title)")
            Text("Rider: \(session.riderName) · \(session.outcome?.title ?? "Recording")")
            if let reason = session.endReason { Text(reason).foregroundStyle(Theme.warning) }
            let summary = RideSummary.make(session)
            Text("Estimated calories: \(whole(summary.kilocalories)) kcal · Simulated distance: \(summary.distance.map(RideFigures.kilometres) ?? "—") km")
            if let trainer = summary.trainerAveragePower { Text("Trainer average power: \(Int(trainer.rounded())) W") }
        }.ftpText(.callout)
    }
    private var uploadChip: some View {
        Menu {
            if job?.status == .queued || job?.status == .needsAttention { Button("Retry upload") { Task { await model.flushUploads(manual: true) } } }
            if job != nil { Button("Upload again…") { model.requestReupload(session) }.accessibilityIdentifier("reupload-activity") }
            else { Button("Upload activity…") { model.requestUpload(session) } }
        } label: { Label(job.map { "Upload: \($0.status.rawValue)" } ?? "Saved locally", systemImage: job?.status == .uploaded ? "checkmark.icloud" : "checkmark.circle") }
            .menuStyle(.button).buttonStyle(FTPunkSecondaryButtonStyle()).menuIndicator(.hidden)
            .disabled(!canUpload || model.isBusy || job?.status == .uploading)
    }
    private func whole(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "—" }
}
