import SwiftUI
import FTPunkDomain

/// Step profile of a workout: bar height is the target on a fixed 0–130 % of FTP scale (so a VO2max set looks
/// taller than tempo on every card), ramps are slanted, and an optional marker shows progress. Bars are coloured by
/// intensity zone. Without an FTP there are no percentages, so heights follow the plan's own peak and the bars are
/// neutral. Drawn with a Canvas, so it stays cheap on the ride screen.
struct WorkoutProfileChart: View {
    let plan: TrainingPlan
    var intensity = 100
    var progressSeconds: Double?
    var height: CGFloat = 70
    /// Set to make the chart inspectable: hover (Mac), touch-drag (iOS) and VoiceOver steps. Nil keeps it a plain picture.
    var selectedStep: Binding<Int?>?
    /// Labels "50 %" and "100 %" on the left edge (only with an FTP).
    var showsAxis = false
    /// False when the rider has no FTP yet: tooltips then show durations only.
    var showsValues = true
    /// Heart rate recorded so far, on the training clock (`WorkoutClock.heartRate`), drawn as a red line over the bars.
    /// Its own scale: 0 to 200 bpm (or the highest reading, if higher), so it reads beside the targets, not against them.
    var heartRate: [(time: Double, bpm: Int)] = []

    private var axisWidth: CGFloat { showsAxis && showsValues && (plan.ftpWatts.map { $0 > 0 } ?? false) ? 36 : 0 }

