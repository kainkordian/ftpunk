import SwiftUI
import UniformTypeIdentifiers
import FTPunkDomain

/// The ride picker: today's workout, the FTP card, quick rides and the workout library.
/// With no FTP, the FTP card moves to the top as the main call to action.
struct HomeView: View {
    @Bindable var model: AppModel
    @State private var showRiders = false
    @State private var showDevices = false
    @State private var detail: WorkoutRef?
    @State private var category: WorkoutCategory?
    @State private var importing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $model.preflightPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    ViewThatFits(in: .horizontal) {
                        if !model.previewPhoneLayout {
                            HStack(alignment: .top, spacing: 24) {
                                VStack(alignment: .leading, spacing: 24) { nextUp; library }.frame(minWidth: 592, maxWidth: .infinity)
                                VStack(spacing: 16) { FTPCard(model: model).id(HomeSection.ftp); quick; UpcomingSection(model: model, open: { detail = $0 }) }.frame(width: 380)
                            }.frame(minWidth: 1036).padding(.horizontal, 32).padding(.vertical, 28)
                        }
                        VStack(alignment: .leading, spacing: 24) {
                            if model.ftpSummary == nil { FTPCard(model: model).id(HomeSection.ftp) }
                            nextUp
                            if model.ftpSummary != nil { FTPCard(model: model).id(HomeSection.ftp) }
                            quick; library
                            UpcomingSection(model: model, open: { detail = $0 }).id(HomeSection.upcoming)
                        }.padding(16)
                    }.frame(maxWidth: 1440).frame(maxWidth: .infinity)
                }
                .onChange(of: model.homeFocus) { _, focus in
                    guard let focus else { return }
                    withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(focus, anchor: .top) }
                    model.homeFocus = nil
                }
                .task(id: model.homeFocus) {
                    if let focus = model.homeFocus {
                        try? await Task.sleep(for: .milliseconds(400))
                        proxy.scrollTo(focus, anchor: .top); model.homeFocus = nil
                    }
                }
            }
            .refreshable { await model.downloadWorkouts() }
            .navigationTitle("Home")
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .navigation) { RiderChip(name: model.profile.name) { showRiders = true } }
                ToolbarItem(placement: .primaryAction) { DevicesPill(summary: model.deviceSummary) { showDevices = true } }
            }
            #else
            .toolbar(model.preflightPath.isEmpty ? .hidden : .visible, for: .windowToolbar)
            #endif
            .navigationDestination(for: RideKind.self) { PreflightView(model: model, kind: $0) }
            .sheet(isPresented: $showRiders) { RiderSheet(model: model) }
            .sheet(isPresented: $showDevices) { DevicesSheet(model: model) }
            .sheet(item: $detail) { WorkoutDetailSheet(model: model, ref: $0) }
            .sheet(item: $model.builder) { BuilderView(model: model, request: $0) }
            // Preview scenarios open the real detail sheet from here; Home clears the request once it is showing.
            .task(id: model.previewWorkoutDetail) {
                guard let ref = model.previewWorkoutDetail else { return }
                try? await Task.sleep(for: .milliseconds(400))
                detail = ref; model.previewWorkoutDetail = nil
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .zwo]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= WorkoutImport.maximumBytes else { throw ArchiveError.invalid("Workout files must be under 2 MB.") }
                    model.importWorkout(try Data(contentsOf: url))
                } catch { model.errorMessage = error.localizedDescription }
            }
            .task { await model.refreshWorkoutsIfNeeded() }
        }
    }
    private var nextUp: some View { NextUpCard(model: model, open: { detail = $0 }).id(HomeSection.today) }
    private var library: some View { WorkoutLibrarySection(model: model, category: $category, importing: $importing, open: { detail = $0 }).id(HomeSection.library) }
    private var quick: some View { QuickRides(model: model).id(HomeSection.quickRides) }

}

struct FTPCard: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let summary = model.ftpSummary {
                Text("YOUR FTP").ftpLabel().foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(Int(summary.watts.rounded())) W").font(.ftp(60)).monospacedDigit().fixedSize(horizontal: false, vertical: true).frame(height: 60)
                    if let wkg = summary.wattsPerKG { Text("\(wkg, specifier: "%.2f") W/kg").ftpText(.title3).foregroundStyle(Theme.secondary) }
                }
                // One line: when it was set and how long ago; after 8 weeks the same line is the retest prompt.
                Label(summary.statusLine.text, systemImage: summary.statusLine.isRetestPrompt ? "arrow.triangle.2.circlepath" : "calendar")
                    .ftpText(.subheadline, weight: summary.statusLine.isRetestPrompt ? .semibold : .regular)
                    .foregroundStyle(summary.statusLine.isRetestPrompt ? Theme.warning : Theme.secondary)
                    .accessibilityIdentifier(summary.statusLine.isRetestPrompt ? "retest-due" : "ftp-age")
                NavigationLink(value: RideKind.ftpTest) { Label("Take the FTP test", systemImage: "waveform.path.ecg") }
                    .buttonStyle(FTPunkSecondaryButtonStyle()).disabled(model.isBusy).accessibilityIdentifier("ftp-test")
            } else {
                Label("No FTP yet", systemImage: "bolt.heart").ftpText(.headline)
                Text("Take an FTP test so workouts fit you.").foregroundStyle(Theme.secondary)
                NavigationLink(value: RideKind.ftpTest) { Label("Take an FTP test", systemImage: "waveform.path.ecg").frame(maxWidth: .infinity) }
                    .buttonStyle(FTPunkPrimaryButtonStyle()).disabled(model.isBusy).accessibilityIdentifier("ftp-test")
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .ftpCard(tint: Theme.accent, fill: 0.08)
        .accessibilityElement(children: .contain)
    }
}

struct QuickRides: View {
    @Bindable var model: AppModel
    private var resistanceReason: String? {
        if model.resistanceLimits != nil { return nil }
        return model.bluetooth.names[.trainer] == nil ? "Connect your trainer first" : "Trainer doesn’t advertise resistance"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Quick ride").ftpText(.title3, weight: .bold).accessibilityAddTraits(.isHeader)
            // The FTP test has its own button on the FTP card, with the retest and no-FTP context.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { tiles }
                VStack(spacing: Space.s) { tiles }
            }
        }.padding(22).ftpCard(fill: 0)
    }
    @ViewBuilder private var tiles: some View {
        tile("Free ERG", "bolt.fill", .freeERG, reason: nil, id: "quick-erg")
        tile("Resistance", "dial.medium", .resistance, reason: resistanceReason, id: "quick-resistance")
    }
    private func tile(_ title: String, _ symbol: String, _ kind: RideKind, reason: String?, id: String) -> some View {
        NavigationLink(value: kind) {
            VStack(spacing: Space.xs) {
                Image(systemName: symbol).ftpText(.title2)
                Text(title).ftpText(.headline)
                if let reason { Text(reason).ftpText(.caption).multilineTextAlignment(.center).foregroundStyle(Theme.secondary) }
            }
            .foregroundStyle(reason == nil ? Color.primary : Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 84).padding(Space.s)
            .ftpCard(fill: 0.05).contentShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain).disabled(model.isBusy || reason != nil)
        .accessibilityIdentifier(id)
        .accessibilityHint(reason ?? "")
    }
}
