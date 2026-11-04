import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

private func ramp(_ seconds: Double, phase: Double? = nil, best: Double? = 290, warmup: Double = 60, cooldown: Double = 180) -> RideVisualInput.Ramp {
    .init(phaseSeconds: phase ?? seconds, warmupSeconds: warmup, cooldownSeconds: cooldown, stepSeconds: 12, rampSeconds: seconds, bestMinuteWatts: best)
}
private func rampState(power: Double?, cadence: Double? = 90, ftp: Double? = 250, seconds: Double = 168, phase: WorkoutPhase = .ramp, speed: Double = 1) -> RideVisualState {
    .make(.init(mode: .ftpTest, phase: phase, power: power, cadence: cadence, ftp: ftp, playbackSpeed: speed, ramp: ramp(seconds)))
}
private func workoutState(power: Double? = 250, step: RideVisualInput.Step, phase: WorkoutPhase = .riding, ftp: Double? = 250, cadence: Double? = 90) -> RideVisualState {
    .make(.init(mode: .workout, phase: phase, power: power, cadence: cadence, ftp: ftp, step: step))
}
private func step(index: Int = 2, count: Int = 9, watts: Double = 225, end: Double? = nil, seconds: Double = 300, remaining: Double = 120,
                  next: RideVisualInput.Step.Next? = nil) -> RideVisualInput.Step {
    .init(index: index, count: count, startWatts: watts, endWatts: end ?? watts, seconds: seconds, remaining: remaining, next: next)
}

// MARK: Intensity

@Test func theAvatarUsesTheProfileChartZonesAtEveryWattage() throws {
    for watts in stride(from: 20.0, through: 400, by: 1) {
        let plan = try TrainingPlan(kind: .workout, name: "One step", ftpWatts: 250, steps: [.init("Step", seconds: 60, watts: Int(watts))])
        let chartZone = try #require(WorkoutProfile.bars(for: plan)[0].zone)
        #expect(RideVisualState.zone(power: watts, ftp: 250) == chartZone, "\(watts) W")
    }
    for percent in 0...200 {
        #expect(RideVisualState.zone(power: Double(percent) * 2.5, ftp: 250) == IntensityZone.zone(forFraction: Double(percent) / 100))
    }
}

