import SwiftUI

/// A selectable capsule for category and activity filters. Selection shows as fill and trait, and
/// Increase Contrast adds an outline.
struct FilterChip: View {
    let title: String
    let selected: Bool
    var identifier: String?
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .bold : .regular))
                .padding(.horizontal, Space.m).frame(minHeight: 44)
                .foregroundStyle(selected ? PrimaryActionPalette.colors(dark: scheme == .dark).foreground.color : Color.primary)
                .background(selected ? PrimaryActionPalette.colors(dark: scheme == .dark).background.color : Theme.secondary.opacity(0.14), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0), lineWidth: 2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "chip-\(title)")
    }
}
