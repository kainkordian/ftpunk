import SwiftUI
import FTPunkDomain

private let cardColumns = [GridItem(.adaptive(minimum: 210), spacing: Space.m, alignment: .top)]

/// The classic library, grouped by type with category chips.
struct WorkoutLibrarySection: View {
    @Bindable var model: AppModel
    @Binding var category: WorkoutCategory?
    @Binding var importing: Bool
    @State private var mineOnly = false
    @State private var showAll = false
    @State private var gridWidth = 0.0
    private var columns: [GridItem] {
        // Keep the six featured cards in complete rows on wide Home windows.
        if !mineOnly && category == nil && !showAll && gridWidth >= 654 {
            return Array(repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top), count: 3)
        }
        return cardColumns
    }
    let open: (WorkoutRef) -> Void

    private var definitions: [WorkoutDefinition] {
        if let category { return WorkoutLibrary.definitions(in: category) }
        let featured = ["easy-spin", "endurance-60", "tempo-3x10", "sweet-spot-2x20", "over-unders-3x9", "threshold-2x20"]
        return featured.compactMap(WorkoutLibrary.definition(id:)) + WorkoutLibrary.catalog.filter { !featured.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Workouts").ftpText(.title2, weight: .bold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("New workout") { model.newWorkout() }.accessibilityIdentifier("new-workout")
                Menu("Import…") {
                    Button("Import file…") { importing = true }.accessibilityIdentifier("add-workout")
                    Button("Paste as text") { model.newWorkout(text: Clipboard.text() ?? "") }.accessibilityIdentifier("paste-workout")
                    Button("Example JSON") { model.importWorkout(Data(WorkoutImport.exampleJSON.utf8)) }
                }.menuStyle(.button).buttonStyle(FTPunkSecondaryButtonStyle()).menuIndicator(.hidden)
            }.buttonStyle(FTPunkSecondaryButtonStyle()).disabled(model.isBusy)
            if model.libraryFTP == nil {
                Label("Needs FTP: take an FTP test or set your FTP to see targets.", systemImage: "info.circle")
                    .ftpText(.footnote).foregroundStyle(Theme.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    FilterChip(title: "All", selected: category == nil && !mineOnly) { category = nil; mineOnly = false }
                    ForEach(WorkoutCategory.allCases) { item in FilterChip(title: item.title, selected: category == item && !mineOnly) { category = item; mineOnly = false } }
                    FilterChip(title: "Mine", selected: mineOnly) { mineOnly = true }.id(HomeSection.mine)
                }.padding(.vertical, Space.xs)
            }
            LazyVGrid(columns: columns, spacing: Space.m) {
                if mineOnly {
                    ForEach(model.myCustomWorkouts) { workout in
                        WorkoutCard(title: workout.name, detail: DurationFormat.workout(workout.duration), plan: try? workout.plan(ftp: model.libraryFTP ?? 100)) { open(.custom(workout.id)) }
                    }
                    ForEach(TodayWorkouts.mine(model.workoutLibrary, riderID: model.profile.id)) { workout in
                        WorkoutCard(title: workout.plan.name, detail: DurationFormat.workout(workout.plan.duration), plan: workout.plan) { open(.cached(workout.id)) }
                    }
                } else { ForEach(Array(definitions.prefix(showAll || category != nil ? definitions.count : 6))) { definition in
                    if let detail = model.workoutDetail(for: .classic(definition.id)) {
                        WorkoutCard(title: detail.title, detail: caption(detail), plan: detail.previewPlan,
                                    badge: detail.needsFTP ? "Needs FTP" : nil) { open(.classic(definition.id)) }
                    }
                } }
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: FeaturedGridWidth.self, value: geometry.size.width)
            })
            .onPreferenceChange(FeaturedGridWidth.self) { gridWidth = $0 }
            if !mineOnly && category == nil && !showAll {
                Button("Show all \(definitions.count) workouts") { showAll = true }.buttonStyle(.plain).foregroundStyle(Theme.accent).ftpText(.callout, weight: .bold)
            }
        }
        .onChange(of: model.homeFocus) { _, value in if value == .mine { mineOnly = true } }
        .onChange(of: model.myCustomWorkouts.count) { _, _ in mineOnly = true }
        .onChange(of: model.workoutImportReport) { _, value in if value?.hasPrefix("Saved") == true { mineOnly = true } }
    }
    private func caption(_ detail: AppModel.WorkoutDetail) -> String {
        var parts = [DurationFormat.workout(detail.duration)]
        if let plan = detail.plan, let watts = IntensityLabel.mainSetWatts(for: plan) { parts.append("\(watts) W") }
        return parts.joined(separator: " · ")
    }
}

