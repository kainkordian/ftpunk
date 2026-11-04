import SwiftUI

/// Spacing and shape scales. Colours stay in `Theme`.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let control: CGFloat = 14
    static let card: CGFloat = 20
}

/// Type scale: hero and metric numbers scale with Dynamic Type and the extra-large setting.
enum NumberRole {
    case hero, metric
}

struct ScaledNumber: ViewModifier {
    let role: NumberRole
    @ScaledMetric(relativeTo: .largeTitle) private var hero = 72.0
    @ScaledMetric(relativeTo: .largeTitle) private var metric = 38.0
    @AppStorage("extraLargeRideNumbers") private var extraLarge = false
    func body(content: Content) -> some View {
        content.font(.system(size: (role == .hero ? hero : metric) * (extraLarge ? 1.2 : 1), weight: .bold, design: .rounded))
            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
    }
}

extension View {
    func ftpNumber(_ role: NumberRole) -> some View { modifier(ScaledNumber(role: role)) }
    /// Small uppercase caption above a value.
    func ftpLabel() -> some View { font(.footnote.weight(.bold)) }
    /// Card surface with a stronger outline under Increase Contrast.
    func ftpCard(tint: Color = .primary, fill: Double = 0.07) -> some View { modifier(CardSurface(tint: tint, fill: fill)) }
}

struct CardSurface: ViewModifier {
    let tint: Color
    let fill: Double
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(tint.opacity(fill), in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0.12), lineWidth: contrast == .increased ? 2 : 1))
    }
}
