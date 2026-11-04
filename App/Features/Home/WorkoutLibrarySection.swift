import SwiftUI
import FTPunkDomain

private let cardColumns = [GridItem(.adaptive(minimum: 170), spacing: Space.m, alignment: .top)]

/// The classic library, grouped by type with category chips.
struct WorkoutLibrarySection: View {
    @Bindable var model: AppModel
    @Binding var category: WorkoutCategory?
    let open: (WorkoutRef) -> Void

    private var definitions: [WorkoutDefinition] { category.map(WorkoutLibrary.definitions(in:)) ?? WorkoutLibrary.catalog }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Workouts").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if model.libraryFTP == nil {
                Label("Needs FTP: take an FTP test or set your FTP to see targets.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    FilterChip(title: "All", selected: category == nil) { category = nil }
                    ForEach(WorkoutCategory.allCases) { item in FilterChip(title: item.title, selected: category == item) { category = item } }
                }.padding(.vertical, Space.xs)
            }
            LazyVGrid(columns: cardColumns, spacing: Space.m) {
                ForEach(definitions) { definition in
                    if let detail = model.workoutDetail(for: .classic(definition.id)) {
                        WorkoutCard(title: detail.title, detail: caption(detail), plan: detail.previewPlan,
                                    badge: detail.needsFTP ? "Needs FTP" : nil) { open(.classic(definition.id)) }
                    }
                }
            }
        }
    }
    private func caption(_ detail: AppModel.WorkoutDetail) -> String {
        var parts = [DurationFormat.workout(detail.duration)]
        if let plan = detail.plan, let watts = IntensityLabel.mainSetWatts(for: plan) { parts.append("main \(watts) W") }
        return parts.joined(separator: " · ")
    }
}

struct UpcomingSection: View {
    @Bindable var model: AppModel
    let open: (WorkoutRef) -> Void
    var body: some View {
        let upcoming = TodayWorkouts.upcoming(model.workoutLibrary, riderID: model.profile.id, today: ScheduledDate.string(for: Date()))
        if model.connection != nil || !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("Upcoming").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if model.connection != nil {
                        Button { Task { await model.downloadWorkouts() } } label: {
                            Label(model.downloadingWorkouts ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                        }.disabled(model.isBusy || model.downloadingWorkouts).frame(minHeight: 44)
                    }
                }
                Text("From Intervals.icu · next 14 days").font(.footnote).foregroundStyle(Theme.secondary)
                if upcoming.isEmpty {
                    Text("Nothing else planned.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    LazyVGrid(columns: cardColumns, spacing: Space.m) {
                        ForEach(upcoming) { workout in
                            WorkoutCard(title: workout.plan.name, detail: "\(dateText(workout.scheduledDate)) · \(DurationFormat.workout(workout.plan.duration))",
                                        plan: workout.plan) { open(.cached(workout.id)) }
                        }
                    }
                }
                if let report = model.workoutImportReport, model.connection != nil { Text(report).font(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled) }
                if let message = model.catalog.syncMessage { Text(message).font(.footnote).foregroundStyle(Theme.secondary) }
            }
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
            Text("My workouts").font(.title3.bold()).accessibilityAddTraits(.isHeader)
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
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    if let exampleURL {
                        ShareLink("Save or share the example JSON", item: exampleURL).font(.footnote)
                    } else {
                        Button("Get an example JSON file") { prepareExample() }.buttonStyle(.borderless).font(.footnote)
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
            if let report = model.workoutImportReport, model.connection == nil { Text(report).font(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled) }
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