struct UpcomingSection: View {
    @Bindable var model: AppModel
    let open: (WorkoutRef) -> Void
    var body: some View {
        let selection = TodayWorkouts.select(model.workoutLibrary, riderID: model.profile.id, today: ScheduledDate.string(for: Date()), connected: model.connection != nil)
        let featured: String? = { if case .nothingToday(let next) = selection { return next }; return nil }()
        let upcoming = TodayWorkouts.upcoming(model.workoutLibrary, riderID: model.profile.id, today: ScheduledDate.string(for: Date())).filter { $0.id != featured }
        if model.connection != nil || !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("Coming up · 14 days").ftpText(.title3, weight: .bold).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if model.connection != nil {
                        Button { Task { await model.downloadWorkouts() } } label: {
                            Label(model.downloadingWorkouts ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                        }.buttonStyle(FTPunkSecondaryButtonStyle()).disabled(model.isBusy || model.downloadingWorkouts).frame(minHeight: 44)
                    }
                }
                if upcoming.isEmpty {
                    Text("Nothing else planned.").ftpText(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(upcoming) { workout in
                            Button { open(.cached(workout.id)) } label: {
                                HStack(spacing: 12) {
                                    Text(dateText(workout.scheduledDate)).frame(width: 84, alignment: .leading).foregroundStyle(Theme.secondary)
                                    Text(workout.plan.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                                    Text(DurationFormat.workout(workout.plan.duration)).foregroundStyle(Theme.secondary)
                                }.ftpText(.callout).frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let report = model.workoutImportReport, model.connection != nil { Text(report).ftpText(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled) }
                if let message = model.catalog.syncMessage { Text(message).ftpText(.footnote).foregroundStyle(Theme.secondary) }
            }.padding(22).ftpCard(fill: 0)
        }
    }
}

struct MyWorkoutsSection: View {
    @Bindable var model: AppModel
    @Binding var importing: Bool
    let open: (WorkoutRef) -> Void
    @State private var exampleURL: URL?

    var body: some View {
        let mine = TodayWorkouts.mine(model.workoutLibrary, riderID: model.profile.id)
        let built = model.myCustomWorkouts
        VStack(alignment: .leading, spacing: Space.s) {
            Text("My workouts").ftpText(.title3, weight: .bold).accessibilityAddTraits(.isHeader)
            // Three visible actions instead of a "+" menu: on macOS that menu drew as a stretched pop-up button, and its
            // choices were hidden. The row stacks at accessibility text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) { actions }
                VStack(spacing: Space.s) { actions }
            }
            .buttonStyle(FTPunkTertiaryButtonStyle()).disabled(model.isBusy)
            if mine.isEmpty && built.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Build a workout with blocks or as text, paste one from Intervals.icu, or import a Zwift .zwo, an Intervals.icu workout event or an FTPunk JSON file. ZWO powers need your FTP.")
                        .ftpText(.footnote).foregroundStyle(Theme.secondary)
                    if let exampleURL {
                        ShareLink("Save or share the example JSON", item: exampleURL).ftpText(.footnote)
                    } else {
                        Button("Get an example JSON file") { prepareExample() }.buttonStyle(.borderless).ftpText(.footnote)
                    }
                }
            } else {
                LazyVGrid(columns: cardColumns, spacing: Space.m) {
                    ForEach(built) { workout in
                        let needsFTP = workout.needsFTP && model.libraryFTP == nil
                        WorkoutCard(title: workout.name, detail: "\(DurationFormat.workout(workout.duration)) · \(workout.needsFTP ? "% FTP" : "watts")",
                                    plan: try? workout.plan(ftp: model.libraryFTP ?? 100), badge: needsFTP ? "Needs FTP" : nil) { open(.custom(workout.id)) }
                    }
                    ForEach(mine) { workout in
                        WorkoutCard(title: workout.plan.name, detail: "\(DurationFormat.workout(workout.plan.duration)) · imported", plan: workout.plan) { open(.cached(workout.id)) }
                    }
                }
            }
            if let report = model.workoutImportReport, model.connection == nil { Text(report).ftpText(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled) }
        }
    }

    @ViewBuilder private var actions: some View {
        Button { model.newWorkout() } label: { Label("New workout", systemImage: "plus") }
            .accessibilityIdentifier("new-workout")
        Button { model.newWorkout(text: Clipboard.text() ?? "") } label: { Label("Paste as text", systemImage: "doc.on.clipboard") }
            .accessibilityHint("Opens the text editor with the workout text from the clipboard")
            .accessibilityIdentifier("paste-workout")
        Button { importing = true } label: { Label("Import file…", systemImage: "square.and.arrow.down") }
            .accessibilityHint("JSON, Intervals.icu event or Zwift .zwo")
            .accessibilityIdentifier("add-workout")
    }

    private func prepareExample() {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FTPunk-workout-example.json")
            try Data(WorkoutImport.exampleJSON.utf8).write(to: url, options: .atomic); exampleURL = url
        } catch { model.errorMessage = error.localizedDescription }
    }
}

private struct FeaturedGridWidth: PreferenceKey {
    static let defaultValue = 0.0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}
