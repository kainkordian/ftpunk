import Foundation
import CoreGraphics
import Testing
import FTPunkDomain
import FTPunkDevices
@testable import FTPunkApp

private let helmet = Ink(255, 0, 154)

private func state(power: Double?, cadence: Double? = 92, ftp: Double? = 250, mode: RideVisualMode = .ftpTest, phase: WorkoutPhase = .ramp) -> RideVisualState {
    .make(.init(mode: mode, phase: phase, power: power, cadence: cadence, ftp: ftp,
                ramp: mode == .ftpTest ? .init(phaseSeconds: 360, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 360, bestMinuteWatts: 290) : nil,
                step: mode == .workout ? .init(index: 2, count: 9, startWatts: power ?? 0, endWatts: power ?? 0, seconds: 300, remaining: 150) : nil,
                target: mode == .freeERG ? 150 : mode == .resistance ? 100 : nil))
}
private func pixels(_ state: RideVisualState, distance: Double = 40, time: Double = 0.5, crank: Double = 0, animated: Bool = true, contrast: Bool = false) -> Pixels {
    RideVisualRaster.pixels(RideVisualScene(state: state, motion: RideVisualMotion(distance: distance, time: time, crankTurns: crank), animated: animated, highContrast: contrast))
}
private func count(_ ink: Ink, in canvas: Pixels, x: Range<Int> = 0..<192, y: Range<Int> = 0..<60) -> Int {
    var total = 0
    for row in y { for column in x where canvas.ink(column, row) == ink { total += 1 } }
    return total
}
private func differing(_ a: Pixels, _ b: Pixels, x: Range<Int> = 0..<192, y: Range<Int> = 0..<60) -> Int {
    var total = 0
    for row in y { for column in x where a.ink(column, row) != b.ink(column, row) { total += 1 } }
    return total
}

@Test func theRendererDrawsAFixedSizeImageForEveryModeWorldAndZone() throws {
    var seen = 0
    for percent in [30.0, 65, 80, 91, 100, 120] {
        for mode in [RideVisualMode.ftpTest, .workout, .freeERG, .resistance] {
            let image = try #require(RideVisualRaster.image(RideVisualScene(state: state(power: 250 * percent / 100, mode: mode, phase: mode == .ftpTest ? .ramp : .riding))))
            #expect(image.width == 192 && image.height == 60)
            seen += 1
        }
    }
    for (phase, seconds, phaseSeconds): (WorkoutPhase, Double, Double) in [(.waiting, 0, 0), (.warmup, 0, 30), (.cooldown, 560, 1), (.cooldown, 560, 90), (.completed, 560, 180), (.interrupted, 0, 4)] {
        let input = RideVisualInput(mode: .ftpTest, phase: phase, power: 150, cadence: 80, ftp: 250,
                                    ramp: .init(phaseSeconds: phaseSeconds, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: seconds, bestMinuteWatts: 290))
        #expect(RideVisualRaster.image(RideVisualScene(state: .make(input))) != nil)
    }
    let paused = RideVisualState.make(.init(mode: .workout, phase: .paused, ftp: 250, step: .init(index: 0, count: 3, startWatts: 200, endWatts: 200, seconds: 60, remaining: 30)))
    #expect(RideVisualRaster.image(RideVisualScene(state: paused)) != nil && seen == 24)
}

@Test func theHelmetAndTheZoneColourAreDrawnForEveryZone() {
    for zone in IntensityZone.allCases {
        let power = [40.0, 65, 80, 91, 100, 120][zone.rawValue] * 2.5
        let s = state(power: power)
        #expect(s.zone == zone)
        let canvas = pixels(s)
        #expect(count(helmet, in: canvas, x: 40..<100, y: 10..<50) >= 8, "helmet in \(zone)")
        // The jacket stripe is the shared chart colour for the zone, set exactly.
        let ink = Ink(ZonePalette.pair(for: zone).dark)
        #expect(count(ink, in: canvas, x: 40..<100, y: 10..<52) >= 2, "zone stripe in \(zone)")
        #expect(RideVisualPalette.zone(zone) == ink)
    }
    #expect(count(RideVisualPalette.cyan, in: pixels(state(power: nil)), x: 40..<100, y: 10..<52) > 0) // neutral cyan without power
}

