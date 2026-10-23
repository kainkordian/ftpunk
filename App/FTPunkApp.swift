import SwiftUI
import FTPunkStorage

@main struct FTPunkApp: App {
    @ViewState private var model: AppModel? = nil
    private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    init() {
        let preview = ProcessInfo.processInfo.arguments.contains("--debug-preview")
        do {
            let store = try LocalStore(inMemory: preview)
            if preview && ProcessInfo.processInfo.arguments.contains("--preview-walkthrough") { try PreviewFixtures.seed(store) }
            _model = ViewState(initialValue: try AppModel(store: store, preview: preview))
        }
        catch { startupError = error.localizedDescription }
    }
    var body: some Scene {
        WindowGroup {
            if let model {
                ContentView(model: model)
                    #if os(macOS)
                    .frame(minWidth: 520, minHeight: 600)
                    #endif
                    .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme)
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
        #if os(macOS)
        .defaultSize(width: 900, height: 820)
        #endif
    }
}
