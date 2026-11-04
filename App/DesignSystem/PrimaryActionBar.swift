import SwiftUI

/// The one obvious next action: a full-width button pinned to the bottom. When the button
/// is disabled, the reason sits directly above it.
struct PrimaryActionBar<Secondary: View>: View {
    let title: String
    var systemImage: String?
    var reason: String?
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        VStack(spacing: Space.s) {
            if let reason, !isEnabled {
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("start-blocker")
            }
            Button(action: action) {
                Group {
                    if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(FTPunkPrimaryButtonStyle()).controlSize(.large)
            .disabled(!isEnabled)
            .accessibilityIdentifier("primary-action")
            secondary()
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

extension PrimaryActionBar where Secondary == EmptyView {
    init(title: String, systemImage: String? = nil, reason: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.init(title: title, systemImage: systemImage, reason: reason, isEnabled: isEnabled, action: action) { EmptyView() }
    }
}
