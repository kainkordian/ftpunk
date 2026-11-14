import SwiftUI
import FTPunkDomain

struct WorkoutCockpitView: View {
    @Bindable var model: AppModel
    let engine: RampEngine
    var body: some View { RideDashboard(model: model, engine: engine) }
}

/// Every other ride figure, always on the dashboard: power (average, normalized, maximum), heart rate (average,
/// maximum), average cadence, work, calories, simulated speed and distance, and pedal balance when it is reported.
struct RideMoreReadings: View {
    let session: TestSession

    private struct Item: Identifiable {
        let caption: String, value: String?, unit: String, note: String?
        var id: String { caption }
    }
    private var items: [Item] {
        let summary = RideSummary.make(session), track = RideTrack.make(session)
        let ridden = !track.points.isEmpty
        let whole: (Double?) -> String? = { $0.map { String(Int($0.rounded())) } }
        var result = [
            Item(caption: "Avg power", value: whole(summary.averagePower), unit: "W", note: nil),
            Item(caption: "NP", value: whole(summary.normalizedPower), unit: "W", note: nil),
            Item(caption: "Max power", value: whole(summary.maximumPower), unit: "W", note: nil),
            Item(caption: "Avg HR", value: whole(summary.averageHeartRate), unit: "bpm", note: nil),
            Item(caption: "Max HR", value: summary.maximumHeartRate.map(String.init), unit: "bpm", note: nil),
            Item(caption: "Avg RPM", value: whole(summary.averageCadence), unit: "rpm", note: nil),
            Item(caption: "Work", value: ridden ? String(Int(track.kilojoules.rounded())) : nil, unit: "kJ", note: nil),
            Item(caption: "Calories", value: ridden ? String(Int(track.kilocalories.rounded())) : nil, unit: "kcal", note: "Est."),
            Item(caption: "Speed", value: ridden ? RideFigures.kilometresPerHour(track.speed(at: session.samples.last?.time ?? 0)) : nil, unit: "km/h", note: "Sim."),
            Item(caption: "Distance", value: ridden ? RideFigures.kilometres(track.distance) : nil, unit: "km", note: "Sim."),
        ]
        if let left = RideBalance.live(session.samples) {
            result.append(Item(caption: "Balance", value: RideFigures.balance(left), unit: "L/R", note: nil))
        }
        return result
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.m)], spacing: Space.m) {
            ForEach(items) { item in
                ChaindanceBox(caption: item.caption, corner: item.note) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        ChaindanceNumber(text: item.value ?? "—", size: 34)
                        if item.value != nil { Text(item.unit).chaindanceCaption() }
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(item.caption)
                .accessibilityValue(item.value.map { "\($0) \(item.unit)" + (item.note.map { ", \($0 == "Sim." ? "simulated" : "estimated")" } ?? "") } ?? "Not yet")
            }
        }
    }
}
