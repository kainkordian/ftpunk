import SwiftUI
import FTPunkDomain

/// A workout in the library: name, computed duration, a profile thumbnail and what it needs.
struct WorkoutCard: View {
    let title: String
    let detail: String
    var plan: TrainingPlan?
    var badge: String?
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title).ftpText(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(detail).ftpText(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                if let plan { WorkoutProfileChart(plan: plan, height: 36, dashboard: true) }
                else { RoundedRectangle(cornerRadius: 8).fill(Theme.secondary.opacity(0.12)).frame(height: 44) }
                if let badge { StatusPill(text: badge, tone: .warning) }
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.text.opacity(contrast == .increased ? 0.8 : 0), lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue([detail, badge].compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint("Shows the workout steps and start options")
        .accessibilityAddTraits(.isButton)
    }
}
