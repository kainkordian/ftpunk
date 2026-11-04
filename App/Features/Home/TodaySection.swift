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
                Text("Nothing planned today").font(.headline)
                if let next, let workout = model.workoutLibrary.first(where: { $0.id == next }) {
                    Text("Next planned").font(.subheadline).foregroundStyle(Theme.secondary)
                    WorkoutCard(title: workout.plan.name, detail: "\(dateText(workout.scheduledDate)) · \(DurationFormat.workout(workout.plan.duration))", plan: workout.plan) { open(.cached(workout.id)) }
                }
                if let message = model.catalog.syncMessage { Text(message).font(.footnote).foregroundStyle(Theme.secondary) }
            }
        case .notConnected:
            if !model.intervalsHintDismissed {
                HStack(alignment: .top, spacing: Space.s) {
                    Button { model.destination = .settings } label: {
                        Label("Connect Intervals.icu in Settings to see planned workouts", systemImage: "calendar.badge.plus")
                            .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("connect-hint")
                    Button { model.intervalsHintDismissed = true } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
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
                        Text(workout.plan.name).font(.title3.bold()).multilineTextAlignment(.leading)
                        Spacer(minLength: Space.s)
                        Text(DurationFormat.workout(workout.plan.duration)).font(.headline).foregroundStyle(Theme.secondary)
                    }
                    WorkoutProfileChart(plan: workout.plan, height: 56)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(workout.plan.name).accessibilityValue("Today, \(DurationFormat.workout(workout.plan.duration))")
                .accessibilityHint("Shows the workout steps")
            Button { model.openPreflight(.workout(.cached(workout.id))) } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(FTPunkPrimaryButtonStyle()).disabled(model.isBusy).accessibilityIdentifier("start-today")
        }
        .padding(Space.l).ftpCard(tint: Theme.accent, fill: 0.06)
    }
}