@Test func theRidersPoseDiffersClearlyBetweenZones() {
    // On the level boulevard, so the climb's tilt does not squash the differences.
    func silhouette(_ percent: Double) -> Pixels { pixels(state(power: 250 * percent / 100, mode: .freeERG, phase: .riding), distance: 0, time: 0, crank: 0, animated: false) }
    let recovery = silhouette(40), endurance = silhouette(65), tempo = silhouette(80), threshold = silhouette(100), vo2 = silhouette(120)
    let rider = 44..<90, air = 12..<44
    // Upright, hoods, low and drops are four different head heights above the road.
    func headTop(_ canvas: Pixels) -> Int { (0..<60).first { row in rider.contains { canvas.ink($0, row) == Ink(255, 128, 204) } } ?? 0 } // the helmet's highlight
    let heads = [recovery, endurance, tempo, threshold].map(headTop)
    #expect(heads == heads.sorted() && heads.first! < heads.last! - 4, "head heights \(heads)")
    #expect(differing(recovery, endurance, x: rider, y: air) > 20 && differing(endurance, tempo, x: rider, y: air) > 20)
    #expect(differing(tempo, threshold, x: rider, y: 0..<60) > 40 && differing(threshold, vo2, x: 0..<192, y: 0..<60) > 0)
}

