import SwiftUI
import FTPunkDomain

enum RideFigures {
    static func kilojoules(_ value: Double) -> String { "\(Int(value.rounded())) kJ" }
    static func kilometresPerHour(_ metresPerSecond: Double) -> String { String(format: "%.1f", metresPerSecond * 3.6) }
    static func kilometres(_ metres: Double) -> String { String(format: "%.2f", metres / 1000) }
    static func balance(_ left: Double) -> String { "\(Int(left.rounded())) / \(100 - Int(left.rounded()))" }
}

/// The small line above the readings: work done so far, and the switch between the main readings and the additional ones.
struct RideDashboardBar: View {
    let session: TestSession
    @Binding var showsMore: Bool

    var body: some View {
        let kilojoules = RideTrack.make(session).kilojoules
        HStack {
            Text(RideFigures.kilojoules(kilojoules)).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.secondary)
                .accessibilityLabel("\(Int(kilojoules.rounded())) kilojoules so far")
            Spacer()
            Button(showsMore ? "Main readings" : "More readings") { showsMore.toggle() }
                .font(.footnote.weight(.semibold)).buttonStyle(.borderless)
                .accessibilityIdentifier("dashboard-toggle")
        }
    }
}

/// The additional readings: simulated speed and distance, estimated calories, average power and, when the meter reports it, pedal balance.
struct RideExtraTiles: View {
    let session: TestSession
    var rows = false

    private struct Item: Identifiable {
        let title: String, value: String?, unit: String, symbol: String, caption: String?
        var id: String { title }
    }
    private var items: [Item] {
        let track = RideTrack.make(session)
        let speed = track.speed(at: session.samples.last?.time ?? 0)
        var result = [
            Item(title: "SPEED", value: track.points.isEmpty ? nil : RideFigures.kilometresPerHour(speed), unit: "km/h", symbol: "speedometer", caption: "Simulated"),
            Item(title: "DISTANCE", value: track.points.isEmpty ? nil : RideFigures.kilometres(track.distance), unit: "km", symbol: "road.lanes", caption: "Simulated"),
            Item(title: "CALORIES", value: track.points.isEmpty ? nil : String(Int(track.kilocalories.rounded())), unit: "kcal", symbol: "flame", caption: "Estimated"),
            Item(title: "AVG POWER", value: track.averagePower.map { String(Int($0.rounded())) }, unit: "W", symbol: "bolt", caption: nil),
        ]
        if let left = RideBalance.live(session.samples) {
            result.append(Item(title: "BALANCE", value: RideFigures.balance(left), unit: "L/R", symbol: "circle.lefthalf.filled", caption: nil))
        }
        return result
    }

    var body: some View {
        if rows {
            VStack(spacing: Space.s) {
                ForEach(items) { MetricRow(title: $0.title, value: $0.value, unit: $0.unit, symbol: $0.symbol, caption: $0.caption) }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: Space.m)], spacing: Space.m) {
                ForEach(items) { MetricTile(title: $0.title, value: $0.value, unit: $0.unit, symbol: $0.symbol, caption: $0.caption) }
            }
        }
    }
}
