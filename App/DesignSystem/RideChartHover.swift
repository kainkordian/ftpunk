import SwiftUI
import Charts
import FTPunkDomain

/// Where the pointer is over a finished ride's charts, shared by all of them: each draws a rule at that moment, and the
/// chart under the pointer also shows the readings. Kept in its own object so a pointer move redraws only the overlays,
/// not the charts' thousands of points.
@MainActor @Observable final class RideChartHover {
    var time: Double?
    var chart: String?
}

/// The hover layer of one ride chart, placed in its `chartOverlay`. The chart's x axis is minutes. On a Mac (or an iPad
/// with a pointer) it follows the pointer; a tap shows the readings at that point too, and tapping the same spot again hides them.
struct RideChartHoverOverlay: View {
    let proxy: ChartProxy
    let session: TestSession
    let hover: RideChartHover
    let chart: String

    var body: some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .frame(width: plot.width, height: plot.height)
                        .offset(x: plot.minX, y: plot.minY)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): point(at: location.x, plot: plot)
                            case .ended: hover.time = nil; hover.chart = nil
                            }
                        }
                        .onTapGesture { location in
                            if hover.chart == chart, let time = hover.time, let x = proxy.position(forX: time / 60), abs(x - (location.x - plot.minX)) < 8 {
                                hover.time = nil; hover.chart = nil
                            } else { point(at: location.x, plot: plot) }
                        }
                    if let time = hover.time, let x = proxy.position(forX: time / 60), x >= 0, x <= plot.width {
                        Rectangle().fill(Theme.secondary.opacity(0.8)).frame(width: 1, height: plot.height)
                            .offset(x: plot.minX + x, y: plot.minY).allowsHitTesting(false)
                        if hover.chart == chart {
                            RideMomentCard(moment: RideMoment.at(session, time: time), showsPower: session.training?.resistance == nil)
                                .fixedSize()
                                // Right of the rule in the left half of the plot, left of it in the right half.
                                .padding(x < plot.width / 2 ? .leading : .trailing, x < plot.width / 2 ? x + 8 : plot.width - x + 8)
                                .frame(width: plot.width, alignment: x < plot.width / 2 ? .leading : .trailing)
                                .offset(x: plot.minX, y: plot.minY + 4).allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .accessibilityHidden(true)
    }

    private func point(at locationX: CGFloat, plot: CGRect) {
        let x = min(max(locationX - plot.minX, 0), plot.width)
        guard let minutes = proxy.value(atX: x, as: Double.self) else { return }
        hover.time = max(0, minutes * 60); hover.chart = chart
    }
}

/// The readings at one moment of a ride: elapsed time, then whatever was recorded then.
struct RideMomentCard: View {
    let moment: RideMoment
    var showsPower = true

    private var rows: [(String, String, Color)] {
        var rows: [(String, String, Color)] = []
        if showsPower, let power = moment.power { rows.append(("Power", "\(Int(power.rounded())) W", Theme.accent)) }
        if let target = moment.target { rows.append(("Target", "\(target) W", .primary)) }
        if showsPower, let trainer = moment.trainerPower { rows.append(("Trainer", "\(Int(trainer.rounded())) W", Theme.secondary)) }
        if let heartRate = moment.heartRate { rows.append(("Heart rate", "\(heartRate) bpm", .pink)) }
        if let cadence = moment.cadence { rows.append(("Cadence", "\(Int(cadence.rounded())) rpm", Theme.secondary)) }
        if let left = moment.leftBalance { rows.append(("L / R", "\(RideFigures.balance(left)) %", Theme.secondary)) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(DurationFormat.clock(moment.time)).font(.caption.weight(.bold)).monospacedDigit()
            if rows.isEmpty { Text("No readings").font(.caption).foregroundStyle(Theme.secondary) }
            Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: 2) {
                ForEach(rows, id: \.0) { title, value, color in
                    GridRow {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 6, height: 6)
                            Text(title).foregroundStyle(Theme.secondary)
                        }
                        Text(value).monospacedDigit().gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, Space.s).padding(.vertical, 6)
        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.secondary.opacity(0.3)))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }
}
