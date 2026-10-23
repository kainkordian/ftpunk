import SwiftUI
import FTPunkStorage

@main struct FTPunkApp: App {
    @ViewState private var model: AppModel? = nil
    private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do { _model = ViewState(initialValue: try AppModel(store: LocalStore())) }
        catch { startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let model {
                ContentView(model: model)
                    .preferredColorScheme(.dark)
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background && model.isActive { model.interrupt("The app moved to the background.") }
                        if phase == .active { Task { await model.flushUploads() } }
                    }
            } else {
                ContentUnavailableView("Unable to open local history", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "Please restart FTPunk."))
            }
        }
    }
}
