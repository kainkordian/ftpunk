import SwiftUI
import Charts
import FTPunkDomain

struct HistoryView: View {
    @Bindable var model: AppModel
    @ViewState private var selectedRider: UUID? = nil
    @ViewState private var metric = "FTP, W"
    @ViewState private var includeDebug = ProcessInfo.processInfo.arguments.contains("--preview-walkthrough")
    @ViewState private var pendingDelete: TestSession? = nil
    private var groups: [RiderHistoryGroup] {
        RiderHistory.groups(sessions: model.history, profiles: model.riders)
            .filter { selectedRider == nil || $0.id == selectedRider }
    }
    private var chartSessions: [TestSession] {
        groups.flatMap(\.sessions).filter { value($0) != nil && (includeDebug || !$0.isDemo) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Rider", selection: $selectedRider) {
                        Text("All riders").tag(UUID?.none)
                        ForEach(model.riders) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("Progress over time") {
                    Picker("Metric", selection: $metric) {
                        Text("FTP, W").tag("FTP, W")
                        Text("FTP, W/kg").tag("FTP, W/kg")
                    }.pickerStyle(.segmented)
                    Toggle("Include debug results in chart", isOn: $includeDebug)
                    if chartSessions.isEmpty {
                        Text("\(metric == "FTP, W/kg" ? "Tests with an FTP result and a saved rider weight" : "Tests with an FTP result") will appear here. Debug results are hidden unless included above.")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical)
                    } else {
                        trendChart
                        Text("Each point is one test. Compare matching protocols and factors. Diamonds mark synthetic debug results.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.history.isEmpty {
                    ContentUnavailableView("Your first test starts here", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Saved tests are grouped by rider, with FTP and W/kg trends."))
                }
                ForEach(groups) { group in
                    Section("\(group.name) · \(group.sessions.count) \(group.sessions.count == 1 ? "test" : "tests")") {
                        ForEach(group.sessions) { session in
                            HStack {
                                NavigationLink { SessionDetail(model: model, sessionID: session.id) } label: {
                                    HistoryRow(session: session, status: model.jobs.first(where: { $0.sessionID == session.id })?.status)
                                }
                                Button(role: .destructive) { pendingDelete = session } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).foregroundStyle(.red).frame(minWidth: 36, minHeight: 44)
                                    .accessibilityLabel("Delete test from \(session.startedAt.formatted())")
                                    .disabled(model.isActive && model.engine?.session.id == session.id)
                            }
                            .swipeActions { Button("Delete", role: .destructive) { pendingDelete = session } }
                            .contextMenu { Button("Delete test…", role: .destructive) { pendingDelete = session } }
                        }
                    }
                }
            }.navigationTitle("Progress")
                .alert("Delete this test?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { session in
                    Button("Delete", role: .destructive) { model.delete(session); pendingDelete = nil }
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                } message: { session in
                    Text("Delete \(session.riderName)’s local recording and its pending upload. Any activity already sent to Intervals.icu remains there. Adopted FTP settings are kept.")
                }
        }
    }
    private var trendChart: some View {
        Chart {
            ForEach(groups) { group in
                ForEach(group.sessions.sorted { $0.startedAt < $1.startedAt }) { session in
                    if let amount = value(session), includeDebug || !session.isDemo {
                        LineMark(x: .value("Date", session.startedAt), y: .value(metric, amount),
                                 series: .value("Rider and data", "\(group.id)-\(session.isDemo)"))
                            .foregroundStyle(by: .value("Rider", group.name))
                        PointMark(x: .value("Date", session.startedAt), y: .value(metric, amount))
                            .foregroundStyle(by: .value("Rider", group.name))
                            .symbol(session.isDemo ? .diamond : .circle)
                            .accessibilityLabel("\(group.name), \(session.startedAt.formatted(date: .abbreviated, time: .omitted)), \(amount.formatted()) \(metric)")
                    }
                }
            }
        }.chartYAxisLabel(metric).frame(height: 210).padding(.vertical, 8)
    }
    private func value(_ session: TestSession) -> Double? {
        metric == "FTP, W/kg" ? session.result?.wattsPerKG : session.result?.estimatedFTP
    }
}

