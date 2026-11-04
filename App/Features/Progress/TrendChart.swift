import SwiftUI
import Charts
import FTPunkDomain

/// One colour per rider, one marker shape for real/debug results, one combined legend.
struct TrendChart: View {
    typealias Metric = TrendMetric
    let groups: [RiderHistoryGroup]
    let metric: Metric
    let includeDebug: Bool
    /// Stable rider order, so a rider keeps their colour when the rider filter changes.
    var riderOrder: [UUID] = []

    private var visible: [RiderHistoryGroup] { groups.filter { !points(for: $0).isEmpty } }
    private func points(for group: RiderHistoryGroup) -> [TestSession] {
        group.sessions.filter { metric.value($0) != nil && (includeDebug || !$0.isDemo) }.sorted { $0.startedAt < $1.startedAt }
    }
    private func color(_ group: RiderHistoryGroup) -> Color {
        Theme.riderColor(at: riderOrder.firstIndex(of: group.id) ?? groups.firstIndex { $0.id == group.id } ?? 0)
    }
    private var hasDebug: Bool { includeDebug && visible.contains { points(for: $0).contains(where: \.isDemo) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(visible) { group in
                    ForEach(points(for: group)) { session in
                        if let amount = metric.value(session) {
                            LineMark(x: .value("Date", session.startedAt), y: .value(metric.rawValue, amount),
                                     series: .value("Rider", group.id.uuidString))
                                .foregroundStyle(by: .value("Rider", group.id.uuidString))
                            PointMark(x: .value("Date", session.startedAt), y: .value(metric.rawValue, amount))
                                .foregroundStyle(by: .value("Rider", group.id.uuidString))
                                .symbol(by: .value("Data", session.isDemo ? "Debug" : "Real"))
                                .accessibilityLabel("\(group.name), \(session.isDemo ? "debug" : "real"), \(session.startedAt.formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityValue("\(amount.formatted(.number.precision(.fractionLength(metric == .watts ? 0 : 2)))) \(metric.rawValue)")
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: visible.map { $0.id.uuidString }, range: visible.map { color($0) })
            .chartSymbolScale(["Real": BasicChartSymbolShape.circle, "Debug": BasicChartSymbolShape.diamond])
            .chartLegend(.hidden)
            .chartXAxis { axis }
            .chartYAxis { axis }
            .chartYAxisLabel { Text(metric.rawValue).foregroundStyle(Theme.secondary) }
            .frame(height: 210)
            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metric.rawValue) history by rider")
        .accessibilityHint("Dated values are also available in the activity list below.")
    }

    private var axis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25))
            AxisTick().foregroundStyle(Theme.secondary)
            AxisValueLabel().foregroundStyle(Theme.secondary)
        }
    }

    /// Colour identifies the rider; shape identifies real or debug data.
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(visible) { group in
                Label(group.name, systemImage: "circle.fill").foregroundStyle(color(group))
                    .labelStyle(LegendLabelStyle())
            }
            Label("Real result", systemImage: "circle").labelStyle(LegendLabelStyle())
            if hasDebug { Label("Debug result", systemImage: "diamond").labelStyle(LegendLabelStyle()) }
        }
        .font(.caption).foregroundStyle(Theme.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legend. Colour shows the rider. Circles are real results\(hasDebug ? ", diamonds are debug results" : "").")
    }
}

private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon; configuration.title.foregroundStyle(Theme.secondary) }
    }
}
