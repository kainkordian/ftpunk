import SwiftUI
import FTPunkDomain

/// A saved activity: the result and its chart, sources, adopt, export, upload and delete.
struct ActivityDetailView: View {
    @Bindable var model: AppModel
    let sessionID: UUID
    @State private var deleting = false
    @State private var info: TestInfo?
    @Environment(\.dismiss) private var dismiss
    private var session: TestSession? { model.history.first { $0.id == sessionID } }

    var body: some View {
        Group {
            if let session {
                List {
                    if session.isDemo { Label("Debug · mock sensor data", systemImage: "ladybug").foregroundStyle(Theme.warning) }
                    headline(session)
                    Section { RideCharts(session: session) }
                    if !session.samples.isEmpty { RideSummaryCard(session: session).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                    if session.training == nil { Section { CalculationNote(result: session.result) { info = .estimate } } }
                    adoption(session)
                    sources(session)
                    Section("Export") { ActivityExportControls(model: model, session: session) }
                    upload(session)
                }
                .buttonStyle(FTPunkRowButtonStyle())
                .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Delete…", role: .destructive) { deleting = true }
                                .disabled(model.isActive && model.engine?.session.id == session.id)
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("Activity options").accessibilityIdentifier("detail-menu")
                    }
                }
                .confirmationDialog("Delete this local activity?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete activity", role: .destructive) { model.delete(session); dismiss() }
                } message: { Text("The recording and pending upload are removed. Already uploaded activities and adopted FTP settings are kept.") }
            } else {
                ContentUnavailableView("Activity deleted", systemImage: "trash")
            }
        }.sheet(item: $info) { ProtocolInfoView(topic: $0) }
    }

    @ViewBuilder private func headline(_ session: TestSession) -> some View {
        if let result = session.result, session.training == nil {
            FTPResultCard(result: result, currentFTP: nil, showDelta: false).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        } else if session.outcome == .interrupted {
            let summary = InterruptionSummary.make(session)
            Section {
                Label(summary.headline, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(Theme.warning)
                Text(summary.reason)
                Text(summary.saved).font(.callout).foregroundStyle(Theme.secondary)
            }
        } else if session.training != nil {
            Section {
                LabeledContent("Time", value: DurationFormat.clock(session.endedAtOffset ?? 0))
            }
        } else {
            Section { Text("No FTP estimate. A valid, continuous 60-second ramp window is required.").foregroundStyle(Theme.secondary) }
        }
    }

    @ViewBuilder private func adoption(_ session: TestSession) -> some View {
        if let result = session.result, session.training == nil, !session.isDemo {
            let rider = model.riders.first { $0.id == session.riderID }
            Section {
                if FTPAdoption.isAdopted(rider: rider, result: result, sessionStart: session.startedAt) {
                    Label("\(model.name(for: session.riderID))’s FTP was set from this test", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                } else {
                    Button("Use \(Int(result.estimatedFTP.rounded())) W as \(model.name(for: session.riderID))’s FTP") { model.adopt(session) }
                        .disabled(model.isBusy).accessibilityIdentifier("detail-adopt")
                }
            }
        }
    }

    private func sources(_ session: TestSession) -> some View {
        Section("This activity") {
            LabeledContent("Rider at time of ride", value: session.riderName)
            LabeledContent("Activity", value: session.activityTitle)
            LabeledContent("Power source", value: session.configuration.resolvedPowerSource.title)
            LabeledContent("Cadence source", value: session.configuration.resolvedCadenceSource.title)
            LabeledContent("FTP at the time", value: session.configuration.priorFTP.map { "\(Int($0.watts.rounded())) W" } ?? "Not provided")
            LabeledContent("Session weight", value: session.configuration.weightKG.map { "\($0) kg" } ?? "Not provided")
            if let resistance = session.training?.resistance {
                LabeledContent("Initial resistance level", value: String(format: "%.1f", Double(resistance) / 10))
            } else if let plan = session.training {
                ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
                    LabeledContent(step.name, value: "\(Int(step.seconds)) s · \(step.watts)" + (step.endWatts.map { " → \($0)" } ?? "") + " W")
                }
            } else {
                LabeledContent("Warm-up", value: "\(session.configuration.warmupPower) W")
                LabeledContent("Estimate factor", value: "\(Int((session.configuration.ftpFactor * 100).rounded())) %")
            }
            LabeledContent("Outcome", value: session.outcome?.title ?? "Recording")
            if let reason = session.endReason { Text(reason).foregroundStyle(Theme.warning) }
        }
    }

    @ViewBuilder private func upload(_ session: TestSession) -> some View {
        if !session.isDemo && session.endedAtOffset != nil {
            Section("Intervals.icu") {
                if let job = model.jobs.first(where: { $0.sessionID == session.id }) {
                    Text("Upload: \(job.status.rawValue)")
                    if let error = job.lastError { Text(error).font(.caption).foregroundStyle(Theme.secondary) }
                    if job.status == .needsAttention || job.status == .queued {
                        Button("Retry upload") { Task { await model.flushUploads(manual: true) } }
                    }
                } else {
                    Button("Upload activity…") { model.requestUpload(session) }.disabled(model.connections[session.riderID] == nil)
                }
            }
        }
    }
}
