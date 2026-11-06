import SwiftUI
import Charts
import FTPunkDomain

/// Recorded power with phase bands and the scored best minute highlighted and labelled.
///
/// Labels are drawn in an overlay at positions the chart reports, not as mark annotations: phase names sit in a
/// top row inside the plot, each no wider than its own band (short forms, or nothing, for narrow bands), and the
/// best-minute label sits in a second row, clamped inside the plot. Nothing is drawn near the axis labels.
struct ResultPowerChart: View {
    let session: TestSession
    @ScaledMetric(relativeTo: .caption2) private var phaseCharacterWidth = 6.4
    @ScaledMetric(relativeTo: .caption) private var bestCharacterWidth = 7.6
    @ScaledMetric(relativeTo: .caption2) private var rowHeight = 17.0

    private struct Point: Identifiable { let id: Int; let time: Double; let power: Double; let segment: Int }
    private var points: [Point] {
        var result: [Point] = [], segment = 0
        var previous: Double?
        for (index, sample) in session.samples.enumerated() {
            guard let power = sample.power else { continue }
            if let previous, sample.time - previous > 2 { segment += 1 }
            result.append(Point(id: index, time: sample.time, power: power, segment: segment)); previous = sample.time
        }
        return result
    }
    private var ceiling: Double { ResultChartLayout.ceiling(forPeak: points.map(\.power).max() ?? 0) }

    var body: some View {
        let bands = ResultChartModel.bands(for: session)
        let best = ResultChartModel.bestMinute(for: session)
        Chart {
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                RectangleMark(xStart: .value("Start", band.start / 60), xEnd: .value("End", band.end / 60), yStart: .value("Floor", 0), yEnd: .value("Ceiling", ceiling))
                    .foregroundStyle(Theme.secondary.opacity(index % 2 == 0 ? 0.10 : 0.18))
            }
            if let best {
                RectangleMark(xStart: .value("Start", best.start / 60), xEnd: .value("End", best.end / 60), yStart: .value("Floor", 0), yEnd: .value("Ceiling", ceiling))
                    .foregroundStyle(Theme.accent.opacity(0.24))
            }
            ForEach(points) { point in
                // The accent has 3:1 or more against the plot in both themes (tested); the default series colour did not.
                LineMark(x: .value("Minutes", point.time / 60), y: .value("Measured power", point.power), series: .value("Continuous signal", point.segment))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.25, lineJoin: .round))
            }
        }
        .chartYScale(domain: 0...ceiling)
        .chartXAxis { axis }
        .chartYAxis { axis }
        .chartXAxisLabel { Text("Minutes").foregroundStyle(Theme.secondary) }
        .chartYAxisLabel { Text("W").foregroundStyle(Theme.secondary) }
        .chartOverlay { proxy in labels(proxy: proxy, bands: bands, best: best) }
        .frame(height: 210)
        .accessibilityLabel("Recorded power from \(session.configuration.resolvedPowerSource.title) over time")
        .accessibilityValue(accessibilityValue(bands: bands, best: best))
    }

    private func labels(proxy: ChartProxy, bands: [ResultBand], best: ResultBand?) -> some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                ZStack(alignment: .topLeading) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                        if let start = proxy.position(forX: band.start / 60), let end = proxy.position(forX: band.end / 60),
                           let text = ResultChartLayout.fittingLabel(for: band.title, availableWidth: Double(end - start) - 8, characterWidth: phaseCharacterWidth) {
                            Text(text).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1).fixedSize()
                                .offset(x: plot.minX + start + 4, y: plot.minY + 2)
                        }
                    }
                    if let best, let start = proxy.position(forX: best.start / 60), let end = proxy.position(forX: best.end / 60),
                       let text = ResultChartLayout.fittingLabel(for: best.title, availableWidth: Double(plot.width) - 8, characterWidth: bestCharacterWidth) {
                        let width = ResultChartLayout.estimatedWidth(of: text, characterWidth: bestCharacterWidth) + 8
                        // Explicit CGFloat/Double conversions: Swift 6.1 (Xcode 16.4) cannot choose between the two operator overloads.
                        let centre: Double = Double(start + end) / 2
                        let leading: CGFloat = CGFloat(ResultChartLayout.clampedLeading(centre: centre, width: width, plotWidth: Double(plot.width)))
                        let top: CGFloat = plot.minY + CGFloat(rowHeight) + 2
                        Text(text).font(.caption.weight(.bold)).foregroundStyle(Theme.accent).lineLimit(1).fixedSize()
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                            .offset(x: plot.minX + leading, y: top)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func accessibilityValue(bands: [ResultBand], best: ResultBand?) -> String {
        var parts: [String] = []
        if !bands.isEmpty {
            parts.append(bands.map { "\($0.title) minute \(Int($0.start / 60)) to \(Int($0.end / 60))" }.joined(separator: ", "))
        }
        if let best { parts.append("\(best.title) between minute \(Int(best.start / 60)) and \(Int(best.end / 60))") }
        return parts.joined(separator: ". ")
    }

    private var axis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25))
            AxisTick().foregroundStyle(Theme.secondary)
            AxisValueLabel().foregroundStyle(Theme.secondary)
        }
    }
}
