import SwiftUI
import FTPunkStorage

@main struct FTPunkApp: App {
    @ViewState private var model: AppModel? = nil
    private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let preview = ProcessInfo.processInfo.arguments.contains("--debug-preview")
        do { _model = ViewState(initialValue: try AppModel(store: LocalStore(inMemory: preview), preview: preview)) }
        catch { startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let model {
                ContentView(model: model)
                    .preferredColorScheme(.dark)
                    .task {
                        if ProcessInfo.processInfo.arguments.contains("--autostart-debug"), model.engine == nil {
                            model.demoMode = true
                            await model.start()
                        }
                        #if os(macOS)
                        await PreviewWalkthrough.run(model: model)
                        #endif
                    }
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