@Test func pedallingTurnsInFourFramesAndCoastingHoldsStill() {
    func frame(_ turns: Double, motion cadence: Double? = 90) -> Pixels { pixels(state(power: 200, cadence: cadence), crank: turns, animated: true) }
    let frames = (0..<4).map { frame(Double($0) / 4 + 0.01) }
    for i in 0..<4 { for j in (i + 1)..<4 { #expect(differing(frames[i], frames[j], x: 40..<85, y: 24..<52) > 3, "frames \(i) and \(j)") } }
    #expect(differing(frame(1.01), frames[0]) == 0) // a whole turn later is the same frame
    #expect(differing(frame(0.01, motion: nil), frame(0.6, motion: nil)) == 0) // coasting ignores the cranks
    #expect(differing(frame(0.01, motion: nil), frames[0], x: 40..<85, y: 24..<52) > 3)
}

@Test func reduceMotionDrawsASteadyPictureThatStillFollowsTheState() {
    let threshold = state(power: 250)
    let a = pixels(threshold, distance: 10, time: 0.2, crank: 0.3, animated: false)
    let b = pixels(threshold, distance: 700, time: 2.4, crank: 0.8, animated: false)
    #expect(differing(a, b) == 0) // no scrolling, parallax, rain or pedalling
    #expect(differing(a, pixels(threshold, distance: 10, time: 0.2, crank: 0.3, animated: true)) > 100)
    #expect(differing(a, pixels(state(power: 120), animated: false), x: 40..<100, y: 10..<52) > 20) // pose and colour still change with the zone
    let stepOne = RideVisualState.make(.init(mode: .ftpTest, phase: .ramp, power: 200, cadence: 90, ftp: 250, ramp: .init(phaseSeconds: 10, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 10, bestMinuteWatts: nil)))
    let stepTwo = RideVisualState.make(.init(mode: .ftpTest, phase: .ramp, power: 200, cadence: 90, ftp: 250, ramp: .init(phaseSeconds: 14, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 14, bestMinuteWatts: nil)))
    #expect(differing(pixels(stepOne, animated: false), pixels(stepTwo, animated: false)) > 5) // the static LVL sign changes with the step
}

@Test func increaseContrastAddsADarkOutlineAroundTheRider() {
    let s = state(power: 200)
    let plain = pixels(s, animated: false), outlined = pixels(s, animated: false, contrast: true)
    let dark = Ink(3, 3, 12)
    #expect(count(dark, in: plain) == 0 && count(dark, in: outlined, x: 30..<110, y: 10..<58) > 60)
    // The rider itself is unchanged underneath it.
    #expect(count(helmet, in: outlined) == count(helmet, in: plain))
}

@Test func theClimbIsEndlessBecauseTheSceneryRepeatsExactlyAndNeverCountsToAFinish() throws {
    let loop = RideVisualMotion.loopDistance, seconds = RideVisualMotion.loopTime
    for percent in [60.0, 100, 120] {
        let s = state(power: 250 * percent / 100)
        let a = pixels(s, distance: 120, time: 0.7, crank: 0.25)
        let b = pixels(s, distance: 120 + loop, time: 0.7 + seconds, crank: 0.25)
        let c = pixels(s, distance: 120 + loop * 7, time: 0.7 + seconds * 5, crank: 0.25 + 12)
        #expect(differing(a, b) == 0 && differing(a, c) == 0, "\(percent) % repeats")
        #expect(differing(a, pixels(s, distance: 160, time: 0.7, crank: 0.25)) > 100) // and moves in between
        #expect(differing(a, pixels(s, distance: 120, time: 1.0, crank: 0.25)) > 10)   // rain and blinking windows move with time
    }
    // Every ramp second of a long ramp is the same skyway; only the step number on the level sign changes.
    var engine = RampEngine(configuration: try SessionConfiguration(warmupSeconds: 0))
    for second in 0...200 {
        engine.receive(RideSample(time: Double(second), power: 200, cadence: 90)); engine.tick(at: Double(second))
        let input = RideVisualInput(mode: .ftpTest, phase: engine.phase, power: 200, cadence: 90, ftp: 250,
                                    ramp: .init(phaseSeconds: Double(second), warmupSeconds: 0, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: Double(second)))
        #expect(RideVisualState.make(input).world == .skyway && engine.phase == .ramp)
    }
}

@Test func districtsAndSignsChangeWhatTheBoulevardLooksLike() {
    let work = state(power: 288, mode: .workout, phase: .riding)
    var recovery = RideVisualMotion(distance: 40, time: 0.5, crankTurns: 0)
    recovery.advance(by: 0.1, state: state(power: 120, mode: .workout, phase: .riding))
    let calm = RideVisualState.make(.init(mode: .workout, phase: .riding, power: 120, cadence: 90, ftp: 250,
                                          step: .init(index: 1, count: 9, startWatts: 125, endWatts: 125, seconds: 180, remaining: 150)))
    let busy = RideVisualState.make(.init(mode: .workout, phase: .riding, power: 288, cadence: 90, ftp: 250,
                                          step: .init(index: 1, count: 9, startWatts: 288, endWatts: 288, seconds: 180, remaining: 150)))
    #expect(work.district.kind == .market && calm.district.kind == .residential)
    #expect(differing(pixels(calm, animated: false), pixels(busy, animated: false), x: 0..<192, y: 0..<48) > 200)
    // The paused sign and the finish sign are drawn where the plan says.
    let paused = RideVisualState.make(.init(mode: .workout, phase: .paused, ftp: 250, step: .init(index: 1, count: 9, startWatts: 288, endWatts: 288, seconds: 180, remaining: 150)))
    #expect(count(RideVisualPalette.amber, in: pixels(paused), x: 100..<190, y: 0..<20) > 30)
    let finish = RideVisualState.make(.init(mode: .ftpTest, phase: .cooldown, power: 120, cadence: 70, ftp: 250,
                                            ramp: .init(phaseSeconds: 1, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 560, bestMinuteWatts: 290)))
    #expect(finish.world == .rooftop && count(RideVisualPalette.lime, in: pixels(finish), x: 100..<190, y: 0..<30) > 30)
}

@Test func renderingNeverTrapsAtAnyDistanceTimeWorldOrPose() throws {
    var inputs: [RideVisualInput] = []
    for percent in [30.0, 65, 80, 91, 100, 130] {
        let power = 250 * percent / 100
        inputs.append(.init(mode: .ftpTest, phase: .ramp, power: power, cadence: 90, ftp: 250, ramp: .init(phaseSeconds: 700, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: 700, bestMinuteWatts: 290)))
        inputs.append(.init(mode: .workout, phase: .riding, power: power, cadence: 90, ftp: 250, step: .init(index: 1, count: 5, startWatts: power, endWatts: power + 30, seconds: 120, remaining: 5, next: .init(seconds: 60, startWatts: 150, endWatts: 150))))
    }
    for (phase, rampSeconds, phaseSeconds): (WorkoutPhase, Double, Double) in [(.waiting, 0, 0), (.warmup, 0, 59), (.cooldown, 560, 2), (.cooldown, 560, 100), (.completed, 560, 180), (.interrupted, 0, 1)] {
        inputs.append(.init(mode: .ftpTest, phase: phase, power: 100, cadence: 70, ftp: 250, ramp: .init(phaseSeconds: phaseSeconds, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: rampSeconds, bestMinuteWatts: 290)))
    }
    inputs.append(.init(mode: .workout, phase: .paused, ftp: nil, step: .init(index: 0, count: 1, startWatts: 100, endWatts: 100, seconds: 60, remaining: 30)))
    inputs.append(.init(mode: .freeERG, phase: .riding, power: 150, cadence: nil, cadenceAvailable: false, ftp: 250, playbackSpeed: 60, target: 150))
    inputs.append(.init(mode: .resistance, phase: .riding, power: nil, cadence: 80, ftp: nil, target: 1000))
    var frames = 0
    func render(_ state: RideVisualState, distance: Double) {
        let scene = RideVisualScene(state: state, motion: RideVisualMotion(distance: distance, time: distance / 40, crankTurns: distance / 30), animated: true, highContrast: Int(distance) % 2 == 0)
        #expect(RideVisualRaster.image(scene) != nil)
        frames += 1
    }
    // Every combination at a coarse stride, and three worlds at every few pixels, so a lamp or sign at either edge is hit.
    for input in inputs { for distance in stride(from: 0.0, to: 1600, by: 97) { render(.make(input), distance: distance) } }
    for index in [1, 0, 14] { for distance in stride(from: 0.0, to: 200, by: 3) { render(.make(inputs[index]), distance: distance) } }
    #expect(frames > 300)
}

/// FNV-1a over a frame's bytes.
private func fingerprint(_ canvas: Pixels) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in canvas.bytes { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return String(hash, radix: 16)
}
/// Frames that cover the boulevard, the skyway climb, the rooftop, the descent, a paused sign, rain, the outline and Reduce Motion.
private func stripReferenceFrames() -> [(String, Pixels)] {
    let ramp = { (phase: WorkoutPhase, rampSeconds: Double, phaseSeconds: Double, power: Double) in
        RideVisualState.make(.init(mode: .ftpTest, phase: phase, power: power, cadence: 90, ftp: 250,
                                   ramp: .init(phaseSeconds: phaseSeconds, warmupSeconds: 60, cooldownSeconds: 180, stepSeconds: 12, rampSeconds: rampSeconds, bestMinuteWatts: 290)))
    }
    let paused = RideVisualState.make(.init(mode: .workout, phase: .paused, ftp: 250, step: .init(index: 1, count: 9, startWatts: 288, endWatts: 288, seconds: 180, remaining: 150)))
    let motion = RideVisualMotion(distance: 123, time: 0.7, crankTurns: 0.25)
    func scene(_ state: RideVisualState, animated: Bool = true, contrast: Bool = false) -> RideVisualScene {
        RideVisualScene(state: state, motion: motion, animated: animated, highContrast: contrast)
    }
    return [
        ("boulevard", RideVisualRaster.pixels(scene(state(power: 150, mode: .workout, phase: .riding)))),
        ("skyway", RideVisualRaster.pixels(scene(ramp(.ramp, 360, 360, 250)))),
        ("skyway-high", RideVisualRaster.pixels(scene(ramp(.ramp, 700, 700, 330), contrast: true))),
        ("rooftop", RideVisualRaster.pixels(scene(ramp(.cooldown, 560, 1, 120)))),
        ("descent", RideVisualRaster.pixels(scene(ramp(.cooldown, 560, 90, 120)))),
        ("paused", RideVisualRaster.pixels(scene(paused))),
        ("still", RideVisualRaster.pixels(scene(state(power: 200), animated: false)))
    ]
}
@Test func theStripStaysPixelIdenticalToItsReferenceFrames() {
    // Recorded before the Large view got its taller raster: the strip must not change by a single pixel.
    let reference = ["boulevard": "11f0c31dcebdb23b", "skyway": "9d34af9f9cd02621", "skyway-high": "3eb575d9992c64a6", "rooftop": "41d8416dc95c6842",
                     "descent": "250e2f92a2df71f6", "paused": "ec1362d036bc6efb", "still": "c96cbc95545e9605"]
    let frames = stripReferenceFrames()
    #expect(frames.count == reference.count)
    for (name, frame) in frames {
        #expect(frame.width == 192 && frame.height == 60)
        #expect(fingerprint(frame) == reference[name], "\(name) changed")
    }
}

private func heroPixels(_ state: RideVisualState, animated: Bool = false, distance: Double = 40) -> Pixels {
    RideVisualRaster.pixels(RideVisualScene(state: state, motion: RideVisualMotion(distance: distance, time: 0.5, crankTurns: 0), animated: animated, skyRows: HeroLayout.skyRows))
}

@Test func theHeroRasterIsTallerAndOnlyTheSkyGrows() throws {
    #expect(RideVisualRaster.height == 60 && RideVisualRaster.heroHeight == 96 && HeroLayout.skyRows == 36)
    let s = state(power: 200, mode: .workout, phase: .riding)
    let strip = pixels(s, animated: false), hero = heroPixels(s, distance: 40)
    #expect(hero.width == 192 && hero.height == 96)
    let image = try #require(RideVisualRaster.image(RideVisualScene(state: s, skyRows: 36)))
    #expect(image.width == 192 && image.height == 96)
    // The road keeps its row offsets from the bottom edge: the rows below the skyline are the same pixels.
    var different = 0
    for row in 50..<60 { for column in 0..<192 where strip.ink(column, row) != hero.ink(column, row + 36) { different += 1 } }
    #expect(different == 0, "\(different) road pixels moved")
    // The extra rows are sky: they hold stars and a moon, and nothing the rider could be mistaken for.
    var lit = 0
    for row in 0..<36 { for column in 0..<192 where hero.ink(column, row) != Ink(8, 8, 28) { lit += 1 } }
    #expect(lit > 60, "stars, moon and tower tips: \(lit) lit pixels")
}

@Test func theRiderStaysBelowTheSkyBandInEveryPose() throws {
    // HeroLayout.readoutFraction is the share of the hero the readout may use, from the top: 36 of 96 rows.
    #expect(HeroLayout.readoutFraction == 36.0 / 96)
    for (percent, mode) in [(40.0, RideVisualMode.freeERG), (65, .freeERG), (80, .workout), (100, .workout), (120, .workout), (300, .freeERG)] {
        let s = state(power: 250 * percent / 100, mode: mode, phase: .riding)
        let stripRows = try #require(RideVisualRaster.riderRows(RideVisualScene(state: s, animated: false)))
        let heroRows = try #require(RideVisualRaster.riderRows(RideVisualScene(state: s, animated: false, skyRows: HeroLayout.skyRows)))
        #expect(heroRows.lowerBound == stripRows.lowerBound + 36, "\(percent) %: rider rows \(heroRows)")
        #expect(heroRows.lowerBound > HeroLayout.skyRows, "\(percent) %: the rider's top row \(heroRows.lowerBound) is inside the readout band")
    }
}

@Test func theHeroReadoutKeepsItsContrastAgainstTheSky() {
    let sky = ActionRGB(red: 10.0 / 255, green: 10.0 / 255, blue: 32.0 / 255)
    let white = ActionRGB(red: 1, green: 1, blue: 1)
    #expect(white.contrast(with: sky) >= 4.5)
    #expect(Theme.accentPair.dark.contrast(with: sky) >= 4.5) // the readout is always drawn in the dark scheme
    // The top rows of the real sky are that dark.
    let hero = heroPixels(state(power: 200, mode: .workout, phase: .riding))
    for column in stride(from: 0, to: 192, by: 16) { #expect(hero.ink(column, 0).r < 40 && hero.ink(column, 0).g < 40 && hero.ink(column, 0).b < 70) }
}

@Test @MainActor func deviceSubtitlesNoLongerRepeatTheBadge() {
    #expect(DeviceStatusRow.subtitle(role: .pedals, connectedName: nil, detail: nil) == "For power matching, or as the power source")
    #expect(DeviceStatusRow.subtitle(role: .heartRate, connectedName: nil, detail: nil) == "Heart rate on screen and in the file")
    #expect(DeviceStatusRow.subtitle(role: .trainer, connectedName: nil, detail: nil) == "Required to ride · tap to connect")
    #expect(DeviceStatusRow.subtitle(role: .trainer, connectedName: "Suito-T", detail: "ERG ready") == "Suito-T · ERG ready")
}