private struct HistoryRow: View {
    let session: TestSession
    let status: UploadStatus?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.isDemo ? "Debug test" : session.outcome?.title ?? "Recording").font(.headline)
                Spacer()
                if let result = session.result { Text("\(Int(result.estimatedFTP.rounded())) W").bold().foregroundStyle(Theme.accent) }
            }
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
            Text("\(session.configuration.preset.title) · \(Int(session.configuration.ftpFactor * 100))% estimate")
                .font(.caption).foregroundStyle(.secondary)
            if let status { Text("Intervals.icu · \(status.rawValue)").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}

struct SessionDetail: View {
    @Bindable var model: AppModel
    let sessionID: UUID
    @ViewState private var exportURL: URL? = nil
    @ViewState private var deleting = false
    @ViewState private var info: TestInfo? = nil
    @Environment(\.dismiss) private var dismiss
    private var session: TestSession? { model.history.first { $0.id == sessionID } }
    var body: some View {
        Group {
            if let session {
                List {
                    if session.isDemo { Label("Debug · mock sensor data", systemImage: "ladybug").foregroundStyle(.orange) }
                    if let result = session.result {
                        ResultCard(result: result)
                        Button { info = .estimate } label: { Label("Why 72–77%?", systemImage: "info.circle") }
                        if !session.isDemo { Button("Use this FTP for \(model.name(for: session.riderID))") { model.adopt(session) } }
                    } else { Text("No valid FTP estimate. A continuous 60-second ramp window is required.") }
                    Section("This test") {
                        LabeledContent("Rider at time of test", value: session.riderName)
                        LabeledContent("Protocol", value: session.configuration.preset.title)
                        LabeledContent("Existing FTP", value: session.configuration.priorFTP.map { "\(Int($0.watts.rounded())) W" } ?? "Not provided")
                        LabeledContent("Session weight", value: session.configuration.weightKG.map { "\($0) kg" } ?? "Not provided")
                        LabeledContent("Warm-up", value: "\(session.configuration.warmupPower) W")
                        LabeledContent("Outcome", value: session.outcome?.title ?? "Recording")
                        if let reason = session.endReason { Text(reason).foregroundStyle(.orange) }
                        PowerChart(session: session)
                    }
                    Section("Export") {
                        ForEach(["tcx", "csv", "json"], id: \.self) { kind in
                            Button("Prepare \(kind.uppercased()) file") { exportURL = model.export(session, kind: kind) }
                        }
                        if let exportURL { ShareLink("Share \(exportURL.pathExtension.uppercased())", item: exportURL) }
                    }
                    if !session.isDemo && session.endedAtOffset != nil {
                        Section("Intervals.icu") {
                            if let job = model.jobs.first(where: { $0.sessionID == session.id }) {
                                Text("Upload: \(job.status.rawValue)")
                                if let error = job.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
                                if job.status == .needsAttention || job.status == .queued {
                                    Button("Retry upload") { Task { await model.flushUploads(manual: true) } }
                                }
                            } else {
                                Button("Upload activity…") { model.requestUpload(session) }.disabled(model.connection == nil)
                            }
                        }
                    }
                    Section {
                        Button("Delete test…", role: .destructive) { deleting = true }
                            .disabled(model.isActive && model.engine?.session.id == session.id)
                    }
                }
                .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
                .confirmationDialog("Delete this local test?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete test", role: .destructive) { model.delete(session); dismiss() }
                } message: { Text("The recording and pending upload are removed. Already uploaded activities and adopted FTP settings are kept.") }
            } else {
                ContentUnavailableView("Test deleted", systemImage: "trash")
            }
        }.sheet(item: $info) { ProtocolInfoView(topic: $0) }
    }
}