@Test func posturesDifferClearlyBetweenZones() {
    let expected: [(IntensityZone, RidePosture)] = [(.recovery, .upright), (.endurance, .hoods), (.tempo, .low), (.sweetSpot, .low), (.threshold, .drops), (.vo2max, .drops)]
    for (zone, posture) in expected { #expect(RideVisualState.posture(for: zone) == posture) }
    #expect(RideVisualState.posture(for: nil) == .hoods) // no FTP: the endurance pose
    func state(_ percent: Double) -> RideVisualState { rampState(power: 250 * percent / 100) }
    #expect(state(40).posture == .upright && state(65).posture == .hoods && state(80).posture == .low && state(91).posture == .low)
    #expect(state(100).posture == .drops && state(120).posture == .drops)
    // Trails grow with effort; only threshold and above sweat and show speed lines, and only VO2max throws sparks.
    let trails = IntensityZone.allCases.map { zone -> Int in
        RideVisualState.make(.init(mode: .freeERG, phase: .riding, power: Double([40, 65, 80, 91, 100, 120][zone.rawValue]) * 2.5, cadence: 90, ftp: 250)).trail.length
    }
    #expect(trails == trails.sorted() && Set(trails).count == 6)
    #expect(state(40).trail.dim && !state(65).trail.dim)
    #expect([40, 65, 80, 91].allSatisfy { !state(Double($0)).showsSweat && !state(Double($0)).showsSpeedLines })
    #expect(state(100).showsSweat && state(100).showsSpeedLines && !state(100).showsSparks)
    #expect(state(120).showsSweat && state(120).showsSpeedLines && state(120).showsSparks)
}

@Test func withoutAnFTPOrFreshPowerTheRiderIsNeutralButStillMoves() {
    for state in [rampState(power: 250, ftp: nil), rampState(power: nil), rampState(power: 250, ftp: 0)] {
        #expect(state.zone == nil && state.posture == .hoods && state.motion == .pedalling && state.worldSpeed > 0)
        #expect(state.accessibilitySummary == "Chaindance: steady effort, level 15")
    }
}

// MARK: Pedalling and speed

@Test func pedalPeriodFollowsMeasuredCadenceAndStaleOrZeroCadenceCoasts() {
    let steady = rampState(power: 200, cadence: 90)
    #expect(steady.motion == .pedalling && abs((steady.pedalPeriod ?? 0) - 60.0 / 90) < 1e-9)
    #expect(abs((rampState(power: 200, cadence: 60).pedalPeriod ?? 0) - 1) < 1e-9)
    for cadence in [Optional(0.0), 4.0, nil] {
        let state = rampState(power: 200, cadence: cadence)
        #expect(state.motion == .coasting && state.pedalPeriod == nil)
        #expect(state.worldSpeed > 0 && state.worldSpeed < rampState(power: 200).worldSpeed) // rolling, slower than pedalling
    }
    // Very high cadence is kept to what 12 frames a second can show.
    #expect((rampState(power: 200, cadence: 400).pedalPeriod ?? 0) >= 60.0 / 150)
}

@Test func withoutACadenceSourcePowerStandsInForCadence() {
    func state(power: Double?) -> RideVisualState {
        .make(.init(mode: .workout, phase: .riding, power: power, cadence: nil, cadenceAvailable: false, ftp: 250, step: step()))
    }
    #expect(state(power: 200).motion == .pedalling && abs((state(power: 200).pedalPeriod ?? 0) - 60 / RideVisualState.nominalCadence) < 1e-9)
    #expect(state(power: 0).motion == .coasting && state(power: nil).motion == .coasting)
}

@Test func worldSpeedFollowsClampedPowerAndIsScaledByDebugPlayback() {
    let speeds = [0.0, 100, 250, 400, 500].map { rampState(power: $0).worldSpeed }
    #expect(speeds == speeds.sorted() && Set(speeds).count == 5)
    #expect(rampState(power: 900).worldSpeed == rampState(power: 500).worldSpeed) // clamped
    let normal = rampState(power: 100), fast = rampState(power: 100, speed: 4), huge = rampState(power: 250, speed: 60)
    #expect(abs(fast.worldSpeed - normal.worldSpeed * 4) < 1e-9 && fast.animationRate == 4)
    #expect(huge.animationRate == RideVisualState.maximumAnimationRate && huge.worldSpeed <= 90)
    #expect(rampState(power: 250, speed: .nan).animationRate == 1 && rampState(power: 250, speed: 0.1).animationRate == 1)
    #expect(rampState(power: 500).rainSlant > rampState(power: 50).rainSlant) // rain slants more at speed
    #expect((0...1).contains(rampState(power: 500, speed: 4).rainSlant))
}

@Test func pausedRidersStopWithAFootDownAndAPausedSign() {
    let state = workoutState(power: nil, step: step(), phase: .paused, cadence: nil)
    #expect(state.motion == .footDown && state.worldSpeed == 0 && state.pedalPeriod == nil)
    #expect(state.sign == RideVisualSign(kind: .paused, text: "PAUSED") && state.accessibilitySummary == "Chaindance: paused")
    // A rider who is merely waiting to start is not paused.
    #expect(workoutState(power: nil, step: step(), phase: .waiting, cadence: nil).sign?.kind == .step)
}

// MARK: The FTP test: The Spire

@Test func theFTPTestRidesTheBoulevardThenClimbsThenFinishesOnTheRoofAndGlidesDown() {
    func state(_ phase: WorkoutPhase, ramp: RideVisualInput.Ramp, power: Double? = 150) -> RideVisualState {
        .make(.init(mode: .ftpTest, phase: phase, power: power, cadence: 90, ftp: 250, ramp: ramp))
    }
    let early = state(.warmup, ramp: ramp(0, phase: 5)), late = state(.warmup, ramp: ramp(0, phase: 50))
    #expect(early.world == .boulevard && late.world == .boulevard && late.spire > early.spire && state(.waiting, ramp: ramp(0, phase: 0)).world == .boulevard)
    #expect(state(.ramp, ramp: ramp(100)).world == .skyway && state(.ramp, ramp: ramp(100)).spire == 1)
    let finished = state(.cooldown, ramp: ramp(560, phase: 1))
    #expect(finished.world == .rooftop && finished.sign == RideVisualSign(kind: .finish, text: "LVL 47 · 290 W"))
    #expect(finished.accessibilitySummary == "Chaindance: ramp finished at level 47")
    let gliding = state(.cooldown, ramp: ramp(560, phase: 60))
    #expect(gliding.world == .descent && gliding.descent > 0 && gliding.descent < 1 && gliding.accessibilitySummary == "Chaindance: cooling down")
    #expect(state(.cooldown, ramp: ramp(560, phase: 179)).descent > gliding.descent)
    // The finish sign stays on screen as long as the finish lasts, and a ramp with no best minute shows the level alone.
    #expect(state(.completed, ramp: ramp(560, phase: 180)).world == .rooftop)
    #expect(state(.cooldown, ramp: ramp(560, phase: 1, best: nil)).sign?.text == "LVL 47")
    // A ride stopped before the ramp started has nothing to celebrate.
    #expect(state(.interrupted, ramp: ramp(0, phase: 3)).world == .boulevard && state(.interrupted, ramp: ramp(0, phase: 3)).sign == nil)
    // A short cool-down still gets its glide.
    #expect(state(.cooldown, ramp: ramp(560, phase: 4, cooldown: 10)).world == .descent)
}

@Test func theClimbIsEndlessAndNeverPredictsWhereTheRampEnds() {
    var previousLevel = 0
    for second in stride(from: 0.0, through: 6000, by: 7) {
        let state = rampState(power: 150 + second / 20, seconds: second)
        let level = Int(second / 12) + 1
        #expect(state.world == .skyway && state.spire == 1 && state.descent == 0)
        #expect(state.level == level && state.sign == RideVisualSign(kind: .level, text: "LVL \(level)") && level >= previousLevel)
        if let upcoming = state.upcoming { #expect(upcoming.key == level + 1 && upcoming.text == "LVL \(level + 1)" && upcoming.secondsUntil <= RideVisualState.levelPreviewSeconds) }
        previousLevel = level
    }
    // Two rides of very different length look the same at the same step, apart from the number on the sign.
    let a = rampState(power: 250, seconds: 168), b = rampState(power: 250, seconds: 168 + 12 * 400)
    #expect(a.zone == b.zone && a.posture == b.posture && a.world == b.world && a.worldSpeed == b.worldSpeed)
}

@Test func eachRampStepPreviewsItsLevelSignJustBeforeTheBoundary() {
    #expect(rampState(power: 200, seconds: 100).upcoming == nil) // 8 s into step 9
    let near = rampState(power: 200, seconds: 106)               // 2 s into the last 6 s
    #expect(near.level == 9 && near.upcoming?.text == "LVL 10" && near.upcoming?.kind == .level && abs((near.upcoming?.secondsUntil ?? 0) - 2) < 1e-9)
    let warmup = RideVisualState.make(.init(mode: .ftpTest, phase: .warmup, power: 130, cadence: 90, ftp: 250, ramp: ramp(0, phase: 56, warmup: 60)))
    #expect(warmup.upcoming?.text == "LVL 1" && warmup.upcoming?.key == 1)
    #expect(RideVisualState.make(.init(mode: .ftpTest, phase: .warmup, power: 130, cadence: 90, ftp: 250, ramp: ramp(0, phase: 20, warmup: 60))).upcoming == nil)
    #expect(rampState(power: 250, seconds: 156).accessibilitySummary == "Chaindance: threshold effort, level 14")
}

// MARK: Workouts and free rides

@Test func workoutDistrictsFollowTheStepsZoneAndRecoveriesAreCalm() {
    let recovery = workoutState(power: 120, step: step(watts: 125))
    #expect(recovery.district == RideVisualDistrict(kind: .residential, zone: .recovery) && recovery.glow < 1)
    let work = workoutState(power: 288, step: step(watts: 288))
    #expect(work.district == RideVisualDistrict(kind: .market, zone: .vo2max) && work.glow == 1)
    #expect(workoutState(power: 100, step: step(watts: 225), ftp: nil).district == RideVisualDistrict(kind: .market, zone: nil))
    // The district follows the step's target, the avatar follows the measured power.
    let lagging = workoutState(power: 120, step: step(watts: 288))
    #expect(lagging.district.zone == .vo2max && lagging.zone == .recovery)
}

@Test func rampedStepsBrightenGradually() {
    let glows = [0.0, 0.25, 0.5, 0.75, 1].map { workoutState(power: 150, step: step(index: 0, watts: 125, end: 175, seconds: 600, remaining: 600 * (1 - $0))).glow }
    #expect(glows == glows.sorted() && Set(glows).count == 5 && glows.first! < 0.5 && glows.last! == 1)
    // A cool-down ramp dims instead.
    let cool = [0.0, 0.5, 1].map { workoutState(power: 120, step: step(index: 8, watts: 150, end: 100, seconds: 300, remaining: 300 * (1 - $0))).glow }
    #expect(cool == cool.sorted(by: >))
}

@Test func theNextStepIsPreviewedTenSecondsAheadWithItsDistrict() {
    let next = RideVisualInput.Step.Next(seconds: 300, startWatts: 225, endWatts: 225)
    let early = workoutState(power: 225, step: step(remaining: 11, next: next)), soon = workoutState(power: 225, step: step(remaining: 9.5, next: next))
    #expect(early.upcoming == nil)
    #expect(soon.upcoming?.text == "NEXT 5:00 · 225 W" && soon.upcoming?.key == 3 && soon.upcoming?.kind == .step)
    #expect(soon.upcoming?.district == RideVisualDistrict(kind: .market, zone: .sweetSpot))
    let recovery = workoutState(step: step(remaining: 5, next: .init(seconds: 180, startWatts: 125, endWatts: 125)))
    #expect(recovery.upcoming?.district?.kind == .residential && recovery.upcoming?.text == "NEXT 3:00 · 125 W")
    #expect(workoutState(step: step(remaining: 5, next: nil)).upcoming == nil) // the last step has no next
    #expect(soon.sign == RideVisualSign(kind: .step, text: "STEP 3/9") && soon.level == 3)
    #expect(soon.accessibilitySummary == "Chaindance: sweet spot effort, step 3 of 9")
}

@Test func freeRidesShowAGateWithTheNewTargetOrLevel() {
    let erg = RideVisualState.make(.init(mode: .freeERG, phase: .riding, power: 140, cadence: 90, ftp: 250, target: 150))
    #expect(erg.sign == RideVisualSign(kind: .gate, text: "150 W") && erg.world == .boulevard && erg.upcoming == nil)
    let resistance = RideVisualState.make(.init(mode: .resistance, phase: .riding, power: 140, cadence: 90, ftp: 250, target: 100))
    #expect(resistance.sign == RideVisualSign(kind: .gate, text: "RES 10.0"))
    #expect(RideVisualState.make(.init(mode: .freeERG, phase: .paused, ftp: 250, target: 150)).sign?.kind == .paused)
}

// MARK: Smoothing and the toggle

@Test func powerIsAveragedOverThreeSecondsAndStaleReadingsAreIgnored() {
    let samples = (0...10).map { RideSample(time: Double($0), power: Double($0 % 2 == 0 ? 100 : 300), cadence: 90) }
    #expect(RideVisualSmoothing.power(samples, now: 10) == 200) // 7...10 s: 300, 100, 300, 100
    #expect(RideVisualSmoothing.power(samples, now: 11) == 500.0 / 3)
    #expect(RideVisualSmoothing.power(samples, now: 12.5) == nil) // newest reading is stale
    #expect(RideVisualSmoothing.power([], now: 1) == nil)
    let gaps = [RideSample(time: 8, power: nil), RideSample(time: 9, power: 200), RideSample(time: 10, power: nil)]
    #expect(RideVisualSmoothing.power(gaps, now: 10) == 200)
    #expect(RideVisualSmoothing.power([RideSample(time: 1, power: .infinity), RideSample(time: 2, power: 150)], now: 2) == 150)
}

@Test func theToggleIsOnByDefaultAndKeepsAnExplicitOffFromTheOldStelvioSwitch() throws {
    #expect(RideVisualPreference.resolve(stored: nil, legacy: nil))
    #expect(!RideVisualPreference.resolve(stored: nil, legacy: false))
    #expect(RideVisualPreference.resolve(stored: nil, legacy: true))
    #expect(!RideVisualPreference.resolve(stored: false, legacy: true) && RideVisualPreference.resolve(stored: true, legacy: false))

    let suite = "ftpunk.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(RideVisualPreference.load(from: defaults) && defaults.object(forKey: RideVisualPreference.key) == nil) // untouched: still the default
    defaults.set(false, forKey: RideVisualPreference.legacyKey)
    #expect(!RideVisualPreference.load(from: defaults))
    #expect(defaults.object(forKey: RideVisualPreference.key) as? Bool == false && defaults.object(forKey: RideVisualPreference.legacyKey) == nil)
    RideVisualPreference.save(true, to: defaults)
    #expect(RideVisualPreference.load(from: defaults)) // the new key wins from then on
    let other = try #require(UserDefaults(suiteName: suite + ".b"))
    defer { other.removePersistentDomain(forName: suite + ".b") }
    other.set(true, forKey: RideVisualPreference.legacyKey)
    #expect(RideVisualPreference.load(from: other) && other.object(forKey: RideVisualPreference.key) as? Bool == true)
}

@Test @MainActor func theCockpitToggleIsPartOfTheModelAndPreviewsStartWithItOn() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)
    #expect(model.rideVisualEnabled)
    model.rideVisualEnabled = false
    #expect(!model.rideVisualEnabled)
    try model.resetPreview()
    #expect(model.rideVisualEnabled) // a scenario starts from the default
}

