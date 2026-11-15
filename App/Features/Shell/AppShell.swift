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
    @State private var showRiders = false
    @State private var showDevices = false
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FTPunk").font(.ftp(26)).foregroundStyle(Theme.accent).padding(.leading, 14).padding(.bottom, 20)
                ForEach(AppDestination.allCases) { destination in
                    Button { model.destination = destination } label: {
                        Label(destination.title, systemImage: destination.symbol).ftpText(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
                            .foregroundStyle(model.destination == destination ? Theme.text : Theme.secondary)
                            .background(model.destination == destination ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
                    }.buttonStyle(.plain).accessibilityAddTraits(model.destination == destination ? .isSelected : [])
                }
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEVICES").ftpText(.caption, weight: .bold).foregroundStyle(Theme.secondary)
                    device("Trainer", light: model.deviceSummary.trainer, required: true)
                    device("Power meter", light: model.deviceSummary.power)
                    device("Heart rate", light: model.deviceSummary.heartRate)
                    if model.demoMode { StatusPill(text: "Mock sensors", symbol: "ladybug", tone: .warning) }
                    Button("Connect") { showDevices = true }.buttonStyle(FTPunkPrimaryButtonStyle()).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("devices-pill")
                }.padding(14).ftpCard(fill: 0)
                Button { showRiders = true } label: {
                    HStack(spacing: 12) {
                        Text(RiderInitials.make(model.profile.name)).font(.ftp(14)).foregroundStyle(Theme.ground)
                            .frame(width: 32, height: 32).background(Theme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.profile.name).ftpText(.headline, weight: .bold)
                            Text("Switch rider").ftpText(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(14).frame(maxWidth: .infinity, minHeight: 56).background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                }.buttonStyle(.plain).accessibilityLabel("Rider: \(model.profile.name). Switch rider").accessibilityIdentifier("rider-chip")
            }.padding(.horizontal, 16).padding(.vertical, 24).frame(width: 236).background(Theme.surface.opacity(0.5))
            DestinationContent(model: model, destination: model.destination).liveRideBar(model).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Theme.ground.ignoresSafeArea())
            .sheet(isPresented: $showDevices) { DevicesSheet(model: model) }
            .sheet(isPresented: $showRiders) { RiderSheet(model: model) }
    }
    private func device(_ title: String, light: DeviceLight, required: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: light == .attention ? "exclamationmark.triangle.fill" : "circle.fill")
                .font(.ftp(10)).foregroundStyle(light == .ready ? Theme.accent : required ? Theme.warning : Theme.secondary)
            Text(title).ftpText(.footnote, weight: .semibold)
            Spacer(minLength: 0)
            Text(light == .ready ? "Ready" : required ? "Offline" : "Optional").ftpText(.footnote).foregroundStyle(light == .ready ? Theme.accent : required ? Theme.warning : Theme.secondary)
        }.frame(minHeight: 30).accessibilityElement(children: .combine)
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
                    Text(summary(engine)).ftpText(.headline).monospacedDigit().lineLimit(2)
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
