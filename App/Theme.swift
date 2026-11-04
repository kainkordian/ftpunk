import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

enum Theme {
    static var controlTint: Color { PrimaryActionPalette.controlBackground.color }
    static var secondary: Color { adaptive(light: (0.28, 0.31, 0.29), dark: (0.74, 0.78, 0.75)) }
    static var warning: Color { adaptive(light: (0.50, 0.25, 0.02), dark: (0.99, 0.72, 0.32)) }
    static var danger: Color { adaptive(light: (0.68, 0.12, 0.12), dark: (1, 0.55, 0.55)) }
    static var surface: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }
    /// Distinguishable series colours for riders; each pair keeps 3:1 against its background (tested).
    static let riderPalette: [(light: ActionRGB, dark: ActionRGB)] = [
        (ActionRGB(red: 0.12, green: 0.39, blue: 0.19), ActionRGB(red: 0.77, green: 0.97, blue: 0.30)),
        (ActionRGB(red: 0.05, green: 0.35, blue: 0.80), ActionRGB(red: 0.45, green: 0.70, blue: 1.0)),
        (ActionRGB(red: 0.75, green: 0.35, blue: 0.0), ActionRGB(red: 1.0, green: 0.65, blue: 0.25)),
        (ActionRGB(red: 0.65, green: 0.10, blue: 0.55), ActionRGB(red: 1.0, green: 0.55, blue: 0.90)),
        (ActionRGB(red: 0.0, green: 0.45, blue: 0.50), ActionRGB(red: 0.35, green: 0.90, blue: 0.90)),
        (ActionRGB(red: 0.40, green: 0.30, blue: 0.20), ActionRGB(red: 0.80, green: 0.70, blue: 0.55))
    ]
    static func riderColor(at index: Int) -> Color {
        let pair = riderPalette[index % riderPalette.count]
        return adaptive(light: (pair.light.red, pair.light.green, pair.light.blue), dark: (pair.dark.red, pair.dark.green, pair.dark.blue))
    }
    /// The app's accent: lime on dark surfaces, dark green on light ones. The pair is public so tests can check contrast.
    static let accentPair: (light: ActionRGB, dark: ActionRGB) = (ActionRGB(red: 0.12, green: 0.39, blue: 0.19), ActionRGB(red: 0.77, green: 0.97, blue: 0.30))
    static var accent: Color { colorPair(accentPair) }
    /// A colour that changes with the appearance.
    static func colorPair(_ pair: (light: ActionRGB, dark: ActionRGB)) -> Color {
        adaptive(light: (pair.light.red, pair.light.green, pair.light.blue), dark: (pair.dark.red, pair.dark.green, pair.dark.blue))
    }
}

struct ActionRGB {
    let red: Double, green: Double, blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func contrast(with other: ActionRGB) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

enum PrimaryActionPalette {
    static let controlBackground = ActionRGB(red: 0.18, green: 0.48, blue: 0.24)
    static func colors(dark: Bool) -> (foreground: ActionRGB, background: ActionRGB) {
        dark ? (ActionRGB(red: 0.04, green: 0.06, blue: 0.04), ActionRGB(red: 0.77, green: 0.97, blue: 0.30))
             : (ActionRGB(red: 1, green: 1, blue: 1), ActionRGB(red: 0.12, green: 0.39, blue: 0.19))
    }
}

/// Explicit opaque fills prevent system/glass styles from pairing white text with lime.
struct FTPunkPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        let palette = PrimaryActionPalette.colors(dark: scheme == .dark)
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(enabled ? palette.foreground.color : Color.secondary)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(enabled ? palette.background.color : Color.secondary.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(contrast == .increased ? 0.8 : 0), lineWidth: 2))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct FTPunkSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary)
            .padding(.horizontal, 18).padding(.vertical, 12).frame(minWidth: 44, minHeight: 44)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.secondary, lineWidth: 1.5))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

/// Low-emphasis action that still looks tappable: a tinted, full-width shape with accent text and a 44 pt minimum height.
/// Use it for "Skip"-style choices next to a primary or secondary button; plain text alone reads as a label.
struct FTPunkTertiaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(enabled ? Theme.accent : Color.secondary)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.accent.opacity(enabled ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(contrast == .increased && enabled ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Form actions fill the available row instead of only responding on their text.
struct FTPunkRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct FTPunkDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    configuration.label.foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(FTPunkRowButtonStyle())
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(configuration.isExpanded ? "Hide options" : "Show options")
            if configuration.isExpanded {
                configuration.content.padding(.top, 8)
            }
        }
    }
}

/// One button handles both label and switch taps, with native switch accessibility.
struct FTPunkRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("", isOn: configuration.$isOn)
                    .labelsHidden().toggleStyle(.switch).tint(Theme.controlTint)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .buttonStyle(FTPunkRowButtonStyle())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

/// Keeps partial input editable; only complete, in-range values update the model.
struct DurationInputField: View {
    let title: String
    @Binding var minutes: Int
    @Binding var isValid: Bool
    @ViewState private var input: String
    @FocusState private var focused: Bool
    private var parsed: Int? { Int(input.trimmingCharacters(in: .whitespacesAndNewlines)) }

    init(title: String, minutes: Binding<Int>, isValid: Binding<Bool>) {
        self.title = title; self._minutes = minutes; self._isValid = isValid
        self._input = ViewState(initialValue: String(minutes.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration")
                Spacer(minLength: 12)
                TextField("Minutes", text: $input)
                    .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .frame(width: 90).focused($focused)
                    .accessibilityLabel("\(title) duration in minutes")
                    .accessibilityHint("Enter a whole number from zero to sixty. Zero skips this phase.")
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                Text("min").foregroundStyle(Theme.secondary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
            .onTapGesture { focused = true }
            if !isValid {
                Text("Enter a whole number from 0 to 60 minutes.")
                    .font(.footnote).foregroundStyle(Theme.danger)
            } else {
                Text("0–60 minutes · 0 skips this phase")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .onAppear { isValid = parsed.map { (0...60).contains($0) } ?? false }
        .onChange(of: input) { _, _ in
            if let parsed, (0...60).contains(parsed) { minutes = parsed; isValid = true }
            else { isValid = false }
        }
        .onChange(of: minutes) { _, value in
            if !focused { input = String(value) }
        }
        #if canImport(UIKit)
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        #endif
    }
}

extension View {
    @ViewBuilder func numberEntry() -> some View {
        #if canImport(UIKit)
        self.keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        #else
        self.multilineTextAlignment(.trailing)
        #endif
    }
}
