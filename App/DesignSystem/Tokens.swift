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
    static let card: CGFloat = 24
    static let tile: CGFloat = 32
    static let pill: CGFloat = 999
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
    @AppStorage("appFont") private var appFont = "tektur"
    func body(content: Content) -> some View {
        content.font(.ftp((role == .hero ? hero : metric) * (extraLarge ? 1.2 : 1), weight: .bold))
            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
    }
}

extension View {
    func ftpNumber(_ role: NumberRole) -> some View { modifier(ScaledNumber(role: role)) }
    /// Small uppercase caption above a value.
    func ftpLabel() -> some View { modifier(AppText(style: .caption, weight: .bold)) }
    /// Card surface with a stronger outline under Increase Contrast.
    func ftpCard(tint: Color = .primary, fill: Double = 0.07) -> some View { modifier(CardSurface(tint: tint, fill: fill)) }
}

struct CardSurface: ViewModifier {
    let tint: Color
    let fill: Double
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background { RoundedRectangle(cornerRadius: Radius.card).fill(Theme.surface).overlay { RoundedRectangle(cornerRadius: Radius.card).fill(tint.opacity(fill)) } }
            .overlay(RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0), lineWidth: contrast == .increased ? 2 : 1))
    }
}

struct AppText: ViewModifier {
    let style: Font.TextStyle
    var weight: Font.Weight = .regular
    @AppStorage("appFont") private var appFont = "tektur"
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    func body(content: Content) -> some View { content.font(.ftp(style, weight: weight, scale: textScale)) }
}
extension View {
    func ftpText(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View { modifier(AppText(style: style, weight: weight)) }
}
extension Font {
    static func ftp(_ style: Font.TextStyle, weight: Font.Weight = .regular, scale: Double = 1) -> Font {
        let size: Double
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline: size = 16
        case .subheadline: size = 15
        case .callout: size = 14
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        default: size = 16
        }
        let resolved: Font.Weight
        switch style { case .largeTitle, .title, .title2, .title3, .headline: resolved = weight == .regular ? .bold : weight; default: resolved = weight }
        return .ftp(size * scale, weight: resolved)
    }
}

struct FTPTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(focused ? Theme.accent : Theme.secondary.opacity(0.3), lineWidth: focused ? 2 : 1))
            .focused($focused)
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var grouped = false
    @ViewBuilder let control: Control
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { label; Spacer(minLength: 12); control.fixedSize(horizontal: true, vertical: false) }
            VStack(alignment: .leading, spacing: 12) { label; control }
        }.frame(minHeight: 64).padding(.horizontal, 22).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: grouped ? 0 : Radius.card))
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).ftpText(.headline, weight: .semibold)
            if let detail { Text(detail).ftpText(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
