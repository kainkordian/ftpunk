import SwiftUI
import FTPunkDomain

/// Today's planned workouts from Intervals.icu, or the next one, or a single quiet hint.
struct TodaySection: View {
    @Bindable var model: AppModel
    let open: (WorkoutRef) -> Void

    private var selection: TodayWorkouts.Selection {
        TodayWorkouts.select(model.workoutLibrary, riderID: model.profile.id, today: ScheduledDate.string(for: Date()), connected: model.connection != nil)
    }

    var body: some View {
        switch selection {
        case .today(let ids):
            VStack(alignment: .leading, spacing: Space.s) {
                heading("Today · from Intervals.icu")
                ForEach(ids, id: \.self) { id in
                    if let workout = model.workoutLibrary.first(where: { $0.id == id }) { TodayCard(model: model, workout: workout, open: open) }
                }
            }
        case .nothingToday(let next):
            VStack(alignment: .leading, spacing: Space.s) {
                heading("Today · from Intervals.icu")
                Text("Nothing planned today").ftpText(.headline)
                if let next, let workout = model.workoutLibrary.first(where: { $0.id == next }) {
                    Text("Next planned").ftpText(.subheadline).foregroundStyle(Theme.secondary)
                    WorkoutCard(title: workout.plan.name, detail: "\(dateText(workout.scheduledDate)) · \(DurationFormat.workout(workout.plan.duration))", plan: workout.plan) { open(.cached(workout.id)) }
                }
                if let message = model.catalog.syncMessage { Text(message).ftpText(.footnote).foregroundStyle(Theme.secondary) }
            }
        case .notConnected:
            if !model.intervalsHintDismissed {
                HStack(alignment: .top, spacing: Space.s) {
                    Button { model.destination = .settings } label: {
                        Label("Connect Intervals.icu in Settings to see planned workouts", systemImage: "calendar.badge.plus")
                            .ftpText(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("connect-hint")
                    Button { model.intervalsHintDismissed = true } label: {
                        Image(systemName: "xmark").ftpText(.footnote, weight: .semibold).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Dismiss").foregroundStyle(Theme.secondary)
                }
            }
        }
    }
    private func heading(_ text: String) -> some View { Text(text.uppercased()).ftpLabel().foregroundStyle(Theme.secondary) }
}

func dateText(_ scheduled: String?) -> String {
    guard let scheduled, let date = ScheduledDate.date(from: scheduled) else { return "Date not set" }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
}

struct TodayCard: View {
    @Bindable var model: AppModel
    let workout: CachedWorkout
    let open: (WorkoutRef) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button { open(.cached(workout.id)) } label: {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(workout.plan.name).ftpText(.title3, weight: .bold).multilineTextAlignment(.leading)
                        Spacer(minLength: Space.s)
                        Text(DurationFormat.workout(workout.plan.duration)).ftpText(.headline).foregroundStyle(Theme.secondary)
                    }
                    WorkoutProfileChart(plan: workout.plan, height: 56)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(workout.plan.name).accessibilityValue("Today, \(DurationFormat.workout(workout.plan.duration))")
                .accessibilityHint("Shows the workout steps")
            Button { model.openPreflight(.workout(.cached(workout.id))) } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(FTPunkPrimaryButtonStyle()).controlSize(.large).disabled(model.isBusy).accessibilityIdentifier("start-today")
        }
        .padding(Space.l).ftpCard(tint: Theme.accent, fill: 0.06)
    }
}

struct NextUpCard: View {
    @Bindable var model: AppModel
    let open: (WorkoutRef) -> Void
    private var selection: TodayWorkouts.Selection {
        TodayWorkouts.select(model.workoutLibrary, riderID: model.profile.id, today: ScheduledDate.string(for: Date()), connected: model.connection != nil)
    }
    private var selected: CachedWorkout? {
        let id: String?
        switch selection { case .today(let ids): id = ids.first; case .nothingToday(let next): id = next; case .notConnected: id = nil }
        return model.workoutLibrary.first { $0.id == id }
    }
    var body: some View {
        if let workout = selected {
            let today = workout.scheduledDate == ScheduledDate.string(for: Date())
            VStack(alignment: .leading, spacing: 14) {
                Text("NEXT UP · \(today ? "TODAY" : dateText(workout.scheduledDate).uppercased()) · FROM INTERVALS.ICU")
                    .ftpText(.caption, weight: .bold).foregroundStyle(Theme.accent)
                Text(workout.plan.name).font(.ftp(34)).lineLimit(2)
                Text("\(DurationFormat.workout(workout.plan.duration)) · \(WorkoutPreview.mainSetText(for: workout.plan) ?? "Cycling workout")" + (today ? "" : " · nothing planned today"))
                    .ftpText(.body).foregroundStyle(Theme.secondary)
                WorkoutProfileChart(plan: workout.plan, height: 92, dashboard: true)
                HStack(spacing: 12) {
                    Button { model.openPreflight(.workout(.cached(workout.id))) } label: { Label(today ? "Start" : "Ride it today", systemImage: "play.fill") }
                        .buttonStyle(FTPunkPrimaryButtonStyle()).controlSize(.large).disabled(model.isBusy).accessibilityIdentifier("start-today")
                    Button("Steps and details") { open(.cached(workout.id)) }.buttonStyle(FTPunkSecondaryButtonStyle())
                }
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).ftpCard(fill: 0)
        } else { TodaySection(model: model, open: open) }
    }
}
