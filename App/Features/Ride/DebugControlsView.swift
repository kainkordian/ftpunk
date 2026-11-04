import SwiftUI
import FTPunkDomain

struct DebugControlsView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Debug controls", systemImage: "ladybug").font(.headline).foregroundStyle(Theme.warning)
            SelectionRow("Signal scenario", selection: $model.mockScenario) {
                ForEach(MockScenario.allCases) { Text($0.title).tag($0) }
            }
            SelectionRow("Playback speed", selection: $model.mockSpeed) {
                ForEach([1.0, 4.0, 12.0, 60.0], id: \.self) { Text("\(Int($0))×").tag($0) }
            }
            Toggle("Set mock numbers manually", isOn: $model.manualMockValues)
            if model.manualMockValues {
                Text("Power: \(Int(model.mockPower)) W")
                Slider(value: $model.mockPower, in: 0...600, step: 5).accessibilityLabel("Mock power watts")
                Text("Cadence: \(Int(model.mockCadence)) rpm")
                Slider(value: $model.mockCadence, in: 0...140, step: 1).accessibilityLabel("Mock cadence rpm")
                Text("Heart rate: \(Int(model.mockHeartRate)) bpm")
                Slider(value: $model.mockHeartRate, in: 60...200, step: 1).accessibilityLabel("Mock heart rate bpm")
            }
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())) {
                Button(model.mockPaused ? "Resume" : "Pause stream") { model.mockPaused.toggle() }
                Button("Advance 60 s") { model.advanceMock(seconds: 60) }
            }.buttonStyle(.bordered).controlSize(.large)
            if model.engine?.phase == .warmup {
                Button("Skip warm-up") { model.skipMockWarmup() }.buttonStyle(.bordered).controlSize(.large)
            }
            Button("Simulate trainer disconnect", role: .destructive) { model.simulateTrainerDisconnect() }
                .buttonStyle(.bordered).controlSize(.large)
            Text("All sensor values are generated locally. No Bluetooth commands or activity uploads are sent.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }.padding().background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }
}