// MARK: Motion bookkeeping

@Test func motionAccumulatesDistanceCranksAndAnnouncedSigns() {
    let moving = rampState(power: 250, cadence: 90)
    var motion = RideVisualMotion()
    for _ in 0..<10 { motion.advance(by: 0.1, state: moving) }
    #expect(abs(motion.distance - moving.worldSpeed) < 1e-9 && abs(motion.time - 1) < 1e-9)
    #expect(abs(motion.crankTurns - 1.5) < 1e-9) // 90 rpm for one second
    var paused = motion
    let stopped = workoutState(power: nil, step: step(), phase: .paused, cadence: nil)
    paused.advance(by: 0.2, state: stopped)
    #expect(paused.distance == motion.distance && paused.crankTurns == motion.crankTurns)
    var clamped = RideVisualMotion()
    clamped.advance(by: 100, state: moving); clamped.advance(by: .nan, state: moving); clamped.advance(by: -3, state: moving)
    #expect(abs(clamped.distance - moving.worldSpeed * 0.25) < 1e-9)
    // Debug playback speeds the scenery up and the crank, within what is readable.
    let slow = rampState(power: 100, cadence: 90), fast = rampState(power: 100, cadence: 90, speed: 4)
    var normal = RideVisualMotion(), quick = RideVisualMotion()
    normal.advance(by: 0.1, state: slow); quick.advance(by: 0.1, state: fast)
    #expect(quick.time > 0.39 && abs(quick.distance - normal.distance * 4) < 1e-9)
}

