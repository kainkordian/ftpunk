import SwiftUI
import Charts
import FTPunkDomain

/// One chronological line per rider; marker fill distinguishes results from FTP settings.
struct TrendChart: View {
    let groups: [RiderHistoryGroup]
    let metric: TrendMetric
    let includeDebug: Bool
    var riderOrder: [UUID] = []
    var profiles: [RiderProfile] = []
    private var allProfiles: [RiderProfile] {
        let known = Set(profiles.map(\.id))
        return profiles + groups.filter { !known.contains($0.id) }.map { RiderProfile(id: $0.id, name: $0.name) }
    }
    private func points(_ profile: RiderProfile) -> [FTPTrendPoint] {
        FTPTrendReadings.series(profile: profile, sessions: groups.flatMap(\.sessions), metric: metric, includeDebug: includeDebug)
    }
    private func color(_ profile: RiderProfile) -> Color { Theme.riderColor(at: riderOrder.firstIndex(of: profile.id) ?? 0) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(allProfiles) { profile in
                    ForEach(points(profile)) { point in
                        LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value), series: .value("Rider", profile.id.uuidString))
                            .foregroundStyle(color(profile))
                        PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                            .foregroundStyle(color(profile))
                            .symbol {
                                if point.kind == .setting { Circle().strokeBorder(color(profile), lineWidth: 2).frame(width: 10, height: 10) }
                                else if point.kind == .debug { Rectangle().fill(color(profile)).frame(width: 8, height: 8).rotationEffect(.degrees(45)) }
                                else { Circle().fill(color(profile)).frame(width: 8, height: 8) }
                            }
                            .accessibilityLabel("\(profile.name), \(point.source), \(point.date.formatted(date: .abbreviated, time: .omitted))")
                            .accessibilityValue("\(point.value.formatted(.number.precision(.fractionLength(metric == .watts ? 0 : 2)))) \(metric.rawValue)")
                    }
                }
            }.chartLegend(.hidden).chartXAxis { axis }.chartYAxis { axis }.frame(height: 210)
            HStack(spacing: 18) {
                ForEach(allProfiles.filter { !points($0).isEmpty }) { profile in
                    Label(profile.name, systemImage: "circle.fill").foregroundStyle(color(profile))
                }
            }.ftpText(.caption)
            Text("● Ramp test   ○ Manual or synced FTP" + (includeDebug ? "   ◇ Debug ramp" : "")).ftpText(.caption).foregroundStyle(Theme.secondary)
            if metric == .wattsPerKG { Text("Manual and synced W/kg uses the rider’s current saved weight.").ftpText(.caption).foregroundStyle(Theme.secondary) }
        }.accessibilityElement(children: .contain).accessibilityLabel("\(metric.rawValue) history by rider")
    }
    private var axis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25)); AxisTick().foregroundStyle(Theme.secondary); AxisValueLabel().foregroundStyle(Theme.secondary)
        }
    }
}