    var body: some View {
        let bars = WorkoutProfile.bars(for: plan, intensity: intensity)
        let total = max(1, plan.duration)
        let hasFTP = plan.ftpWatts.map { $0 > 0 } ?? false
        let segments = WorkoutProfile.segments(for: plan, intensity: intensity)
        let peak = WorkoutProfile.peakWatts(for: plan, intensity: intensity)
        let left = axisWidth
        let selected = selectedStep?.wrappedValue
        Canvas { context, size in
            let plotWidth = size.width - left
            if left > 0 {
                for percent in [50.0, 100.0] {
                    let y = size.height * (1 - percent / WorkoutProfile.scaleMaxPercent)
                    context.draw(Text("\(Int(percent)) %").font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary),
                                 at: CGPoint(x: left - 4, y: y), anchor: .trailing)
                }
            }
            if hasFTP {
                // 100 % of FTP, so each bar can be read against the rider's threshold.
                let y = size.height * (1 - 100 / WorkoutProfile.scaleMaxPercent)
                var line = Path(); line.move(to: CGPoint(x: left, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(Theme.secondary.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            for (index, (bar, segment)) in zip(bars, segments).enumerated() {
                let x0 = left + plotWidth * bar.start, x1 = left + plotWidth * bar.end
                let y0 = size.height * (1 - bar.startHeight), y1 = size.height * (1 - bar.endHeight)
                var path = Path()
                path.move(to: CGPoint(x: x0, y: size.height)); path.addLine(to: CGPoint(x: x0, y: y0))
                path.addLine(to: CGPoint(x: max(x0 + 1, x1 - 0.5), y: y1)); path.addLine(to: CGPoint(x: max(x0 + 1, x1 - 0.5), y: size.height))
                path.closeSubpath()
                let done = progressSeconds.map { $0 >= segment.end } ?? false
                let dimmed = selected.map { $0 != index } ?? false
                context.fill(path, with: .color(color(for: bar).opacity(done ? 0.45 : dimmed ? 0.6 : 1)))
                if selected == index { context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineJoin: .round)) }
            }
            if heartRate.count >= 2 {
                let top = Double(max(200, heartRate.map(\.bpm).max() ?? 0))
                var line = Path(), previous: Double?
                for point in heartRate {
                    let p = CGPoint(x: left + plotWidth * min(1, max(0, point.time / total)), y: size.height * (1 - Double(point.bpm) / top))
                    // A gap of more than five seconds (a pause, a lost signal) breaks the line.
                    if let previous, point.time - previous <= 5 { line.addLine(to: p) } else { line.move(to: p) }
                    previous = point.time
                }
                context.stroke(line, with: .color(Chaindance.heartLine), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let progressSeconds {
                let x = left + plotWidth * min(1, max(0, progressSeconds / total))
                context.fill(Path(CGRect(x: x - 1.5, y: 0, width: 3, height: size.height)), with: .color(.primary))
            }
        }
        .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 8))
        .background(Theme.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay { interactionLayer(left: left, bars: bars) }
        .modifier(ChartAccessibility(interactive: selectedStep != nil, label: accessibilityValue(peak: peak, hasFTP: hasFTP),
                                     steps: selectedStep == nil ? [] : WorkoutPreview.steps(for: plan, intensity: intensity, showValues: showsValues)))
    }

    @ViewBuilder private func interactionLayer(left: CGFloat, bars: [ProfileBar]) -> some View {
        if let selectedStep {
            GeometryReader { geo in
                let plotWidth = max(1, geo.size.width - left)
                ZStack(alignment: .top) {
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): selectedStep.wrappedValue = step(at: point.x, left: left, plotWidth: plotWidth)
                            case .ended: selectedStep.wrappedValue = nil
                            }
                        }
                        #if os(iOS)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { selectedStep.wrappedValue = step(at: $0.location.x, left: left, plotWidth: plotWidth) }
                            .onEnded { _ in selectedStep.wrappedValue = nil })
                        #endif
                    if let index = selectedStep.wrappedValue, bars.indices.contains(index) {
                        let summary = WorkoutPreview.steps(for: plan, intensity: intensity, showValues: showsValues)[index]
                        let bar = bars[index]
                        let startX = left + plotWidth * bar.start, endX = left + plotWidth * bar.end, centerX = (startX + endX) / 2
                        let alignment: Alignment = centerX < geo.size.width * 0.3 ? .leading : centerX > geo.size.width * 0.7 ? .trailing : .center
                        tooltip(summary)
                            .frame(width: geo.size.width, alignment: alignment)
                            .offset(x: alignment == .center ? centerX - geo.size.width / 2 : 0)
                            .alignmentGuide(.top) { $0[.bottom] + 4 }
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func step(at x: CGFloat, left: CGFloat, plotWidth: CGFloat) -> Int? {
        WorkoutPreview.step(atFraction: min(1, max(0, (x - left) / plotWidth)), in: plan)
    }

    private func tooltip(_ step: WorkoutStepSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.name).font(.caption.weight(.semibold))
            Text(step.valueText).font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.secondary.opacity(0.4), lineWidth: 1))
        .fixedSize()
    }

    private func color(for bar: ProfileBar) -> Color {
        guard let zone = bar.zone else { return Theme.secondary.opacity(0.35 + 0.45 * (bar.startHeight + bar.endHeight) / 2) }
        return ZonePalette.color(for: zone)
    }

    private func accessibilityValue(peak: Double, hasFTP: Bool) -> String {
        var text = "\(plan.steps.count) steps over \(Int((plan.duration / 60).rounded())) minutes, peak target \(Int(peak.rounded())) watts"
        if hasFTP, let ftp = plan.ftpWatts { text += ", \(Int((peak / ftp * 100).rounded())) percent of FTP" }
        return text
    }
}

/// A plain chart reads as one element; an interactive one lets VoiceOver swipe through its steps.
private struct ChartAccessibility: ViewModifier {
    let interactive: Bool
    let label: String
    let steps: [WorkoutStepSummary]
    func body(content: Content) -> some View {
        if interactive {
            content.accessibilityLabel("Workout profile").accessibilityValue(label)
                .accessibilityChildren {
                    VStack {
                        ForEach(steps, id: \.index) { step in Rectangle().accessibilityLabel(step.spokenText) }
                    }
                }
        } else {
            content.accessibilityElement(children: .ignore).accessibilityLabel("Workout profile").accessibilityValue(label)
        }
    }
}
