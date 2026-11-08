import SwiftUI
import FTPunkDomain

/// What a finished or interrupted activity shows: the training result first, then what it means for
/// training, then sharing. Debug and interrupted results use the same layout.
struct ResultView: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    @State private var info: TestInfo?

    private var session: TestSession { engine.session }
    private var rider: RiderProfile? { model.riders.first { $0.id == session.riderID } }
    private var currentFTP: Double? { rider?.currentFTP?.watts }
    private var isFTPResult: Bool { session.result != nil && session.training == nil }
    private var adopted: Bool {
        session.result.map { FTPAdoption.isAdopted(rider: rider, result: $0, sessionStart: session.startedAt) } ?? false
    }
    private var canUpload: Bool { model.connections[session.riderID] != nil && !session.isDemo && session.endedAtOffset != nil }
    private var canAdopt: Bool { isFTPResult && !session.isDemo && !adopted }

    var body: some View {
        let sections = ResultLayout.sections(isFTPResult: isFTPResult, adopted: adopted && !session.isDemo, canUpload: canUpload)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                topBadges
                ForEach(sections, id: \.rawValue) { section in
                    switch section {
                    case .headline: headline
                    case .chart: chart
                    case .decision: decision
                    case .trainingHandoff: handoff
                    case .upload: upload
                    }
                }
                if session.endedAtOffset != nil, !session.samples.isEmpty { RideSummaryCard(session: session) }
                if session.endedAtOffset != nil, !session.samples.isEmpty { ActivityExportControls(model: model, session: session) }
            }
            .padding(Space.l).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(item: $info) { ProtocolInfoView(topic: $0) }
    }

    // MARK: Sections

    @ViewBuilder private var topBadges: some View {
        if session.isDemo { StatusPill(text: "Debug · mock sensor data · never uploads", symbol: "ladybug", tone: .warning) }
        if model.isFinishing { Label("Confirming trainer stop…", systemImage: "hourglass").font(.headline).foregroundStyle(Theme.warning) }
    }

    @ViewBuilder private var headline: some View {
        if session.outcome == .interrupted {
            let summary = InterruptionSummary.make(session)
            VStack(alignment: .leading, spacing: Space.s) {
                Label(summary.headline, systemImage: "exclamationmark.triangle.fill").font(.title2.bold()).foregroundStyle(Theme.warning)
                Text(summary.reason).font(.body)
                Text(summary.saved).font(.callout).foregroundStyle(Theme.secondary)
                if let result = session.result { resultFigures(result) }
            }
            .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).ftpCard(tint: Theme.warning, fill: 0.08)
            .accessibilityElement(children: .combine)
        } else if let result = session.result, session.training == nil {
            resultFigures(result)
        } else if session.training != nil {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(session.outcome == .completed ? "Ride complete" : "Ride saved", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(Theme.accent)
                Text(session.activityTitle).font(.headline)
                HStack(spacing: Space.l) {
                    stat("Time", DurationFormat.clock(session.endedAtOffset ?? 0))
                }
                Text("Saved on this device.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).ftpCard(tint: Theme.accent, fill: 0.07)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                Label(session.outcome?.title ?? "Ride saved", systemImage: "waveform.path").font(.title2.bold())
                Text("No FTP estimate. A valid, continuous 60-second ramp window is required, and the scored ramp must end by finishing or exhaustion.")
                    .font(.callout).foregroundStyle(Theme.secondary)
                Text("The recording is saved on this device.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).ftpCard(fill: 0.05)
            .accessibilityElement(children: .combine)
        }
    }

    private func resultFigures(_ result: FTPResult) -> some View {
        FTPResultCard(result: result, currentFTP: currentFTP, showDelta: !session.isDemo)
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
    }

    @ViewBuilder private var chart: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            RideCharts(session: session)
            if session.training == nil { CalculationNote(result: session.result) { info = .estimate } }
            if let reason = session.endReason, session.outcome != .interrupted { Text(reason).font(.callout).foregroundStyle(Theme.warning) }
        }
    }

    @ViewBuilder private var decision: some View {
        if let result = session.result {
            Label("\(session.riderName)’s FTP is now \(Int(result.estimatedFTP.rounded())) W", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(Theme.accent)
                .accessibilityIdentifier("ftp-adopted")
        }
    }

    @ViewBuilder private var handoff: some View {
        if let result = session.result {
            let previous = session.configuration.priorFTP?.watts ?? currentFTP
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("WHAT THIS CHANGES").ftpLabel().foregroundStyle(Theme.accent)
                Text("Library workouts now use \(Int(result.estimatedFTP.rounded())) W").font(.headline)
                if let example = RetargetExample.make(oldFTP: previous, newFTP: result.estimatedFTP), example.oldWatts != example.newWatts {
                    Text(example.text).font(.body).monospacedDigit()
                }
                Text("Warm-ups use 50 % of this FTP. Earlier rides keep the FTP they were made with.").font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).ftpCard(fill: 0.05)
            .accessibilityElement(children: .combine).accessibilityIdentifier("training-handoff")
        }
    }

    @ViewBuilder private var upload: some View {
        let queued = model.jobs.first { $0.sessionID == session.id && $0.accountID == model.connections[session.riderID]?.athleteID }
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { model.requestUpload(session) } label: {
                Label(queued == nil ? "Upload to Intervals.icu…" : "Upload \(queued!.status.rawValue)", systemImage: "arrow.up.circle")
            }
            .buttonStyle(FTPunkRowButtonStyle()).disabled(queued != nil || model.isBusy)
            Text("You will be asked to confirm the rider and account before anything is sent.").font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    // MARK: Bottom bar

    @ViewBuilder private var bottomBar: some View {
        if canAdopt, let result = session.result {
            PrimaryActionBar(title: "Use \(Int(result.estimatedFTP.rounded())) W as \(session.riderName)’s FTP", systemImage: "checkmark.circle",
                             isEnabled: !model.isBusy, action: { model.adopt(session) }) {
                Button(currentFTP.map { "Keep \(Int($0.rounded())) W" } ?? "Not now") { model.closeCockpit() }
                    .buttonStyle(FTPunkSecondaryButtonStyle()).controlSize(.large).frame(maxWidth: .infinity)
                    .disabled(model.isFinishing).accessibilityIdentifier("keep-ftp")
            }
        } else {
            PrimaryActionBar(title: adopted && !session.isDemo ? "Back to Home" : "Done",
                             reason: model.isFinishing ? "Confirming the trainer stop…" : nil, isEnabled: !model.isFinishing, action: { model.closeCockpit() })
        }
    }
}
