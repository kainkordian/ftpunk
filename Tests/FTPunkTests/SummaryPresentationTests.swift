import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

@Test func perStepPowerAndHeartRateExcludePausedSamples() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Two steps", steps: [.init("A", seconds: 5, watts: 100), .init("B", seconds: 5, watts: 200)])
    var engine = RideEngine(configuration: try SessionConfiguration(), training: plan)
    for second in 0...12 {
        let paused = (3..<6).contains(second)
        engine.receive(.init(time: Double(second), power: paused ? 1000 : second < 8 ? 100 : 200, cadence: 80, heartRate: paused ? 220 : second < 8 ? 120 : 140))
        engine.tick(at: Double(second))
        if second == 3 { _ = engine.pause(at: 3) }
        if second == 6 { _ = engine.resume(at: 6) }
    }
    let values = StepRideAverages.make(session: engine.session)
    #expect(values.map(\.name) == ["A", "B"])
    #expect(values[0].power == 100 && values[0].heartRate == 120)
    #expect(values[1].power == 200 && values[1].heartRate == 140)
    #expect(values[1].target == "200 W" && values[1].seconds == 5)
    #expect(RideChartDomain.end(session: engine.session) == 12)
}

@Test func trendIncludesManualAndSyncedSettingsAndHidesDebugActivitiesOnRequest() throws {
    var rider = RiderProfile(name: "Rider", ftpHistory: [.init(watts: 200, source: "Manual"), .init(watts: 210, source: "Intervals.icu"), .init(watts: 215, source: "Ramp test")])
    rider.currentFTPID = rider.ftpHistory[0].id
    #expect(Set(FTPTrendReadings.settings(profile: rider).map(\.watts)) == [200, 210])
    let real = TestSession(configuration: try SessionConfiguration())
    let demo = TestSession(configuration: try SessionConfiguration(), isDemo: true)
    #expect(ProgressRules.activities([real, demo], rider: nil, filter: .all, includeDebug: false).map(\.id) == [real.id])
    #expect(ProgressRules.activities([real, demo], rider: nil, filter: .all, includeDebug: true).count == 2)
}

@Test func shellTextColoursContrastOnAllThreeSurfaces() {
    for dark in [false, true] {
        let text = dark ? Theme.textPair.dark : Theme.textPair.light
        for pair in [Theme.groundPair, Theme.cardPair, Theme.raisedPair] {
            #expect(text.contrast(with: dark ? pair.dark : pair.light) >= 4.5)
        }
    }
}

@Test @MainActor func appReferenceScenariosRemainIsolatedAndMatchTheReferenceEstimate() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.appHome, to: model)
    #expect(model.profile.name == "Kordian" && model.workoutLibrary.count == 7)
    #expect(model.catalog.syncMessage == "7 cycling workouts with % FTP targets synced")
    try await PreviewScenarios.apply(.appSummary, to: model)
    let session = try #require(model.engine?.session)
    #expect(session.result?.bestMinutePower == 290 && session.configuration.ftpFactor == 0.72)
    #expect(Int(try #require(session.result).estimatedFTP.rounded()) == 209 && session.endedAtOffset == 518)
    #expect(model.previewSummaryValues["Work"] == "101" && model.cockpitPresented)
    try await PreviewScenarios.apply(.appSettings, to: model)
    #expect(model.destination == .settings && model.previewSettingsAnchor == SettingsGroup.rideDisplay.rawValue)
}

@Test func trendMergesSettingsAndRampResultsInDateOrder() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var rider = RiderProfile(name: "Rider", weightKG: 50, ftpHistory: [.init(watts: 200, date: start, source: "Manual")])
    var session = TestSession(startedAt: start.addingTimeInterval(10), configuration: try SessionConfiguration(riderID: rider.id))
    session.result = try FTPAnalysis.calculate(samples: (0...60).map { PowerSample(time: Double($0), watts: 300) }, start: 0, end: 60, weightKG: 50, factor: 0.72)
    let values = FTPTrendReadings.series(profile: rider, sessions: [session], metric: .watts, includeDebug: false)
    #expect(values.map(\.value) == [200, 216] && values.map(\.kind) == [.setting, .ramp])
    #expect(FTPTrendReadings.series(profile: rider, sessions: [session], metric: .wattsPerKG, includeDebug: false).first?.value == 4)
    rider.weightKG = nil
    #expect(FTPTrendReadings.series(profile: rider, sessions: [session], metric: .wattsPerKG, includeDebug: false).count == 1)
}

