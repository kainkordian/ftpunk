import SwiftUI

/// Countdown to the next ramp step: a ring that drains, with the change and time beside it.
struct StepCountdownRing: View {
    let fraction: Double
    let remainingSeconds: Int
    let nextChange: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.m) {
            ZStack {
                Circle().stroke(Theme.secondary.opacity(0.25), lineWidth: 6)
                Circle().trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: fraction)
                Text("\(remainingSeconds)").font(.headline).monospacedDigit()
            }.frame(width: 52, height: 52)
            Text("\(nextChange) in \(remainingSeconds) s").font(.title3.weight(.semibold)).monospacedDigit()
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next step")
        .accessibilityValue("\(nextChange) in \(remainingSeconds) seconds")
    }
}
