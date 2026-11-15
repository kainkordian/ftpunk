import SwiftUI
import Charts
import FTPunkDomain

struct CombinedRideChart: View {
    let session: TestSession
    let hover: RideChartHover
    var height = 360.0
    @StateObject private var model: SummaryChartModel
    init(session: TestSession, hover: RideChartHover, height: Double = 360) {
        self.session = session; self.hover = hover; self.height = height
        _model = StateObject(wrappedValue: SummaryChartModel(session: session))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { title; Spacer(); legend }
                VStack(alignment: .leading, spacing: 8) { title; ScrollView(.horizontal, showsIndicators: false) { legend } }
            }
            SummaryHoverReadout(session: session, hover: hover)
            SummaryPlot(session: session, data: model.cache.data, hover: hover, height: height).equatable()
            .accessibilityLabel("Recorded power and heart rate with target power and the best minute shaded")
        }.padding(.horizontal, 24).padding(.vertical, 20).ftpCard(fill: 0)
            .onChange(of: SummaryChartCache.Revision(session)) { _, _ in model.update(session) }
    }
    private var title: some View { Text("Power and heart rate").ftpText(.headline, weight: .bold) }
    private var legend: some View {
        HStack(spacing: 20) {
            key("Power", color: Theme.accent); key("Target", color: Theme.secondary, dashed: true); key("Heart rate", color: Theme.heart)
            if session.configuration.resolvedPowerSource == .externalPowerMeter { key("Trainer", color: Theme.cyan) }
            if session.result != nil { key("Best minute", color: Theme.accent.opacity(0.4)) }
        }.fixedSize()
    }
    private func key(_ title: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 22, height: dashed ? 2 : 4)
            Text(title).ftpText(.callout).foregroundStyle(Theme.secondary)
        }.accessibilityHidden(true)
    }
}

private struct SummaryHoverReadout: View {
    let session: TestSession
    let hover: RideChartHover
    var body: some View {
        // The overlay has no intrinsic size: changing text cannot resize the card or chart.
        Color.clear.frame(height: 22).overlay(alignment: .leading) {
            GeometryReader { geometry in
            HStack(spacing: 16) {
                if let time = hover.time {
                    let moment = RideMoment.at(session, time: time)
                    Text(clockText(time)).monospacedDigit()
                    Text(moment.power.map { "Power \(Int($0.rounded())) W" } ?? "Power —")
                    Text(moment.heartRate.map { "Heart rate \($0) bpm" } ?? "Heart rate —").foregroundStyle(Theme.heart)
                    Text(moment.target.map { "Target \($0) W" } ?? "")
                } else { Text("Hover or touch the chart for readings").foregroundStyle(Theme.secondary) }
            }.ftpText(.footnote).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: geometry.size.width, height: 22, alignment: .leading).clipped()
            }
        }.allowsHitTesting(false)
    }
}

@MainActor private final class SummaryChartModel: ObservableObject {
    let cache: SummaryChartCache
    init(session: TestSession) { cache = SummaryChartCache(session: session) }
    func update(_ session: TestSession) {
        guard cache.revision != SummaryChartCache.Revision(session) else { return }
        objectWillChange.send()
        cache.update(session: session)
    }
}

private struct SummaryPlot: View, Equatable {
    let session: TestSession
    let data: SummaryChartData
    let hover: RideChartHover
    let height: Double
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.data.id == rhs.data.id && lhs.height == rhs.height && lhs.hover === rhs.hover
    }
    var body: some View {
        Chart {
                if let result = session.result {
                    RectangleMark(xStart: .value("Start", result.windowStart / 60), xEnd: .value("End", result.windowEnd / 60), yStart: .value("Zero", 0), yEnd: .value("Power", data.ceiling))
                        .foregroundStyle(Theme.accent.opacity(0.16))
                }
                ForEach(data.power) { point in
                    LineMark(x: .value("Time", point.time / 60), y: .value("Power", point.value), series: .value("Series", "power\(point.segment)"))
                        .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                ForEach(data.heart) { point in
                    LineMark(x: .value("Time", point.time / 60), y: .value("Heart", point.value), series: .value("Series", "heart\(point.segment)"))
                        .foregroundStyle(Theme.heart).lineStyle(StrokeStyle(lineWidth: 2))
                }
                if session.configuration.resolvedPowerSource == .externalPowerMeter {
                    ForEach(data.trainer) { point in
                        LineMark(x: .value("Time", point.time / 60), y: .value("Trainer", point.value), series: .value("Series", "trainer\(point.segment)"))
                            .foregroundStyle(Theme.cyan).lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                ForEach(data.target) { point in
                    LineMark(x: .value("Time", point.time / 60), y: .value("Target", point.value), series: .value("Series", "target\(point.segment)"))
                        .foregroundStyle(Theme.secondary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                }
            }
            .chartXScale(domain: 0...(data.end / 60)).chartYScale(domain: 0...data.ceiling).chartLegend(.hidden)
            .chartXAxis { AxisMarks { value in AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.15)); AxisValueLabel { Text(clockText((value.as(Double.self) ?? 0) * 60)).ftpText(.caption) } } }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.15)); AxisValueLabel() }
                AxisMarks(position: .trailing, values: data.heartTicks) { value in
                    AxisValueLabel { Text("\(data.heartBPM(at: value.as(Double.self) ?? 0)) bpm").foregroundStyle(Theme.heart).ftpText(.caption) }
                }
            }
            .chartOverlay { proxy in RideChartHoverOverlay(proxy: proxy, session: session, hover: hover, chart: "summary") }
            .frame(height: height)
    }
}
