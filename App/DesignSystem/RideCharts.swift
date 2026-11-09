import SwiftUI
import Charts
import FTPunkDomain

/// What a finished ride shows: the figures, then recorded power with its target, then heart rate when it was recorded.
struct RideCharts: View {
    let session: TestSession
    private var hasHeartRate: Bool { session.samples.contains { $0.heartRate != nil } }
    private var hasTarget: Bool { !TargetSeries.make(session).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ResultPowerChart(session: session)
            legend
            if hasHeartRate { RideHeartRateChart(session: session) }
            if let balance = RideBalance.make(session), balance.series().count >= 2 { RideBalanceChart(balance: balance) }
        }
    }

    private var legend: some View {
        HStack(spacing: Space.m) {
            swatch("Power", color: Theme.accent, dashed: false)
            if hasTarget { swatch("Target", color: .primary.opacity(0.75), dashed: true) }
            if hasHeartRate { swatch("Heart rate", color: .pink, dashed: false) }
        }
        .font(.caption).foregroundStyle(Theme.secondary).accessibilityHidden(true)
    }
    private func swatch(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Path { $0.move(to: CGPoint(x: 0, y: 5)); $0.addLine(to: CGPoint(x: 18, y: 5)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2.25, dash: dashed ? [4, 3] : [])).frame(width: 18, height: 10)
            Text(title)
        }
    }
}

struct RideHeartRateChart: View {
    let session: TestSession
    private struct Point: Identifiable { let id: Int; let time: Double; let bpm: Int; let segment: Int }
    private var points: [Point] {
        var result: [Point] = [], segment = 0, previous: Double?
        for (index, sample) in session.samples.enumerated() {
            guard let bpm = sample.heartRate, bpm > 0 else { continue }
            if let previous, sample.time - previous > 5 { segment += 1 }
            result.append(Point(id: index, time: sample.time, bpm: bpm, segment: segment)); previous = sample.time
        }
        return result
    }

    var body: some View {
        let summary = RideSummary.make(session)
        Chart(points) { point in
            LineMark(x: .value("Minutes", point.time / 60), y: .value("Heart rate", point.bpm), series: .value("Continuous signal", "h\(point.segment)"))
                .foregroundStyle(.pink).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel { Text("Minutes").foregroundStyle(Theme.secondary) }
        .chartYAxisLabel { Text("bpm").foregroundStyle(Theme.secondary) }
        .chartXAxis { axis }.chartYAxis { axis }
        .frame(height: 130)
        .accessibilityLabel("Recorded heart rate over time")
        .accessibilityValue(summary.averageHeartRate.map { "Average \(Int($0.rounded())) beats per minute" + (summary.maximumHeartRate.map { ", maximum \($0)" } ?? "") } ?? "")
    }
    private var axis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25))
            AxisTick().foregroundStyle(Theme.secondary)
            AxisValueLabel().foregroundStyle(Theme.secondary)
        }
    }
}

/// Left/right balance as a diverging chart around an even 50 %: the left leg's share above the line, the right leg's below, smoothed over 30 seconds.
struct RideBalanceChart: View {
    let balance: RideBalance
    @Environment(\.colorScheme) private var colorScheme
    private var leftColor: Color { colorScheme == .dark ? Color(red: 0.145, green: 0.416, blue: 0.749) : Color(red: 0.165, green: 0.471, blue: 0.839) }
    private var rightColor: Color { colorScheme == .dark ? Color(red: 0.851, green: 0.349, blue: 0.149) : Color(red: 0.922, green: 0.408, blue: 0.204) }

    var body: some View {
        let points = balance.series(), reach = RideBalance.axisReach(points)
        let left = Int(balance.left.rounded())
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Text("Pedal balance").font(.caption.weight(.bold)).foregroundStyle(Theme.secondary)
                Spacer()
                key("Left \(left) %", color: leftColor)
                key("Right \(100 - left) %", color: rightColor)
            }
            Chart {
                ForEach(points, id: \.time) { point in marks(point) }
                RuleMark(y: .value("Even", 50.0)).foregroundStyle(Theme.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: (50 - reach)...(50 + reach))
            .chartXAxisLabel { Text("Minutes").foregroundStyle(Theme.secondary) }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25))
                    AxisTick().foregroundStyle(Theme.secondary)
                    AxisValueLabel().foregroundStyle(Theme.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(values: [50 - reach, 50, 50 + reach]) { value in
                    AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25))
                    AxisValueLabel { Text(Self.label(value.as(Double.self) ?? 50)).foregroundStyle(Theme.secondary) }
                }
            }
            .frame(height: 130)
            .accessibilityLabel("Pedal balance over time")
            .accessibilityValue("Left \(left) percent, right \(100 - left) percent overall")
        }
    }

    @ChartContentBuilder private func marks(_ point: RideBalance.Point) -> some ChartContent {
        let minutes: Double = point.time / 60
        AreaMark(x: .value("Minutes", minutes), yStart: .value("Even", 50.0), yEnd: .value("Left", max(point.left, 50.0)), series: .value("Part", "L\(point.segment)"))
            .foregroundStyle(leftColor.opacity(0.6))
        AreaMark(x: .value("Minutes", minutes), yStart: .value("Even", 50.0), yEnd: .value("Right", min(point.left, 50.0)), series: .value("Part", "R\(point.segment)"))
            .foregroundStyle(rightColor.opacity(0.6))
        LineMark(x: .value("Minutes", minutes), y: .value("Left share", point.left), series: .value("Part", "B\(point.segment)"))
            .foregroundStyle(.primary).lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    private func key(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12)
            Text(title).font(.caption).foregroundStyle(Theme.secondary).monospacedDigit()
        }
    }
    private static func label(_ value: Double) -> String {
        value > 50 ? "L \(Int(value))" : value < 50 ? "R \(Int(100 - value))" : "50"
    }
}

