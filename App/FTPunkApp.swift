import SwiftUI
import FTPunkDomain
import FTPunkStorage
#if os(macOS)
import AppKit
#endif

@main struct FTPunkApp: App {
    @ViewState private var model: AppModel? = nil
    private var startupError: String?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    init() {
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif
        let preview = ProcessInfo.processInfo.arguments.contains("--debug-preview")
        do {
            let store = try LocalStore(inMemory: preview)
            _model = ViewState(initialValue: try AppModel(store: store, preview: preview))
        }
        catch { startupError = error.localizedDescription }
    }
    private static func launchValue(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }
    var body: some Scene {
        WindowGroup {
            if let model {
                ContentView(model: model)
                    #if os(macOS)
                    .background {
                        // The cockpit already owns this shortcut. Keep it available after minimising too.
                        if !model.cockpitPresented {
                            Button("") { model.engine?.phase == .paused ? model.resumeTraining() : model.pauseTraining() }
                                .keyboardShortcut("p", modifiers: [.command, .shift])
                                .disabled(!model.isActive || model.engine?.session.training == nil || model.trainingTransition != nil)
                                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
                        }
                    }
                    #endif
                    .modifier(PreviewTextSize(override: model.previewTextSize))
                    #if os(macOS)
                    .frame(minWidth: model.previewPhoneLayout ? 393 : 640, minHeight: 600)
                    #endif
                    .preferredColorScheme((AppearanceMode(rawValue: appearance) ?? .system).scheme)
                    .task {
                        if ProcessInfo.processInfo.arguments.contains("--ride-visual-preview") {
                            model.rideVisualEnabled = true
                            model.mockSpeed = 1
                        }
                        // UI tests slow the mock stream down (`--mock-speed 4`); only an isolated preview honours it.
                        if let speed = Self.launchValue("--mock-speed").flatMap(Double.init), (1...60).contains(speed),
                           ProcessInfo.processInfo.arguments.contains("--debug-preview") {
                            model.mockSpeed = speed
                        }
                        if let scenario = PreviewScenario.requested() {
                            // Seeding runs real ramps on the main actor (over a second for two riders of history).
                            // Let the first frame reach the screen before it starts, so a capture never sees a blank window.
                            try? await Task.sleep(for: .milliseconds(250))
                            do { try await PreviewScenarios.apply(scenario, to: model) }
                            catch { model.errorMessage = "Scenario \(scenario.rawValue) failed: \(error.localizedDescription)" }
                        }
                        if ProcessInfo.processInfo.arguments.contains("--autostart-debug"), model.engine == nil, PreviewScenario.requested() == nil {
                            model.demoMode = true
                            await model.start()
                        }
                        if ProcessInfo.processInfo.arguments.contains("--debug-preview") {
                            if ProcessInfo.processInfo.arguments.contains("--readability-preview") {
                                model.advanceMock(seconds: 85); model.mockPaused = true
                            }
                            if ProcessInfo.processInfo.arguments.contains("--preview-result") {
                                model.advanceMock(seconds: 1000); model.mockPaused = true
                            }
                            if ProcessInfo.processInfo.arguments.contains("--preview-about") {
                                model.hideDebugTools(); model.destination = .settings
                            }
                        }
                        #if os(macOS)
                        await PreviewWalkthrough.run(model: model)
                        #endif
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .background && model.isBusy { model.interrupt("The app moved to the background.") }
                        if phase == .active { Task { await model.flushUploads() } }
                    }
            } else {
                ContentUnavailableView("Unable to open local history", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(startupError ?? "Please restart FTPunk."))
            }
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 820)
        .commands {
            MacAppCommands(model: model)
            CommandGroup(after: .toolbar) {
                // Off, strip, hero. (Command-Shift-P is Pause in the cockpit.)
                Button("Cycle \(RideVisualBranding.name) view") { if let model { model.rideVisualPlacement = model.rideVisualPlacement.next } }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model == nil)
            }
        }
        #endif
    }
}

/// Preview-only text size override, used by the screenshot matrix. Without one it inherits the system size.
struct PreviewTextSize: ViewModifier {
    let override: DynamicTypeSize?
    @Environment(\.dynamicTypeSize) private var inherited
    func body(content: Content) -> some View { content.environment(\.dynamicTypeSize, override ?? inherited) }
}
