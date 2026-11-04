import SwiftUI

/// One large reading: title, value, unit and an optional caption. Used for target, actual,
/// heart rate, cadence and best-minute readings so they all read the same from the saddle.
struct MetricTile: View {
    enum Tone { case normal, accent, warning, heart }
    let title: String
    let value: String?
    var unit = ""
    var symbol: String?
    var tone: Tone = .normal
    var caption: String?
    var role: NumberRole = .metric
    var placeholder = "—"
    var missingDescription = "No recent signal"

    private var tint: Color {
        switch tone { case .normal: .primary; case .accent: Theme.accent; case .warning: Theme.warning; case .heart: .pink }
    }

    var body: some View {
        VStack(spacing: Space.xs) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }.ftpLabel().foregroundStyle(.primary)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value ?? placeholder).ftpNumber(role).foregroundStyle(tone == .normal ? Color.primary : tint)
                if value != nil, !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(Theme.secondary) }
            }
            if let caption {
                Text(caption).font(.footnote.weight(.semibold))
                    .foregroundStyle(tone == .warning ? Theme.warning : Theme.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: role == .hero ? 130 : 100).padding(Space.m)
        .ftpCard(tint: tint, fill: tone == .warning ? 0.14 : 0.07)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\($0) \(unit)" + (caption.map { ". \($0)" } ?? "") } ?? missingDescription)
    }
}

/// The same reading as `MetricTile`, laid out as one short row (label left, number right) for accessibility text
/// sizes, where two tall tiles would push the second reading off the screen. Falls back to label-above-number
/// when the row is too narrow.
struct MetricRow: View {
    let title: String
    let value: String?
    var unit = ""
    var symbol: String?
    var tone: MetricTile.Tone = .normal
    var caption: String?
    /// Hero rows hide the caption to stay one line tall; VoiceOver still reads it.
    var showsCaption = true
    var placeholder = "—"
    var missingDescription = "No recent signal"

    private var tint: Color {
        switch tone { case .normal: .primary; case .accent: Theme.accent; case .warning: Theme.warning; case .heart: .pink }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
            }.ftpLabel().foregroundStyle(.primary)
            if showsCaption, let caption {
                Text(caption).font(.footnote.weight(.semibold))
                    .foregroundStyle(tone == .warning ? Theme.warning : Theme.secondary)
            }
        }
    }
    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(value ?? placeholder).ftpNumber(.metric).foregroundStyle(tone == .normal ? Color.primary : tint)
            if value != nil, !unit.isEmpty { Text(unit).font(.footnote).foregroundStyle(Theme.secondary) }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                heading
                Spacer(minLength: Space.s)
                reading
            }
            VStack(alignment: .leading, spacing: Space.xs) { heading; reading }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.m)
        .ftpCard(tint: tint, fill: tone == .warning ? 0.14 : 0.07)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\($0) \(unit)" + (caption.map { ". \($0)" } ?? "") } ?? missingDescription)
    }
}
