import SwiftUI
import FTPunkDomain

/// Trainer, power and heart-rate status. Shape and colour both carry state.
struct DevicesPill: View {
    let summary: DeviceSummary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                light(summary.trainer, "bicycle")
                light(summary.power, "bolt.fill")
                light(summary.heartRate, "heart.fill")
                Text("Devices").font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, Space.m).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Devices")
        .accessibilityValue(summary.description)
        .accessibilityHint("Connect or manage your trainer, power meter and heart-rate sensor")
        .accessibilityIdentifier("devices-pill")
    }
    private func light(_ state: DeviceLight, _ symbol: String) -> some View {
        Image(systemName: state == .attention ? "exclamationmark.triangle.fill" : symbol)
            .font(.caption).symbolVariant(state == .off ? .none : .fill)
            .foregroundStyle(state == .ready ? Theme.accent : state == .attention ? Theme.warning : Theme.secondary)
            .opacity(state == .off ? 0.55 : 1)
    }
}
