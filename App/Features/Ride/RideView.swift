import SwiftUI
import FTPunkDomain

/// Chooses what fills the screen for the current activity: the live cockpit while it runs,
/// the result when it ends.
struct RideView: View {
    @Bindable var model: AppModel
    var body: some View {
        if let engine = model.engine {
            if !engine.phase.isActive { ResultView(model: model, engine: engine) }
            else if engine.session.training == nil { FTPCockpitView(model: model, engine: engine) }
            else { WorkoutCockpitView(model: model, engine: engine) }
        }
    }
}
