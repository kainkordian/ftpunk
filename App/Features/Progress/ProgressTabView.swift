import SwiftUI
import FTPunkDomain

/// Which rider's results to show. "Current" follows the rider chip on Home.
enum RiderScope: Hashable {
    case current, all, rider(UUID)
}

/// FTP trend first, then the activity list. Delete lives in swipe, the context menu and the detail menu.
struct ProgressTabView: View {
    @Bindable var model: AppModel
    @State private var scope = RiderScope.current
    @State private var metric = TrendMetric.watts
    @State private var filter = ActivityFilter.all
    @State private var includeDebug = false
    @State private var pendingDelete: TestSession?

    private var riderID: UUID? {
        switch scope { case .current: model.profile.id; case .all: nil; case .rider(let id): id }
    }
    private var scopeTitle: String {
        switch scope {
        case .current: model.profile.name
        case .all: "All riders"
        case .rider(let id): model.name(for: id)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                trendSection
                filterSection
                activitySection
            }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Rider", selection: $scope) {
                            Text("Current rider · \(model.profile.name)").tag(RiderScope.current)
                            Text("All riders").tag(RiderScope.all)
                            ForEach(model.riders.filter { $0.id != model.profile.id }) { Text($0.name).tag(RiderScope.rider($0.id)) }
                        }
                        Toggle("Show debug results in the trend", isOn: $includeDebug)
                    } label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                        .accessibilityLabel("Filter progress").accessibilityValue(scopeTitle + (includeDebug ? ", debug results shown" : ""))
                        .accessibilityIdentifier("progress-filter")
                }
            }
            .navigationDestination(for: UUID.self) { ActivityDetailView(model: model, sessionID: $0) }
            .alert("Delete this activity?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { session in
                Button("Delete", role: .destructive) { model.delete(session); pendingDelete = nil }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { session in
                Text("Delete \(session.riderName)’s local recording and its pending upload. Any activity already sent to Intervals.icu remains there. Adopted FTP settings are kept.")
            }
        }
    }

    // MARK: Trend

    private var trendSection: some View {
        Section {
            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).tint(Theme.controlTint)
            let sessions = ProgressRules.trendSessions(model.history, rider: riderID, metric: metric, includeDebug: includeDebug)
            if sessions.isEmpty {
                Text("\(metric == .wattsPerKG ? "FTP tests with a result and a saved rider weight" : "FTP test results") for \(scopeTitle) will appear here. Debug results are hidden unless you turn them on in the filter menu.")
                    .font(.callout).foregroundStyle(Theme.secondary).padding(.vertical, Space.s)
            } else {
                TrendChart(groups: RiderHistory.groups(sessions: sessions, profiles: model.riders), metric: metric, includeDebug: includeDebug,
                           riderOrder: model.riders.map(\.id))
                Text("Each point is one FTP test. Colour identifies the rider; circles are real results and diamonds are debug results. Compare matching protocols and power sources.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        } header: { Text("FTP trend · \(scopeTitle)") }
    }

    // MARK: Activities

    private var filterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(ActivityFilter.allCases) { item in
                        FilterChip(title: item.title, selected: filter == item, identifier: "filter-\(item.rawValue)") { filter = item }
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)).listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var activitySection: some View {
        let sessions = ProgressRules.activities(model.history, rider: riderID, filter: filter)
        if model.history.isEmpty {
            ContentUnavailableView("Your first ride starts on Home", systemImage: "chart.line.uptrend.xyaxis",
                                   description: Text("Finished rides are saved here, with FTP trends for every rider."))
        } else if sessions.isEmpty {
            Section { Text("No \(filter == .all ? "activities" : filter.title.lowercased()) for \(scopeTitle) yet.").foregroundStyle(Theme.secondary) }
        } else {
            Section("Activities") {
                ForEach(sessions) { session in
                    NavigationLink(value: session.id) {
                        ActivityRow(row: ActivityRowModel.make(session, uploadStatus: model.jobs.first { $0.sessionID == session.id }?.status, showRider: scope == .all))
                    }
                    .swipeActions { Button("Delete", role: .destructive) { pendingDelete = session }.disabled(isLive(session)) }
                    .contextMenu { Button("Delete…", role: .destructive) { pendingDelete = session }.disabled(isLive(session)) }
                    .accessibilityIdentifier("activity-\(session.id.uuidString)")
                }
            }
        }
    }
    private func isLive(_ session: TestSession) -> Bool { model.isActive && model.engine?.session.id == session.id }
}

struct ActivityRow: View {
    let row: ActivityRowModel
    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).font(.headline)
                Text(row.subtitle).font(.subheadline).foregroundStyle(Theme.secondary)
                if !row.badges.isEmpty {
                    HStack(spacing: Space.xs) {
                        ForEach(row.badges, id: \.rawValue) { badge in
                            StatusPill(text: badge.rawValue, symbol: symbol(badge), tone: tone(badge))
                        }
                    }
                }
            }
            Spacer(minLength: Space.s)
            if let value = row.value { Text(value).font(.headline).foregroundStyle(Theme.accent).monospacedDigit() }
        }
        .padding(.vertical, Space.xs).frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
    private func symbol(_ badge: ActivityBadge) -> String {
        switch badge {
        case .debug: "ladybug"
        case .uploaded: "checkmark.icloud"
        case .uploadQueued: "icloud.and.arrow.up"
        case .uploadFailed: "exclamationmark.icloud"
        case .interrupted: "exclamationmark.triangle"
        }
    }
    private func tone(_ badge: ActivityBadge) -> StatusPill.Tone {
        switch badge {
        case .debug, .interrupted, .uploadFailed: .warning
        case .uploaded: .good
        case .uploadQueued: .neutral
        }
    }
}
