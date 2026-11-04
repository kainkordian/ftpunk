import SwiftUI
import FTPunkDomain

/// A workout in the library: name, computed duration, a profile thumbnail and what it needs.
struct WorkoutCard: View {
    let title: String
    let detail: String
    var plan: TrainingPlan?
    var badge: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                if let plan { WorkoutProfileChart(plan: plan, height: 44) }
                else { RoundedRectangle(cornerRadius: 8).fill(Theme.secondary.opacity(0.12)).frame(height: 44) }
                if let badge { StatusPill(text: badge, tone: .warning) }
            }
            .padding(Space.m).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .ftpCard(fill: 0.05).contentShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([detail, badge].compactMap { $0 }.joined(separator: ". "))
        .accessibilityHint("Shows the workout steps and start options")
        .accessibilityAddTraits(.isButton)
    }
}
