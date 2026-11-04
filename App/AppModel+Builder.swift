import Foundation
import FTPunkDomain
import FTPunkStorage

/// One open workout builder.
struct BuilderRequest: Identifiable {
    let id = UUID()
    var state: BuilderState
    let isNew: Bool
    /// Nil opens in the mode the rider used last.
    var mode: BuilderState.Mode?
}

/// The riders' own workouts: building, saving, deleting and opening the builder.
extension AppModel {
    func customWorkout(id: UUID) -> CustomWorkout? { customWorkouts.first { $0.id == id } }
    /// The selected rider's own workouts.
    var myCustomWorkouts: [CustomWorkout] { customWorkouts.filter { $0.riderID == profile.id } }

    @discardableResult func saveCustomWorkout(_ workout: CustomWorkout) -> Bool {
        do { try store.saveCustomWorkout(workout); try reload(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func deleteCustomWorkout(_ workout: CustomWorkout) {
        guard !isBusy else { return }
        do { try store.deleteCustomWorkout(id: workout.id); try reload() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Opening the builder

    /// A blank workout, or one made from pasted text (opens in Text mode).
    func newWorkout(text: String? = nil) {
        guard !isBusy else { return }
        let blank = CustomWorkout(riderID: profile.id, name: "", blocks: [])
        var state = BuilderState(workout: blank)
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.switchTo(.text); state.setText(text)
            builder = BuilderRequest(state: state, isNew: true, mode: .text)
        } else {
            builder = BuilderRequest(state: state, isNew: true, mode: nil)
        }
    }
    func editWorkout(_ workout: CustomWorkout) {
        guard !isBusy else { return }
        builder = BuilderRequest(state: BuilderState(workout: workout), isNew: false, mode: .blocks)
    }
    /// Whether "Duplicate & edit" makes sense for a workout, and the copy to edit.
    func duplicate(_ ref: WorkoutRef) -> CustomWorkout? {
        let name: (String) -> String = { "Copy of \($0)".prefix(100).description }
        return switch ref {
        case .classic(let id):
            WorkoutLibrary.definition(id: id).flatMap { CustomWorkout(definition: $0, riderID: profile.id, name: name($0.name)) }
        case .cached(let id):
            workoutLibrary.first { $0.id == id }.flatMap { CustomWorkout(plan: $0.plan, riderID: profile.id, name: name($0.plan.name)) }
        case .custom(let id):
            customWorkout(id: id).map { var copy = $0; copy.id = UUID(); copy.riderID = profile.id; copy.name = name($0.name); return copy }
        }
    }
    func duplicateAndEdit(_ ref: WorkoutRef) {
        guard !isBusy, let copy = duplicate(ref) else { return }
        builder = BuilderRequest(state: BuilderState(workout: copy), isNew: true, mode: .blocks)
    }
}
