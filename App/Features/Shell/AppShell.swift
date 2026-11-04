import SwiftUI
import FTPunkDomain

/// Platform shells: tabs on iPhone, a sidebar on Mac. Preview scenarios can force the phone layout.
struct AppShell: View {
    @Bindable var model: AppModel
    var body: some View {
        #if os(macOS)
        if model.previewPhoneLayout { TabShell(model: model) } else { SidebarShell(model: model) }
        #else
        TabShell(model: model)
        #endif
    }
}

private struct DestinationContent: View {
    @Bindable var model: AppModel
    let destination: AppDestination
    var body: some View {
        switch destination {
        case .home: HomeView(model: model)
        case .progress: ProgressTabView(model: model)
        case .settings: SettingsView(model: model)
        }
    }
}

struct TabShell: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView(selection: $model.destination) {
            ForEach(AppDestination.allCases) { destination in
                DestinationContent(model: model, destination: destination)
                    .liveRideBar(model)
                    .tabItem { Label(destination.title, systemImage: destination.symbol) }
                    .tag(destination)
            }
        }
    }
}

#if os(macOS)
struct SidebarShell: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(model.destination) }, set: { if let value = $0 { model.destination = value } })) {
                ForEach(AppDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol).tag(destination)
                        .frame(minHeight: 32)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 240)
        } detail: {
            DestinationContent(model: model, destination: model.destination).liveRideBar(model)
        }
    }
}
#endif

/// Shown above the tabs, only while a ride is active: phase, live power, time and one-tap Return.
struct LiveRideBar: ViewModifier {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isActive, let engine = model.engine {
                let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s)) : AnyLayout(HStackLayout(spacing: Space.m))
                layout {
                    Text(summary(engine)).font(.headline).monospacedDigit().lineLimit(2)
                        .accessibilityLabel(accessibilitySummary(engine))
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Button("Return") { model.cockpitPresented = true }
                        .buttonStyle(FTPunkPrimaryButtonStyle()).accessibilityIdentifier("return-to-ride")
                    Button("Stop & save", role: .destructive, action: model.stop)
                        .buttonStyle(FTPunkSecondaryButtonStyle()).accessibilityIdentifier("live-bar-stop")
                }
                .padding(.horizontal, Space.l).padding(.vertical, Space.s).frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
    }
    private func watts(_ engine: RampEngine) -> String {
        let live = engine.lastPower.flatMap { model.elapsed - $0.time <= 2 ? Int($0.watts.rounded()) : nil }
        return (live ?? engine.targetPower).map { "\($0) W" } ?? "— W"
    }
    private func summary(_ engine: RampEngine) -> String { "\(engine.phase.title) · \(watts(engine)) · \(clockText(model.elapsed))" }
    private func accessibilitySummary(_ engine: RampEngine) -> String { "Live ride. \(engine.phase.title), \(watts(engine)), elapsed \(clockText(model.elapsed))" }
}

extension View {
    func liveRideBar(_ model: AppModel) -> some View { modifier(LiveRideBar(model: model)) }
}

func clockText(_ value: Double) -> String { "\(Int(value) / 60):\(String(format: "%02d", Int(value) % 60))" }

/// Full-screen ride: the cockpit while riding, the result afterwards.
struct CockpitContainer: View {
    @Bindable var model: AppModel
    var body: some View { RideView(model: model) }
}
