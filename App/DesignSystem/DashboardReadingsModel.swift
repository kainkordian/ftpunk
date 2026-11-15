import SwiftUI
import FTPunkDomain

@MainActor final class DashboardReadingsModel: ObservableObject {
    let readings = LiveWorkoutReadings()
    private var summaryRevision: SummaryChartCache.Revision?
    private var summaryValue: RideSummary?
    func summary(session: TestSession) -> RideSummary {
        let revision = SummaryChartCache.Revision(session)
        if summaryRevision == revision, let summaryValue { return summaryValue }
        let value = RideSummary.make(session)
        summaryRevision = revision; summaryValue = value
        return value
    }
    init(session: TestSession, time: Double) { readings.update(session: session, at: time) }
    func update(session: TestSession, time: Double) {
        objectWillChange.send()
        readings.update(session: session, at: time)
    }
    struct Revision: Equatable {
        let recording: SummaryChartCache.Revision
        let time: Double
        init(session: TestSession, time: Double) { recording = .init(session); self.time = time }
    }
}
