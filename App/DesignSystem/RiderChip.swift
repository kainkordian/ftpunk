import SwiftUI
import FTPunkDomain

/// Initials and name. The only place the rider is chosen.
struct RiderChip: View {
    let name: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = PrimaryActionPalette.colors(dark: scheme == .dark)
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text(RiderInitials.make(name)).font(.caption.weight(.bold))
                    .foregroundStyle(palette.foreground.color)
                    .frame(width: 28, height: 28).background(palette.background.color, in: Circle())
                    .accessibilityHidden(true)
                // Toolbars size their items from a minimal proposal; without fixedSize the name collapsed to nothing.
                // Long names are cut by `RiderChipName`, the full name stays in the accessibility label.
                Text(RiderChipName.display(name)).font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary).accessibilityHidden(true)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rider: \(name)")
        .accessibilityHint("Switch or add riders, and edit weight and FTP")
        .accessibilityIdentifier("rider-chip")
    }
}
