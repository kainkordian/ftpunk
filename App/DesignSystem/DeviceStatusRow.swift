import SwiftUI
import FTPunkDevices

/// One row per device role, shared by Settings and the Devices sheet.
struct DeviceStatusRow: View {
    let role: DeviceRole
    let connectedName: String?
    /// Extra status after the device name, e.g. "ERG ready".
    var detail: String?
    /// Why the last connection attempt failed; shown instead of the generic hint while the device is not connected.
    var problem: String?
    let action: () -> Void

    private var symbol: String { role == .trainer ? "bicycle" : role == .pedals ? "bolt.circle" : "heart.circle" }
    private var title: String { role == .trainer ? "Smart trainer" : role == .pedals ? "Power meter" : "Heart rate monitor" }
    private var badge: String { role == .trainer ? "Required" : "Optional" }
    private var subtitle: String { Self.subtitle(role: role, connectedName: connectedName, detail: detail, problem: problem) }
    /// The badge already says Required or Optional, so the subtitle only says what the device is for.
    static func subtitle(role: DeviceRole, connectedName: String?, detail: String?, problem: String? = nil) -> String {
        if let connectedName { return detail.map { "\(connectedName) · \($0)" } ?? connectedName }
        if let problem { return problem }
        switch role {
        case .trainer: return "Required to ride · tap to connect"
        case .pedals: return "For power matching, or as the power source"
        case .heartRate: return "Heart rate on screen and in the file"
        }
    }
    private var dot: Color { connectedName != nil ? Theme.accent : role == .trainer ? Theme.warning : Theme.secondary }
    private var statusWord: String { connectedName != nil ? "connected" : role == .trainer ? "required, not connected" : "not connected" }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Space.s) {
                        Text(title).foregroundStyle(.primary)
                        StatusPill(text: badge, tone: role == .trainer && connectedName == nil ? .warning : .neutral)
                    }
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: Space.s)
                Circle().fill(dot).frame(width: 10, height: 10).accessibilityHidden(true)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusWord)
        .accessibilityHint("Choose or manage \(title)")
    }
}
