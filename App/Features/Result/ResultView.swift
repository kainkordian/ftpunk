import SwiftUI
import FTPunkDomain

struct ResultView: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    var body: some View { RideSummaryView(model: model, session: engine.session, done: { model.closeCockpit() }) }
}
