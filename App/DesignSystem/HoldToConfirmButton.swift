import SwiftUI
import FTPunkDomain

/// A deliberate, secondary-styled action: press and hold for 1.5 s while a ring fills.
/// VoiceOver gets a custom action, and Mac can pass a keyboard shortcut.
struct HoldToConfirmButton: View {
    let title: String
    var holdingTitle = "Keep holding…"
    var systemImage: String?
    var accessibilityActionName: String
    var shortcut: KeyboardShortcut?
    var identifier = "hold-to-confirm"
    var dashboardScale: Double? = nil
    let action: () -> Void
    @State private var pressStart: Date?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: pressStart == nil)) { clock in
            let held = pressStart.map { clock.date.timeIntervalSince($0) } ?? 0
            let fraction = HoldProgress.fraction(held: held)
            HStack(spacing: Space.s) {
                if dashboardScale == nil { ZStack {
                    Circle().stroke(Theme.secondary.opacity(0.35), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    if let systemImage { Image(systemName: systemImage).font(.footnote) }
                }.frame(width: 26, height: 26) }
                Text(pressStart == nil ? title : holdingTitle).font(dashboardScale.map { .ftp(17 * $0, weight: .bold) } ?? .headline)
            }
            .foregroundStyle(dashboardScale == nil ? Color.primary : Color(red: 1, green: 156/255, blue: 203/255)).multilineTextAlignment(.center)
            .padding(.horizontal, 18 * (dashboardScale ?? 1)).padding(.vertical, dashboardScale == nil ? 12 : 6)
            .frame(maxWidth: .infinity, minHeight: dashboardScale.map { 44 * $0 } ?? 52)
            .background(dashboardScale == nil ? Theme.surface : Color(red: 58/255, green: 28/255, blue: 46/255), in: RoundedRectangle(cornerRadius: dashboardScale.map { 22 * $0 } ?? Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(dashboardScale == nil ? Theme.secondary : Color.clear, lineWidth: contrast == .increased ? 2.5 : 1.5))
            .overlay {
                if dashboardScale != nil, fraction > 0 {
                    Capsule().trim(from: 0, to: fraction).stroke(RideStyle.lime, lineWidth: 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if pressStart == nil { pressStart = Date() } }
            .onEnded { _ in pressStart = nil })
        .task(id: pressStart) {
            guard let start = pressStart else { return }
            while !Task.isCancelled {
                if HoldProgress.isComplete(held: Date().timeIntervalSince(start)) { pressStart = nil; action(); return }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Press and hold for one and a half seconds, or use the \(accessibilityActionName) action.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
        .accessibilityAction(named: accessibilityActionName, action)
        .background {
            if let shortcut { Button("", action: action).keyboardShortcut(shortcut).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true) }
        }
    }
}
