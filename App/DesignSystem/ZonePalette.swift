import SwiftUI
import FTPunkDomain

/// Colours for the workout profile charts, one per intensity zone. They climb in lightness with intensity (darker in
/// light mode, brighter in dark mode) so zones differ by more than hue, and each keeps 3:1 against the chart
/// background in both themes (tested). Hues: neutral grey, teal, green, lime/olive, then the icon's magenta.
enum ZonePalette {
    typealias Pair = (light: ActionRGB, dark: ActionRGB)

    static func pair(for zone: IntensityZone) -> Pair {
        switch zone {
        case .recovery: (ActionRGB(red: 0.49, green: 0.51, blue: 0.49), ActionRGB(red: 0.53, green: 0.55, blue: 0.53))
        case .endurance: (ActionRGB(red: 0.10, green: 0.50, blue: 0.44), ActionRGB(red: 0.13, green: 0.66, blue: 0.58))
        case .tempo: (ActionRGB(red: 0.17, green: 0.46, blue: 0.17), ActionRGB(red: 0.28, green: 0.74, blue: 0.28))
        case .sweetSpot: (ActionRGB(red: 0.29, green: 0.38, blue: 0.08), ActionRGB(red: 0.59, green: 0.76, blue: 0.17))
        case .threshold: (ActionRGB(red: 0.53, green: 0.12, blue: 0.38), ActionRGB(red: 1.00, green: 0.64, blue: 0.90))
        case .vo2max: (ActionRGB(red: 0.43, green: 0.06, blue: 0.32), ActionRGB(red: 1.00, green: 0.72, blue: 0.96))
        }
    }
    static func color(for zone: IntensityZone) -> Color { Theme.colorPair(pair(for: zone)) }

    /// Surfaces a profile can sit on, for contrast checks: card on the page, chart tint on the card.
    static let lightBackground = ActionRGB(red: 0.90, green: 0.90, blue: 0.90)
    static let darkBackground = ActionRGB(red: 0.10, green: 0.10, blue: 0.10)
}
