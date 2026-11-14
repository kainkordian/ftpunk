import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

@Test func liveBestMinuteWaitsForRampCoverageAndKeepsEarlierMaximum() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 10))
    for halfSecond in 0...720 {
        let time = Double(halfSecond) / 2
        engine.receive(RideSample(time: time, power: time < 10 ? 900 : time < 120 ? 300 : 150, cadence: 90))
        engine.tick(at: time)
        if time < 70 { #expect(engine.liveBestMinutePower == nil) }
    }
    #expect(engine.liveBestMinutePower == 300)
    engine.finishRamp(at: 360)
    #expect(engine.liveBestMinutePower == engine.session.result?.bestMinutePower)
    #expect(engine.session.result?.bestMinutePower == 300)
}

@Test func liveMinuteCountsZerosAndNeverFillsAStaleGap() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    for second in 0...65 {
        engine.receive(RideSample(time: Double(second), power: second < 30 ? 0 : 200, cadence: 90))
        engine.tick(at: Double(second))
    }
    #expect(abs(try #require(engine.liveBestMinutePower) - 200 * 35 / 60) < 0.001)
    var missing = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    for second in 0...30 {
        missing.receive(RideSample(time: Double(second), power: 200, cadence: 90)); missing.tick(at: Double(second))
    }
    missing.tick(at: 33)
    #expect(missing.phase == .interrupted)
    #expect(missing.liveBestMinutePower == nil)
}

@Test func finalMinuteExcludesTheExhaustionConfirmationPeriod() throws {
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    for second in 0...75 {
        engine.receive(RideSample(time: Double(second), power: second < 70 ? 300 : 1000, cadence: second < 70 ? 90 : 30))
        engine.tick(at: Double(second))
        if second == 74 { #expect(try #require(engine.liveBestMinutePower) > 300) }
    }
    #expect(engine.session.outcome == .exhaustion)
    #expect(engine.liveBestMinutePower == 300)
    #expect(engine.session.result?.bestMinutePower == 300)
}

@Test @MainActor func debugToolsUnlockOnExactlyTenAboutActivations() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.hideDebugTools()
    #expect(!model.debugUnlocked && !model.demoMode)
    for _ in 0..<9 { model.tapAboutInfo() }
    #expect(model.aboutTapCount == 9)
    #expect(!model.debugUnlocked && !model.demoMode)
    model.tapAboutInfo()
    #expect(model.debugUnlocked && model.demoMode)
    model.hideDebugTools()
    #expect(!model.debugUnlocked && !model.demoMode && model.aboutTapCount == 0)
}

@Test @MainActor func unlockingDebugNeverSwitchesAnActiveRealSessionToMockInput() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.hideDebugTools()
    model.engine = RampEngine(configuration: try SessionConfiguration(), isDemo: false)
    for _ in 0..<10 { model.tapAboutInfo() }
    #expect(model.debugUnlocked)
    #expect(!model.demoMode)
    #expect(model.engine?.session.isDemo == false)
    model.hideDebugTools()
    #expect(model.debugUnlocked) // Cannot change sensor mode during an active test.
    model.engine = nil
}

@Test func primaryActionTextMeetsContrastMinimumInBothAppearances() {
    #expect(ActionRGB(red: 1, green: 1, blue: 1).contrast(with: PrimaryActionPalette.controlBackground) >= 4.5)
    for dark in [false, true] {
        let colors = PrimaryActionPalette.colors(dark: dark)
        #expect(colors.foreground.contrast(with: colors.background) >= 4.5)
    }
}

@Test func riderSeriesColoursStayDistinguishableOnBothBackgrounds() {
    let white = ActionRGB(red: 1, green: 1, blue: 1), black = ActionRGB(red: 0.06, green: 0.06, blue: 0.06)
    for (index, pair) in Theme.riderPalette.enumerated() {
        #expect(pair.light.contrast(with: white) >= 3, "light rider colour \(index)")
        #expect(pair.dark.contrast(with: black) >= 3, "dark rider colour \(index)")
    }
    #expect(Theme.riderPalette.count == 6)
}

@Test func settingsAreGroupedAsPlannedAndDebugStaysHiddenUntilUnlocked() {
    #expect(SettingsGroup.visible(debugUnlocked: false).map(\.title) ==
            ["Riders", "Devices", "Ride screen", "Intervals.icu", "Backup & transfer", "About"])
    #expect(SettingsGroup.visible(debugUnlocked: true).contains(.debug))
    #expect(SettingsGroup.visible(debugUnlocked: true).map(\.title).last == "About")
    #expect(SettingsTopic.powerMatching.paragraphs.count == 3)
}