@Test func eachLevelAndStepSignIsAnnouncedOnceAndAlignsWithTheDistrictChange() {
    var motion = RideVisualMotion()
    let level = rampState(power: 250, seconds: 105)
    for _ in 0..<5 { motion.advance(by: 0.1, state: level) }
    #expect(motion.markers.map(\.text) == ["LVL 10"] && motion.markers[0].kind == .level)
    let sign = motion.markers[0]
    #expect(sign.worldX > motion.distance)
    for _ in 0..<5 { motion.advance(by: 0.1, state: level) }
    #expect(motion.markers.count == 1) // not announced again
    // Workout: a billboard, a gantry and a district that starts exactly at the gantry.
    var workout = RideVisualMotion()
    let next = RideVisualInput.Step.Next(seconds: 180, startWatts: 125, endWatts: 125)
    let approaching = workoutState(power: 288, step: step(watts: 288, remaining: 8, next: next))
    workout.advance(by: 0.1, state: approaching)
    #expect(workout.markers.map(\.kind) == [.billboard, .gantry] && workout.markers[0].text == "NEXT 3:00 · 125 W")
    let gantry = workout.markers[1]
    #expect(workout.district(atWorldX: gantry.worldX - 1)?.kind == .market && workout.district(atWorldX: gantry.worldX)?.kind == .residential)
    #expect(workout.markers[0].worldX < gantry.worldX)
    // When the step really changes the district is already there; nothing new is added.
    let after = workoutState(power: 130, step: step(index: 3, watts: 125, seconds: 180, remaining: 170))
    workout.advance(by: 0.1, state: after)
    #expect(workout.segments.count == 2)
    // A change nobody announced starts a district a little way ahead.
    var surprise = RideVisualMotion()
    surprise.advance(by: 0.1, state: workoutState(power: 250, step: step(watts: 250)))
    surprise.advance(by: 0.1, state: workoutState(power: 120, step: step(watts: 120)))
    #expect(surprise.segments.count == 2 && surprise.segments[1].district.kind == .residential && surprise.segments[1].startX > surprise.distance)
}

