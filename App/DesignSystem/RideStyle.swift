import SwiftUI
import CoreText
import FTPunkDomain

enum RideStyle {
    static let ground = Color(red: 13/255, green: 12/255, blue: 21/255)
    static let tile = Color(red: 25/255, green: 24/255, blue: 39/255)
    static let raised = Color(red: 35/255, green: 34/255, blue: 53/255)
    static let text = Color(red: 243/255, green: 244/255, blue: 248/255)
    static let dim = Color(red: 169/255, green: 169/255, blue: 191/255)
    static let lime = Color(red: 197/255, green: 247/255, blue: 77/255)
    static let heart = Chaindance.heartLine
    static let coolTile = Color(red: 21/255, green: 36/255, blue: 48/255)
    static let progressGrey = Color(red: 125/255, green: 129/255, blue: 145/255)
    static let cyan = Color(red: 95/255, green: 217/255, blue: 232/255)
    static let gaugeAmberOnWarning = Color(red: 97/255, green: 56/255, blue: 10/255)
    static let warning = Color(red: 252/255, green: 184/255, blue: 82/255)
}

extension Font {
    private static let registerRideFont: Bool = {
        var location = Bundle.main.url(forResource: "Tektur", withExtension: "ttf", subdirectory: "Fonts")
        #if SWIFT_PACKAGE
        if location == nil { location = Bundle.module.url(forResource: "Tektur", withExtension: "ttf", subdirectory: "Fonts") }
        #endif
        guard let url = location else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return true
    }()
    static func ftp(_ size: CGFloat, weight: Font.Weight = .black, width: Double = 85) -> Font {
        let choice = UserDefaults.standard.string(forKey: "appFont") ?? "tektur"
        if choice == "tektur", registerRideFont {
            let descriptor = CTFontDescriptorCreateWithAttributes([
                kCTFontNameAttribute: "Tektur-Regular", kCTFontSizeAttribute: size,
                kCTFontVariationAttribute: [2003072104: width, 2003265652: weight == .black ? 900 : 800]
            ] as CFDictionary)
            return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        }
        return .system(size: size, weight: weight, design: choice == "system" ? .default : .rounded)
    }
}

struct DashNumber: View {
    let text: String
    let size: Double
    var color: Color = RideStyle.text
    var unit = ""
    var unitColor: Color? = nil
    var unitSize: Double? = nil
    @AppStorage("appFont") private var appFont = "tektur"
    @AppStorage("extraLargeRideNumbers") private var extraLarge = false
    @ScaledMetric(relativeTo: .largeTitle) private var textScale = 1.0
    private var renderedSize: Double {
        #if os(iOS)
        size * min(1.5, textScale) * (extraLarge ? 1.1 : 1)
        #else
        size
        #endif
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: renderedSize * 0.05) {
            Text(text).font(.ftp(renderedSize)).monospacedDigit().tracking(-renderedSize * 0.02)
            if !unit.isEmpty { Text(unit).font(.ftp(unitSize.map { $0 * renderedSize / size } ?? renderedSize * 0.24, weight: .bold)).foregroundStyle(unitColor ?? RideStyle.dim) }
        }
        // CSS uses line-height: .8. Preserve the font’s intrinsic line height before
        // assigning that layout box, so SwiftUI cannot shrink every glyph to fit it.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.55).frame(height: renderedSize * 0.8)
        .accessibilityElement(children: .combine)
    }
}
struct DashCaption: View {
    let text: String
    var size = 30.0
    var color: Color = RideStyle.dim
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: size * 0.4) {
            if let symbol { Image(systemName: symbol) }
            Text(text.uppercased()).tracking(size * 0.05)
        }.font(.ftp(size, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
    }
}
struct DashTile<Content: View>: View {
    var scale = 1.0
    var fill = RideStyle.tile
    var horizontalPadding = 32.0
    var verticalPadding = 26.0
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding * scale).padding(.vertical, verticalPadding * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: 32 * scale))
            .background(RideStyle.tile, in: RoundedRectangle(cornerRadius: 32 * scale))
    }
}
struct DashStepper: View {
    var value: String? = nil
    var minus = "−"
    var plus = "+"
    var minusID: String
    var plusID: String
    var lowerDisabled = false
    var upperDisabled = false
    let scale: Double
    let lower: () -> Void
    let raise: () -> Void
    var body: some View {
        HStack(spacing: 6 * scale) {
            Button(minus, action: lower).disabled(lowerDisabled).accessibilityIdentifier(minusID)
                .accessibilityLabel(minusID.hasPrefix("intensity") ? "Lower intensity by 1 percent" : minusID.hasPrefix("erg") ? "Lower target by 5 watts" : "Lower resistance")
            if let value { Text(value).font(.ftp(30 * scale, weight: .bold)).frame(minWidth: 100 * scale) }
            Button(plus, action: raise).disabled(upperDisabled).accessibilityIdentifier(plusID)
                .accessibilityLabel(plusID.hasPrefix("intensity") ? "Raise intensity by 1 percent" : plusID.hasPrefix("erg") ? "Raise target by 5 watts" : "Raise resistance")
        }
        .buttonStyle(DashButtonStyle(scale: scale, size: 26, height: 56))
        .padding(6 * scale).background(RideStyle.ground, in: Capsule())
    }
}
struct DashButtonStyle: ButtonStyle {
    var scale = 1.0
    var size = 17.0
    var height = 44.0
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.ftp(size * scale, weight: .bold)).foregroundStyle(RideStyle.text)
            .padding(.horizontal, 16 * scale).frame(minHeight: height * scale)
            .background(RideStyle.raised.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
    }
}
struct SegmentCountdown: View {
    let filled: Int
    var scale = 1.0
    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(0..<12) { index in
                RoundedRectangle(cornerRadius: 6 * scale)
                    .fill(index < filled ? RideStyle.lime : RideStyle.raised)
            }
        }.frame(height: 32 * scale).accessibilityHidden(true)
    }
}

/// The reference's pill segments, shared by the ride-screen preferences.
struct RideChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [(String, Value)]
    var detail: String? = nil
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { label; Spacer(); segments }
            VStack(alignment: .leading, spacing: 10) { label; segments }
        }
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let detail { Text(detail).font(.callout).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(choices.indices, id: \.self) { index in
                let item = choices[index]
                Button { selection = item.1 } label: {
                    Text(item.0).font(.ftp(16, weight: .bold)).padding(.horizontal, 14).frame(minHeight: 40)
                        .foregroundStyle(selection == item.1 ? RideStyle.ground : RideStyle.dim)
                        .background(selection == item.1 ? RideStyle.lime : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel("\(title): \(item.0)")
                    .accessibilityAddTraits(selection == item.1 ? .isSelected : [])
            }
        }.padding(4).background(RideStyle.tile, in: Capsule())
    }
}
struct RideSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button { configuration.isOn.toggle() } label: {
                Capsule().fill(configuration.isOn ? RideStyle.lime : RideStyle.raised)
                    .frame(width: 52, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? RideStyle.ground : RideStyle.text).frame(width: 24, height: 24).padding(3)
                    }
            }.buttonStyle(.plain)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}