@Test @MainActor func longSummaryCachesGeometryAcrossPointerAndLayoutUpdates() async throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    try await PreviewScenarios.apply(.appSummaryLong, to: model)
    var session = try #require(model.engine?.session)
    #expect(session.samples.count == 9647)
    #expect(session.samples.compactMap(\.heartRate).count == 3214)
    #expect(RideChartDomain.end(session: session) == 3240)
    let start = ContinuousClock.now
    let cache = SummaryChartCache(session: session)
    let buildDuration = start.duration(to: .now)
    let geometryID = cache.data.id
    #expect(cache.data.power.count == 9647 && cache.data.heart.count == 3214)
    #expect(cache.data.ceiling >= 230 && cache.data.heartTop == 180)
    #expect(!cache.data.target.isEmpty)
    for point in cache.data.heart {
        let original = try #require(session.samples[point.id].heartRate)
        #expect(abs(Double(cache.data.heartBPM(at: point.value)) - Double(original)) <= 1)
    }
    // A sweep over a 54-minute chart must reuse its recording geometry. Neither
    // hover time nor the proposed card size is part of the cache's identity.
    for _ in 0..<1000 { #expect(!cache.update(session: session)) }
    #expect(cache.buildCount == 1 && cache.data.id == geometryID)
    print("Long summary geometry build: \(buildDuration); 3,214 HR projections and 1,000 unchanged updates: \(start.duration(to: .now))")
    session.samples.append(.init(time: 3241, power: 500, heartRate: 190))
    session.endedAtOffset = 3241
    #expect(cache.update(session: session))
    #expect(cache.buildCount == 2 && cache.data.id != geometryID && cache.data.heartTop == 200)
    #expect(cache.data.ceiling == ResultChartLayout.ceiling(forPeak: 500))
}

@Test func chartGeometryPreservesSignalGapsAndRejectsNonfiniteValues() throws {
    var session = TestSession(configuration: try SessionConfiguration())
    session.samples = [.init(time: 0, power: 100, heartRate: 120), .init(time: 1, power: .nan),
                       .init(time: 8, power: 200, heartRate: 150, trainerPower: 220)]
    let data = SummaryChartData(session: session)
    #expect(data.power.map(\.segment) == [0, 1])
    #expect(data.heart.map(\.segment) == [0, 1])
    #expect(data.power.map(\.value) == [100, 200])
    #expect(data.ceiling == ResultChartLayout.ceiling(forPeak: 220))
}

@Test func liveReadingsVisitAppendedSamplesOnceAndMatchFullRecordingRules() throws {
    var session = TestSession(configuration: try SessionConfiguration())
    session.training = try TrainingPlan(kind: .workout, name: "Long ride", steps: [.init("A", seconds: 1500, watts: 150), .init("B", seconds: 1800, watts: 200)])
    session.events = [.init(time: 0, message: WorkoutPhase.riding.title)]
    let readings = LiveWorkoutReadings()
    for second in 0...3240 {
        session.samples.append(.init(time: Double(second), power: Double(100 + second % 100), heartRate: 120 + second % 40))
        readings.update(session: session, at: Double(second))
    }
    #expect(readings.samplesVisited == session.samples.count)
    #expect(readings.recentPowerCount <= 63)
    for window in LivePower.windows {
        #expect(readings.power(at: 3240, window: window) == LivePower.average(samples: session.samples, at: 3240, window: window))
    }
    #expect(readings.stepHeartRates == StepHeartRate.averages(session: session))
    #expect(readings.heartRate.map(\.time) == WorkoutClock.heartRate(session).map(\.time))
    #expect(readings.heartRate.map(\.bpm) == WorkoutClock.heartRate(session).map(\.bpm))
    let visited = readings.samplesVisited
    for _ in 0..<100 { readings.update(session: session, at: 3240) }
    #expect(readings.samplesVisited == visited)
    #expect(readings.power(at: 3243, window: 3) == nil)
}

@Test func liveReadingsReplayOnClockChangesAndRecordingReplacement() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Two steps", steps: [.init("A", seconds: 5, watts: 100), .init("B", seconds: 10, watts: 200)])
    var engine = RideEngine(configuration: try SessionConfiguration(), training: plan)
    let readings = LiveWorkoutReadings()
    for second in 0...14 {
        engine.receive(.init(time: Double(second), power: Double(100 + second), cadence: 80, heartRate: 120 + second))
        engine.tick(at: Double(second))
        if second == 3 { _ = engine.pause(at: 3) }
        if second == 6 { _ = engine.resume(at: 6) }
        readings.update(session: engine.session, at: Double(second))
        #expect(readings.stepHeartRates == StepHeartRate.averages(session: engine.session))
        #expect(readings.heartRate.map(\.time) == WorkoutClock.heartRate(engine.session).map(\.time))
        for window in LivePower.windows {
            #expect(readings.power(at: Double(second), window: window) == LivePower.average(samples: engine.session.samples, at: Double(second), window: window, pauses: RidePause.list(engine.session)))
        }
    }
    let empty = TestSession(configuration: try SessionConfiguration())
    readings.update(session: empty, at: 0)
    #expect(readings.heartRate.isEmpty && readings.stepHeartRates.isEmpty && readings.power(at: 0, window: 3) == nil)
}

@Test func sharedControlLabelsContrastWithTheirLightAndDarkTracks() {
    #expect(Theme.segmentLabelPair.light.contrast(with: Theme.segmentTrackPair.light) >= 4.5)
    #expect(Theme.segmentLabelPair.dark.contrast(with: Theme.segmentTrackPair.dark) >= 4.5)
    #expect(Theme.textPair.light.contrast(with: Theme.raisedPair.light) >= 4.5)
    #expect(Theme.textPair.dark.contrast(with: Theme.raisedPair.dark) >= 4.5)
}