@Test func freeRideGatesAppearOnTargetChangesButNotAtTheStart() {
    func state(_ target: Int) -> RideVisualState { .make(.init(mode: .freeERG, phase: .riding, power: 140, cadence: 90, ftp: 250, target: target)) }
    var motion = RideVisualMotion()
    motion.advance(by: 0.1, state: state(150)); motion.advance(by: 0.1, state: state(150))
    #expect(motion.markers.isEmpty)
    motion.advance(by: 0.1, state: state(160))
    #expect(motion.markers.map(\.text) == ["160 W"] && motion.markers[0].kind == .gate)
    motion.advance(by: 0.1, state: state(160))
    #expect(motion.markers.count == 1)
}

@Test func markersAndOldDistrictsAreDroppedOnceBehindTheRider() {
    var motion = RideVisualMotion()
    let state = rampState(power: 250, seconds: 105)
    motion.advance(by: 0.1, state: state)
    let first = motion.markers[0]
    let rolling = rampState(power: 500)
    for _ in 0..<200 { motion.advance(by: 0.25, state: rolling) }
    #expect(!motion.markers.contains(first))
    #expect(motion.distance > first.worldX + 90)
}

// MARK: Layout constants

@Test func theStripKeepsAFixedShortAspect() {
    #expect(RideVisualRaster.width == 192 && RideVisualRaster.height == 60)
    #expect(Double(RideVisualRaster.width) / Double(RideVisualRaster.height) == 3.2) // 16:5
}
