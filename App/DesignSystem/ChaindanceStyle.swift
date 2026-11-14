import SwiftUI

/// The ride dashboard's look, taken from the Chaindance (RG/SP) mockups: a deep blue-black screen, square boxes
/// with a thick outline, small uppercase captions in the top-left corner and large heavy numbers. Lime marks the
/// target, pink the heart, cyan the intensity. The rider and scenery of the mockups are not part of it (yet).
enum Chaindance {
    static let background = Color(red: 0x07 / 255, green: 0x05 / 255, blue: 0x1a / 255)
    static let panel = Color(red: 0x0f / 255, green: 0x0b / 255, blue: 0x27 / 255)
    static let panelRaised = Color(red: 0x18 / 255, green: 0x12 / 255, blue: 0x38 / 255)
    static let line = Color(red: 0x2c / 255, green: 0x24 / 255, blue: 0x63 / 255)
    static let dim = Color(red: 0x9a / 255, green: 0x94 / 255, blue: 0xd0 / 255)
    static let text = Color(red: 0xec / 255, green: 0xf0 / 255, blue: 0xfa / 255)
    static let lime = Color(red: 0xc5 / 255, green: 0xf7 / 255, blue: 0x4d / 255)
    static let cyan = Color(red: 0x00 / 255, green: 0xd3 / 255, blue: 0xe0 / 255)
    static let magenta = Color(red: 0xff / 255, green: 0x00 / 255, blue: 0x9a / 255)
    static let pink = Color(red: 0xff / 255, green: 0x6f / 255, blue: 0xb8 / 255)
    static let amber = Color(red: 0xfc / 255, green: 0xb8 / 255, blue: 0x52 / 255)
    /// The heart-rate line over the workout profile.
    static let heartLine = Color(red: 1, green: 92/255, blue: 92/255)

    enum Accent { case none, lime, cyan, pink, amber
        var color: Color? {
            switch self { case .none: nil; case .lime: Chaindance.lime; case .cyan: Chaindance.cyan; case .pink: Chaindance.pink; case .amber: Chaindance.amber }
        }
    }
}

extension View {
    /// Small uppercase caption, e.g. "STEP LEFT".
    func chaindanceCaption() -> some View {
        font(.system(.footnote, design: .rounded).weight(.bold)).textCase(.uppercase).tracking(1.2).foregroundStyle(Chaindance.dim)
    }
}

/// A big reading in the dashboard's number face; `size` is the point size at the default text size.
struct ChaindanceNumber: View {
    let text: String
    var size: CGFloat
    var color: Color = Chaindance.text
    @ScaledMetric(relativeTo: .largeTitle) private var scale = 1.0
    @AppStorage("extraLargeRideNumbers") private var extraLarge = false
    var body: some View {
        Text(text)
            .font(.system(size: size * scale * (extraLarge ? 1.2 : 1), weight: .black, design: .rounded))
            .monospacedDigit().tracking(-1).foregroundStyle(color)
            .shadow(color: color == Chaindance.text ? .clear : color.opacity(0.55), radius: 10)
            .lineLimit(1).minimumScaleFactor(0.4)
    }
}

/// One square box of the dashboard: caption top-left, optional corner text top-right, content below.
struct ChaindanceBox<Content: View>: View {
    let caption: String
    var accent: Chaindance.Accent = .none
    var corner: String?
    var minHeight: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(caption).chaindanceCaption()
                Spacer(minLength: Space.s)
                if let corner { Text(corner).chaindanceCaption().foregroundStyle(Chaindance.text) }
            }
            content.frame(maxWidth: .infinity)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(accent.color.map { $0.opacity(0.08) } ?? .clear)
        .background(Chaindance.panel)
        .overlay(Rectangle().strokeBorder(accent.color ?? Chaindance.line, lineWidth: 3))
        .shadow(color: (accent.color ?? .clear).opacity(0.3), radius: 8)
    }
}

/// The square −/+ buttons that live inside the target box.
struct ChaindanceStepButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.heavy)).monospacedDigit()
            .foregroundStyle(isEnabled ? Chaindance.background : Chaindance.dim)
            .padding(.horizontal, Space.m).frame(minWidth: 64, minHeight: 44)
            .background(isEnabled ? Chaindance.lime.opacity(configuration.isPressed ? 0.7 : 1) : Chaindance.line)
            .contentShape(Rectangle())
    }
}

/// Outlined square button for secondary dashboard actions such as Skip.
struct ChaindanceOutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.bold)).textCase(.uppercase).tracking(1)
            .foregroundStyle(isEnabled ? Chaindance.cyan : Chaindance.dim)
            .padding(.horizontal, Space.m).frame(minHeight: 44)
            .background(configuration.isPressed ? Chaindance.cyan.opacity(0.2) : Chaindance.panel)
            .overlay(Rectangle().strokeBorder(isEnabled ? Chaindance.cyan : Chaindance.line, lineWidth: 2))
            .contentShape(Rectangle())
    }
}
