import SwiftUI
import FTPunkDomain

/// Warm-up, ramp and cool-down as one bar with a progress fill.
struct PhaseTimelineView: View {
    let timeline: PhaseTimeline
    let current: WorkoutPhase
    /// The words under the bar. Accessibility text sizes drop them to save height; the bar and its VoiceOver value remain.
    var showsLabels = true
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Space.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    ForEach(Array(timeline.segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(segment.phase == current ? Theme.accent.opacity(0.28) : Theme.secondary.opacity(0.16))
                            .frame(width: max(2, geometry.size.width * (segment.end - segment.start) - 2))
                            .offset(x: geometry.size.width * segment.start)
                    }
                    RoundedRectangle(cornerRadius: 4).fill(Theme.accent)
                        .frame(width: max(0, geometry.size.width * timeline.progress), height: 6)
                }
            }.frame(height: 10)
            if showsLabels {
                HStack {
                    ForEach(Array(timeline.segments.enumerated()), id: \.offset) { index, segment in
                        Text(label(segment.phase)).font(.caption2.weight(segment.phase == current ? .bold : .regular))
                            .foregroundStyle(segment.phase == current ? Color.primary : Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : index == timeline.segments.count - 1 ? .trailing : .center)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Test progress")
        .accessibilityValue("\(current.title), \(Int(timeline.progress * 100)) percent through the planned test")
    }
    private func label(_ phase: WorkoutPhase) -> String {
        switch phase { case .warmup: "warm-up"; case .ramp: "ramp"; default: "cool-down" }
    }
}