/// Average and normalized power, heart rate and cadence for a finished ride. Figures that were not recorded are left out.
struct RideSummaryCard: View {
    let session: TestSession
    private func energyItems(_ summary: RideSummary) -> [(String, String)] {
        var items: [(String, String)] = []
        if let kilojoules = summary.kilojoules { items.append(("Energy", RideFigures.kilojoules(kilojoules))) }
        if let kilocalories = summary.kilocalories { items.append(("Estimated calories", "\(Int(kilocalories.rounded())) kcal")) }
        if let distance = summary.distance { items.append(("Simulated distance", "\(RideFigures.kilometres(distance)) km")) }
        if let left = summary.leftBalance { items.append(("Left / right", "\(RideFigures.balance(left)) %")) }
        return items
    }
    var body: some View {
        let summary = RideSummary.make(session)
        let showsPower = session.training?.resistance == nil
        let items: [(String, String)] = [
            ("Time", DurationFormat.clock(summary.duration)),
            showsPower ? summary.averagePower.map { ("Average power", "\(Int($0.rounded())) W") } : nil,
            showsPower ? summary.normalizedPower.map { ("Normalized power", "\(Int($0.rounded())) W") } : nil,
            summary.averageHeartRate.map { ("Average heart rate", "\(Int($0.rounded())) bpm") },
            summary.maximumHeartRate.map { ("Max heart rate", "\($0) bpm") },
            summary.averageCadence.map { ("Average cadence", "\(Int($0.rounded())) rpm") },
        ].compactMap { $0 }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: Space.m) {
            ForEach(items + energyItems(summary), id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
                    Text(value).font(.title3.bold()).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).ftpCard(fill: 0.05)
        .accessibilityIdentifier("ride-summary")
    }
}

/// The live "Power over time" chart in the cockpit, as in the web app: measured power over the last ten minutes with the
/// target as a dashed line. It reads the running session, so it follows the ride.
struct LivePowerChart: View {
    let session: TestSession
    private static let window = 600.0
    private struct Point: Identifiable { let id: Int; let time: Double; let power: Double; let segment: Int }

    var body: some View {
        let end = max(60, session.samples.last?.time ?? 0), start = max(0, end - Self.window)
        let points = visiblePoints(from: start)
        let targets = TargetSeries.make(session, from: start)
        let peak = max(200, points.map(\.power).max() ?? 0, targets.map(\.watts).max() ?? 0)
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Power over time").font(.headline)
                Spacer()
                Text("Last 10 minutes").font(.caption).foregroundStyle(Theme.secondary)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Minutes", point.time / 60), y: .value("Measured power", point.power), series: .value("Continuous signal", "p\(point.segment)"))
                        .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2.25, lineJoin: .round))
                }
                ForEach(Array(targets.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Minutes", point.time / 60), y: .value("Target power", point.watts), series: .value("Continuous signal", "t\(point.segment)"))
                        .foregroundStyle(.primary.opacity(0.75)).lineStyle(StrokeStyle(lineWidth: 1.75, lineJoin: .round, dash: [5, 3]))
                }
            }
            .chartXScale(domain: (start / 60)...(end / 60))
            .chartYScale(domain: 0...(peak * 1.15))
            .chartXAxis { axis }.chartYAxis { axis }
            .chartYAxisLabel { Text("W").foregroundStyle(Theme.secondary) }
            .frame(height: 160)
            .accessibilityLabel("Measured power over the last ten minutes" + (targets.isEmpty ? "" : ", with the target power"))
            .accessibilityIdentifier("live-power-chart")
        }
        .padding(Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func visiblePoints(from start: Double) -> [Point] {
        var result: [Point] = [], segment = 0, previous: Double?
        for (index, sample) in session.samples.enumerated() where sample.time >= start {
            guard let power = sample.power, power.isFinite else { continue }
            if let previous, sample.time - previous > 2 { segment += 1 }
            result.append(Point(id: index, time: sample.time, power: power, segment: segment)); previous = sample.time
        }
        return result
    }

    private var axis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine().foregroundStyle(Theme.secondary.opacity(0.25))
            AxisTick().foregroundStyle(Theme.secondary)
            AxisValueLabel().foregroundStyle(Theme.secondary)
        }
    }
}
