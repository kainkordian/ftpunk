#if os(macOS)
import SwiftUI
import FTPunkDomain

/// Menu actions use the same model entry points as the cockpit, including while it is minimised.
struct MacAppCommands: Commands {
    let model: AppModel?
    @AppStorage("dashboardShowsMoreReadings") private var showsMoreReadings = false

    private var running: Bool { model?.isActive == true }
    private var training: Bool { model?.engine?.session.training != nil }
    private var transitioning: Bool { model?.trainingTransition != nil }
    private var paused: Bool { model?.engine?.phase == .paused }
    private var workout: Bool { model?.engine?.session.training?.kind == .workout }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model?.destination = .settings }
                .keyboardShortcut(",", modifiers: .command).disabled(model == nil)
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Go") {
            Group {
                Button("Home") { model?.destination = .home }.keyboardShortcut("1", modifiers: .command)
                Button("Progress") { model?.destination = .progress }.keyboardShortcut("2", modifiers: .command)
                Button("Settings") { model?.destination = .settings }.keyboardShortcut("3", modifiers: .command)
            }.disabled(model == nil)
        }
        CommandMenu("Ride") {
            Group {
                Button(paused ? "Resume" : "Pause") { paused ? model?.resumeTraining() : model?.pauseTraining() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!training || transitioning)
                Button("Skip step") { model?.skipStep() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(model?.engine?.canSkipStep != true || transitioning)
                Button("Raise target") { adjustTarget(1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .disabled(!training || transitioning || (workout && (model?.engine?.intensity ?? 100) >= 150))
                Button("Lower target") { adjustTarget(-1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .disabled(!training || transitioning || (workout && (model?.engine?.intensity ?? 100) <= 50))
                Button("Finish ramp") { model?.finishRamp() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(model?.engine?.phase != .ramp)
                Button("Stop & save") { model?.stop() }.keyboardShortcut(".", modifiers: .command)
                // Workout/free-ride cockpits already show all readings. Their toggle arrives in plan 11.
                Button(showsMoreReadings ? "Main readings" : "More readings") { showsMoreReadings.toggle() }
                    .disabled(training)
                Button("Minimise ride") { model?.cockpitPresented = false }
                    .disabled(model?.cockpitPresented != true)
            }.disabled(!running)
        }
    }

    private func adjustTarget(_ direction: Int) {
        guard let model else { return }
        if workout { model.adjustIntensity(by: 5 * direction) }
        else if model.engine?.resumeResistance != nil { model.adjustResistance(by: direction) }
        else { model.adjustERG(by: 10 * direction) }
    }
}
#endif
