import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

private func standingInput(mode: RideVisualMode = .workout, phase: WorkoutPhase = .riding, power: Double?, sprint: Double?, peak: Double? = nil,
                           weight: Double? = 75, ftp: Double? = 250, cadence: Double? = 100) -> RideVisualInput {
    .init(mode: mode, phase: phase, power: power, cadence: cadence, ftp: ftp,
          ramp: mode == .ftpTest ? .init(phaseSeconds: 120, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 120) : nil,
          step: mode == .workout ? .init(index: 1, count: 3, startWatts: 300, endWatts: 300, seconds: 60, remaining: 30) : nil,
          weightKG: weight, sprintPower: sprint, sprintPeak: peak ?? sprint)
}
private func stands(_ input: RideVisualInput) -> Bool { RideVisualState.make(input).posture == .standing }

@Test func aSprintAtSevenWattsPerKilogramStandsTheRiderUp() {
    // 75 kg: threshold 525 W.
    #expect(RideVisualState.standingThreshold(weightKG: 75, ftp: 250) == 525)
    #expect(stands(standingInput(power: 480, sprint: 560)))
    #expect(!stands(standingInput(power: 450, sprint: 500)))
    let sprinting = RideVisualState.make(standingInput(power: 480, sprint: 560))
    #expect(sprinting.accessibilitySummary.contains("sprinting out of the saddle") && sprinting.showsSparks && sprinting.showsSpeedLines)
    #expect(RidePosture.standing > RidePosture.drops)
}

@Test func hysteresisKeepsTheRiderUpJustBelowTheThreshold() {
    // A 560 W second within the last three, smoothed power still 540 W: stay up.
    #expect(stands(standingInput(power: 540, sprint: 520, peak: 560)))
    // Smoothed power fell below 85 % of the threshold (446 W): sit down.
    #expect(!stands(standingInput(power: 400, sprint: 420, peak: 560)))
    // No second reached the threshold: seated.
    #expect(!stands(standingInput(power: 540, sprint: 510, peak: 520)))
}

@Test func withoutAWeightTheThresholdIsOnePointSixTimesFTP() {
    #expect(RideVisualState.standingThreshold(weightKG: nil, ftp: 250) == 400)
    #expect(stands(standingInput(power: 380, sprint: 410, weight: nil)))
    #expect(!stands(standingInput(power: 360, sprint: 380, weight: nil)))
    // Neither weight nor FTP: never stand.
    #expect(RideVisualState.standingThreshold(weightKG: nil, ftp: nil) == nil)
    #expect(!stands(standingInput(power: 1500, sprint: 1500, weight: nil, ftp: nil)))
    #expect(RideVisualState.standingThreshold(weightKG: 0, ftp: 250) == 400)
}

@Test func theFTPTestKeepsTheRiderSeatedInWarmupAndRampButNotInTheCooldown() {
    #expect(!stands(standingInput(mode: .ftpTest, phase: .ramp, power: 650, sprint: 700)))
    #expect(!stands(standingInput(mode: .ftpTest, phase: .warmup, power: 650, sprint: 700)))
    #expect(stands(standingInput(mode: .ftpTest, phase: .cooldown, power: 650, sprint: 700)))
    #expect(stands(standingInput(mode: .freeERG, phase: .riding, power: 650, sprint: 700)))
    #expect(stands(standingInput(mode: .resistance, phase: .riding, power: 650, sprint: 700)))
}

@Test func coastingPausedOrStalePowerNeverStands() {
    #expect(!stands(standingInput(power: 700, sprint: 700, cadence: 0)))
    #expect(!stands(standingInput(phase: .paused, power: 700, sprint: 700)))
    #expect(!stands(standingInput(power: nil, sprint: nil)))
}

@Test func sprintSmoothingUsesOneSecondWindowsAndLooksBackThreeSeconds() {
    let samples = (0...10).map { RideSample(time: Double($0), power: $0 >= 8 ? 600 : 300) }
    #expect(RideVisualSmoothing.sprintPower(samples, now: 10) == 600)
    #expect(RideVisualSmoothing.power(samples, now: 10) == 525) // the three-second average lags
    #expect(RideVisualSmoothing.sprintPeak(samples, now: 10) == 600)
    // A sprint that ended 2 s ago is still the peak of the last three seconds, but no longer the current second.
    let after = samples + [RideSample(time: 11, power: 300), RideSample(time: 12, power: 300)]
    #expect(RideVisualSmoothing.sprintPower(after, now: 12) == 300)
    #expect(RideVisualSmoothing.sprintPeak(after, now: 12) == 600)
    #expect(RideVisualSmoothing.sprintPeak([], now: 5) == nil)
    #expect(RideVisualSmoothing.sprintPower(samples, now: 20) == nil) // stale
}

