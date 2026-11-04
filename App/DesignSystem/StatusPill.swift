import SwiftUI

/// Short status text with a symbol, so state never relies on colour alone.
struct StatusPill: View {
    enum Tone { case neutral, good, warning, danger }
    let text: String
    var symbol: String?
    var tone: Tone = .neutral

    private var tint: Color {
        switch tone { case .neutral: Theme.secondary; case .good: Theme.accent; case .warning: Theme.warning; case .danger: Theme.danger }
    }

    var body: some View {
        Group {
            if let symbol { Label(text, systemImage: symbol) } else { Text(text) }
        }
        .font(.caption.weight(.semibold)).foregroundStyle(tint)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}