@Test func theStandingRiderIsDrawnHigherAtEveryCrankFrame() throws {
    let seated = RideVisualState.make(standingInput(power: 400, sprint: 400, cadence: 95))
    let up = RideVisualState.make(standingInput(power: 560, sprint: 600, cadence: 95))
    #expect(seated.posture == .drops && up.posture == .standing)
    func helmetTop(_ state: RideVisualState, crank: Double) -> Int? {
        let canvas = RideVisualRaster.pixels(RideVisualScene(state: state, motion: RideVisualMotion(distance: 40, time: 0.5, crankTurns: crank), animated: true))
        let helmet = Ink(255, 0, 154)
        for row in 0..<60 { for column in 30..<110 where canvas.ink(column, row) == helmet { return row } }
        return nil
    }
    for crank in [0.0, 0.25, 0.5, 0.75] {
        let high = try #require(helmetTop(up, crank: crank)), low = try #require(helmetTop(seated, crank: crank))
        #expect(high < low, "crank \(crank)")
    }
}

@Test func cockpitLayoutChoosesStripHeroAndSideBySide() {
    let off = CockpitLayout.make(phase: .riding, accessibilitySize: false)
    #expect(off.visual == .off && off.showsCoachingLine && !off.sideBySide)
    let strip = CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .strip, containerWidth: 1200)
    #expect(strip.visual == .strip && !strip.showsCoachingLine && !strip.sideBySide)
    let hero = CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .hero, containerWidth: 700)
    #expect(hero.visual == .hero && !hero.sideBySide)
    #expect(CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .hero, containerWidth: 900).sideBySide)
    #expect(!CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .hero, containerWidth: 899).sideBySide)
    #expect(!CockpitLayout.make(phase: .riding, accessibilitySize: false, rideVisual: .hero, containerWidth: 1200, regularWidthClass: false).sideBySide)
    // Accessibility sizes: the numbers come first, so the hero becomes the strip.
    let large = CockpitLayout.make(phase: .riding, accessibilitySize: true, rideVisual: .hero, containerWidth: 1200)
    #expect(large.visual == .strip && !large.sideBySide)
}

@Test func placementMigratesFromTheOldToggle() throws {
    #expect(RideVisualPreference.resolvePlacement(stored: nil, enabled: nil, legacy: nil) == .off)
    #expect(RideVisualPreference.resolvePlacement(stored: nil, enabled: true, legacy: nil) == .strip)
    #expect(RideVisualPreference.resolvePlacement(stored: nil, enabled: false, legacy: true) == .off)
    #expect(RideVisualPreference.resolvePlacement(stored: "hero", enabled: false, legacy: nil) == .hero)
    #expect(RideVisualPreference.resolvePlacement(stored: "nonsense", enabled: false, legacy: nil) == .off)
    let suite = "ftpunk.placement.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(RideVisualPreference.loadPlacement(from: defaults) == .off)
    #expect(RideVisualPreference.resolvePlacement(stored: "strip", enabled: false, legacy: nil) == .strip)
    defaults.set(false, forKey: RideVisualPreference.key) // an older build's "off"
    #expect(RideVisualPreference.loadPlacement(from: defaults) == .off)
    RideVisualPreference.savePlacement(.hero, to: defaults)
    #expect(RideVisualPreference.loadPlacement(from: defaults) == .hero && RideVisualPreference.load(from: defaults))
    #expect(RideVisualPlacement.off.next == .strip && RideVisualPlacement.strip.next == .hero && RideVisualPlacement.hero.next == .off)
    #expect(RideVisualBranding.name == "Chaindance")
}

@Test @MainActor func theOnOffSwitchKeepsTheChosenPlacement() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    model.rideVisualPlacement = .hero
    #expect(model.rideVisualEnabled)
    model.rideVisualEnabled = true
    #expect(model.rideVisualPlacement == .hero)
    model.rideVisualEnabled = false
    #expect(model.rideVisualPlacement == .off)
    model.rideVisualEnabled = true
    #expect(model.rideVisualPlacement == .strip)
}
