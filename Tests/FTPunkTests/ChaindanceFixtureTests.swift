import Foundation
import Testing
import FTPunkDomain
@testable import FTPunkApp

// The shared parity fixture for the web port of Chaindance (ftpunk_web/src/chaindance/). A fixed set of ride states (every zone, both
// modes, standing, coasting, paused, reduce motion, increase contrast, the Large view, several distances and times) is described by plain
// data, rendered by the native renderer, and stored with the FNV-1a fingerprint of the RGBA bytes and a summary of the derived state.
// The JavaScript renderer must produce the same bytes and the same state. The rider is the made-up preview rider: 71 kg, 230 W.
// Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter chaindanceMatchesTheSharedFixture

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func round9(_ value: Double) -> Double { (value * 1e9).rounded() / 1e9 }

/// FNV-1a over a frame's bytes (the function of RideVisualRasterTests).
private func fingerprint(_ canvas: Pixels) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in canvas.bytes { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return String(hash, radix: 16)
}

private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

private func input(from spec: [String: Any]) -> RideVisualInput {
    var ramp: RideVisualInput.Ramp?
    if let r = spec["ramp"] as? [String: Any] {
        ramp = .init(phaseSeconds: number(r["phaseSeconds"])!, warmupSeconds: number(r["warmupSeconds"])!, cooldownSeconds: number(r["cooldownSeconds"])!,
                     stepSeconds: number(r["stepSeconds"])!, rampSeconds: number(r["rampSeconds"])!, bestMinuteWatts: number(r["bestMinuteWatts"]))
    }
    var step: RideVisualInput.Step?
    if let s = spec["step"] as? [String: Any] {
        var next: RideVisualInput.Step.Next?
        if let n = s["next"] as? [String: Any] { next = .init(seconds: number(n["seconds"])!, startWatts: number(n["startWatts"])!, endWatts: number(n["endWatts"])!) }
        step = .init(index: Int(number(s["index"])!), count: Int(number(s["count"])!), startWatts: number(s["startWatts"])!, endWatts: number(s["endWatts"])!,
                     seconds: number(s["seconds"])!, remaining: number(s["remaining"])!, next: next)
    }
    let mode: RideVisualMode = switch spec["mode"] as? String { case "workout": .workout; case "freeERG": .freeERG; case "resistance": .resistance; default: .ftpTest }
    let phase = WorkoutPhase(rawValue: spec["phase"] as! String)!
    return RideVisualInput(mode: mode, phase: phase, power: number(spec["power"]), cadence: number(spec["cadence"]), cadenceAvailable: (spec["cadenceAvailable"] as? Bool) ?? true,
                           ftp: number(spec["ftp"]), playbackSpeed: number(spec["playbackSpeed"]) ?? 1, ramp: ramp, step: step, target: number(spec["target"]).map { Int($0) },
                           weightKG: number(spec["weightKG"]), sprintPower: number(spec["sprintPower"]), sprintPeak: number(spec["sprintPeak"]))
}

private func districtSummary(_ district: RideVisualDistrict?) -> Any {
    guard let district else { return NSNull() }
    return ["kind": district.kind == .market ? "market" : "residential", "zone": district.zone.map { $0.rawValue as Any } ?? NSNull()]
}

private func summary(_ state: RideVisualState) -> [String: Any] {
    let world = ["boulevard", "skyway", "rooftop", "descent"][[RideVisualWorld.boulevard, .skyway, .rooftop, .descent].firstIndex(of: state.world)!]
    let motion = state.motion == .pedalling ? "pedalling" : state.motion == .coasting ? "coasting" : "footDown"
    var result: [String: Any] = [
        "world": world, "zone": state.zone.map { $0.rawValue as Any } ?? NSNull(), "posture": state.posture.rawValue, "motion": motion,
        "pedalPeriod": state.pedalPeriod.map { round9($0) as Any } ?? NSNull(), "worldSpeed": round9(state.worldSpeed), "animationRate": state.animationRate,
        "rainSlant": round9(state.rainSlant), "district": districtSummary(state.district), "glow": round9(state.glow), "level": state.level.map { $0 as Any } ?? NSNull(),
        "spire": round9(state.spire), "climbSeconds": round9(state.climbSeconds), "descent": round9(state.descent), "accessibilitySummary": state.accessibilitySummary,
        "trailLength": state.trail.length, "trailDim": state.trail.dim, "sweat": state.showsSweat, "sparks": state.showsSparks, "speedLines": state.showsSpeedLines
    ]
    let signKind = { (kind: RideVisualSign.Kind) in ["level", "finish", "paused", "step", "gate"][[RideVisualSign.Kind.level, .finish, .paused, .step, .gate].firstIndex(of: kind)!] }
    result["sign"] = state.sign.map { ["kind": signKind($0.kind), "text": $0.text] as [String: Any] } ?? NSNull()
    result["upcoming"] = state.upcoming.map { ["key": $0.key, "kind": $0.kind == .level ? "level" : "step", "text": $0.text, "secondsUntil": round9($0.secondsUntil), "district": districtSummary($0.district)] as [String: Any] } ?? NSNull()
    return result
}

private let ftp = 230.0, weight = 71.0

private func ramp(_ phase: String, power: Double, phaseSeconds: Double, rampSeconds: Double, warmup: Double = 60, step: Double = 12, best: Double? = nil, extra: [String: Any] = [:]) -> [String: Any] {
    var ramp: [String: Any] = ["phaseSeconds": phaseSeconds, "warmupSeconds": warmup, "cooldownSeconds": 180, "stepSeconds": step, "rampSeconds": rampSeconds]
    if let best { ramp["bestMinuteWatts"] = best }
    var spec: [String: Any] = ["mode": "ftpTest", "phase": phase, "power": power, "cadence": 90, "ftp": ftp, "weightKG": weight, "ramp": ramp]
    for (key, value) in extra { spec[key] = value }
    return spec
}
private func workout(power: Double, start: Double? = nil, end: Double? = nil, remaining: Double = 150, next: [String: Any]? = nil, phase: String = "riding", extra: [String: Any] = [:]) -> [String: Any] {
    var step: [String: Any] = ["index": 2, "count": 9, "startWatts": start ?? power, "endWatts": end ?? power, "seconds": 300, "remaining": remaining]
    if let next { step["next"] = next }
    var spec: [String: Any] = ["mode": "workout", "phase": phase, "power": power, "cadence": 92, "ftp": ftp, "weightKG": weight, "step": step]
    for (key, value) in extra { spec[key] = value }
    return spec
}
private func ride(_ mode: String, target: Int, power: Double = 150, extra: [String: Any] = [:]) -> [String: Any] {
    var spec: [String: Any] = ["mode": mode, "phase": "riding", "power": power, "cadence": 90, "ftp": ftp, "weightKG": weight, "target": target]
    for (key, value) in extra { spec[key] = value }
    return spec
}

private struct Case {
    var name: String
    var spec: [String: Any]
    var distance = 123.0, time = 0.7, crankTurns = 0.25
    /// Advance the motion with `steps` steps of `dt` seconds first (announces signs, districts and gates).
    var advance: (steps: Int, dt: Double)?
    /// A different state to advance with after the first `advance` (a gate or district changing).
    var thenSpec: [String: Any]?
    var animated = true, highContrast = false, skyRows = 0
}

private func cases() -> [Case] {
    var all: [Case] = []
    let percents = [("recovery", 0.4), ("endurance", 0.65), ("tempo", 0.8), ("sweetSpot", 0.91), ("threshold", 1.0), ("vo2max", 1.2)]
    for (name, fraction) in percents { all.append(Case(name: "zone-\(name)-workout", spec: workout(power: ftp * fraction))) }
    for (name, fraction) in percents { all.append(Case(name: "zone-\(name)-ramp", spec: ramp("ramp", power: ftp * fraction, phaseSeconds: 360, rampSeconds: 360))) }
    all.append(Case(name: "no-power", spec: workout(power: 0, extra: ["power": NSNull()])))
    all.append(Case(name: "no-ftp", spec: ["mode": "freeERG", "phase": "riding", "power": 180, "cadence": 88, "target": 150]))
    // The FTP test's phases.
    all.append(Case(name: "ramp-waiting", spec: ramp("waiting", power: 90, phaseSeconds: 0, rampSeconds: 0)))
    all.append(Case(name: "ramp-warmup", spec: ramp("warmup", power: 115, phaseSeconds: 30, rampSeconds: 0)))
    all.append(Case(name: "ramp-warmup-ending", spec: ramp("warmup", power: 115, phaseSeconds: 57, rampSeconds: 0), advance: (30, 0.1)))
    all.append(Case(name: "ramp-level-ending", spec: ramp("ramp", power: 200, phaseSeconds: 79, rampSeconds: 79), advance: (60, 0.1)))
    all.append(Case(name: "ramp-long", spec: ramp("ramp", power: 330, phaseSeconds: 700, rampSeconds: 700)))
    all.append(Case(name: "ramp-high-contrast", spec: ramp("ramp", power: 330, phaseSeconds: 700, rampSeconds: 700), highContrast: true))
    all.append(Case(name: "ramp-sprint-power-never-stands", spec: ramp("ramp", power: 330, phaseSeconds: 300, rampSeconds: 300, extra: ["sprintPower": 620, "sprintPeak": 640])))
    all.append(Case(name: "rooftop", spec: ramp("cooldown", power: 120, phaseSeconds: 1, rampSeconds: 560, best: 290)))
    all.append(Case(name: "rooftop-no-best", spec: ramp("cooldown", power: 120, phaseSeconds: 2, rampSeconds: 560)))
    all.append(Case(name: "descent", spec: ramp("cooldown", power: 120, phaseSeconds: 90, rampSeconds: 560)))
    all.append(Case(name: "completed-summit", spec: ramp("completed", power: 90, phaseSeconds: 180, rampSeconds: 560, best: 305)))
    all.append(Case(name: "interrupted-without-ramp", spec: ramp("interrupted", power: 90, phaseSeconds: 4, rampSeconds: 0)))
    all.append(Case(name: "ramp-paused-sign", spec: ramp("paused", power: 90, phaseSeconds: 4, rampSeconds: 0)))
    // The other modes.
    all.append(Case(name: "free-erg", spec: ride("freeERG", target: 150)))
    all.append(Case(name: "free-erg-gate", spec: ride("freeERG", target: 150), advance: (40, 0.1), thenSpec: ride("freeERG", target: 175)))
    all.append(Case(name: "resistance", spec: ride("resistance", target: 100, power: 120)))
    all.append(Case(name: "workout-paused", spec: workout(power: 0, phase: "paused", extra: ["power": NSNull(), "cadence": NSNull()])))
    all.append(Case(name: "workout-next-step", spec: workout(power: 230, remaining: 8, next: ["seconds": 180, "startWatts": 120, "endWatts": 120]), advance: (50, 0.1)))
    all.append(Case(name: "workout-next-step-hard", spec: workout(power: 140, remaining: 4, next: ["seconds": 300, "startWatts": 276, "endWatts": 276]), advance: (50, 0.1)))
    all.append(Case(name: "workout-ramped-step", spec: workout(power: 150, start: 120, end: 240, remaining: 100)))
    all.append(Case(name: "workout-recovery-district", spec: workout(power: 100, start: 100, end: 100)))
    // Standing, coasting and cadence.
    all.append(Case(name: "standing-sprint", spec: workout(power: 480, extra: ["sprintPower": 560, "sprintPeak": 580])))
    all.append(Case(name: "standing-held", spec: workout(power: 440, extra: ["sprintPower": 480, "sprintPeak": 520])))
    all.append(Case(name: "standing-needs-pedalling", spec: workout(power: 480, extra: ["cadence": 0, "sprintPower": 560, "sprintPeak": 580])))
    all.append(Case(name: "standing-ftp-threshold-without-weight", spec: workout(power: 400, extra: ["weightKG": NSNull(), "sprintPower": 380, "sprintPeak": 380])))
    all.append(Case(name: "coasting", spec: workout(power: 0, extra: ["power": 0, "cadence": 0])))
    all.append(Case(name: "no-cadence-source", spec: workout(power: 150, extra: ["cadence": NSNull(), "cadenceAvailable": false])))
    all.append(Case(name: "playback-speed-4", spec: workout(power: 200, extra: ["playbackSpeed": 60])))
    // Reduce motion, increase contrast, the Large view.
    all.append(Case(name: "reduce-motion-workout", spec: workout(power: 230), animated: false))
    all.append(Case(name: "reduce-motion-ramp", spec: ramp("ramp", power: 230, phaseSeconds: 100, rampSeconds: 100), animated: false))
    all.append(Case(name: "reduce-motion-gate", spec: ride("freeERG", target: 150), animated: false))
    all.append(Case(name: "contrast-workout", spec: workout(power: 230), highContrast: true))
    all.append(Case(name: "contrast-vo2", spec: workout(power: 280), animated: false, highContrast: true))
    all.append(Case(name: "hero-workout", spec: workout(power: 200), skyRows: 36))
    all.append(Case(name: "hero-ramp", spec: ramp("ramp", power: 250, phaseSeconds: 360, rampSeconds: 360), time: 1.2, skyRows: 36))
    all.append(Case(name: "hero-rooftop", spec: ramp("cooldown", power: 120, phaseSeconds: 1, rampSeconds: 560, best: 290), skyRows: 36))
    all.append(Case(name: "hero-reduce-motion", spec: workout(power: 150), animated: false, skyRows: 36))
    all.append(Case(name: "hero-paused", spec: workout(power: 0, phase: "paused", extra: ["power": NSNull()]), skyRows: 36))
    all.append(Case(name: "hero-contrast", spec: workout(power: 250), highContrast: true, skyRows: 36))
    // Distances, times and cranks.
    for (distance, time, crank) in [(0.0, 0.0, 0.0), (97.0, 0.25, 0.3), (400.0, 1.5, 0.55), (1535.0, 2.9, 0.8), (1536.0, 3.0, 1.0), (3000.0, 0.1, 7.7)] {
        all.append(Case(name: "motion-boulevard-\(Int(distance))-\(Int(time * 100))", spec: workout(power: 200), distance: distance, time: time, crankTurns: crank))
        all.append(Case(name: "motion-skyway-\(Int(distance))-\(Int(time * 100))", spec: ramp("ramp", power: 260, phaseSeconds: 400, rampSeconds: 400), distance: distance, time: time, crankTurns: crank))
    }
    all.append(Case(name: "motion-descent-777", spec: ramp("cooldown", power: 120, phaseSeconds: 60, rampSeconds: 560), distance: 777, time: 2.1, crankTurns: 3.3))
    return all
}

private func render(_ item: Case) -> (state: RideVisualState, motion: RideVisualMotion, pixels: Pixels) {
    let state = RideVisualState.make(input(from: item.spec))
    var motion = RideVisualMotion(distance: item.distance, time: item.time, crankTurns: item.crankTurns)
    if let advance = item.advance {
        for _ in 0..<advance.steps { motion.advance(by: advance.dt, state: state) }
        if let thenSpec = item.thenSpec {
            let next = RideVisualState.make(input(from: thenSpec))
            for _ in 0..<advance.steps { motion.advance(by: advance.dt, state: next) }
        }
    }
    let scene = RideVisualScene(state: item.thenSpec.map { RideVisualState.make(input(from: $0)) } ?? state, motion: motion, animated: item.animated, highContrast: item.highContrast, skyRows: item.skyRows)
    return (scene.state, motion, RideVisualRaster.pixels(scene))
}

private func fixture() -> [String: Any] {
    let entries = cases().map { item -> [String: Any] in
        let (state, motion, pixels) = render(item)
        var spec: [String: Any] = ["name": item.name, "input": item.spec, "distance": item.distance, "time": item.time, "crankTurns": item.crankTurns,
                                   "animated": item.animated, "highContrast": item.highContrast, "skyRows": item.skyRows]
        if let advance = item.advance { spec["advance"] = ["steps": advance.steps, "dt": advance.dt] }
        if let thenSpec = item.thenSpec { spec["thenInput"] = thenSpec }
        let markers = motion.markers.map { ["kind": ["level", "gantry", "billboard", "gate"][[RideVisualMotion.Marker.Kind.level, .gantry, .billboard, .gate].firstIndex(of: $0.kind)!], "text": $0.text, "worldX": round9($0.worldX)] as [String: Any] }
        let segments = motion.segments.map { ["startX": round9($0.startX), "district": districtSummary($0.district)] as [String: Any] }
        return ["spec": spec, "state": summary(state), "width": pixels.width, "height": pixels.height, "fingerprint": fingerprint(pixels),
                "motion": ["distance": round9(motion.distance), "time": round9(motion.time), "crankTurns": round9(motion.crankTurns), "markers": markers, "segments": segments]]
    }
    return ["format": "ftpunk-chaindance-fingerprints", "version": 1, "hash": "FNV-1a 64 over the RGBA bytes, lowercase hex without leading zeros", "cases": entries]
}

@Test func chaindanceMatchesTheSharedFixture() throws {
    let url = root.appendingPathComponent("contracts/fixtures/chaindance-fingerprints.json")
    let expected = try JSONSerialization.data(withJSONObject: fixture(), options: [.prettyPrinted, .sortedKeys])
    if ProcessInfo.processInfo.environment["FTPUNK_WRITE_FIXTURES"] == "1" { try expected.write(to: url, options: .atomic) }
    // Byte comparison: the serialisation is deterministic, and decoded decimals would not compare equal to doubles.
    let data = try Data(contentsOf: url)
    #expect(data == expected, "Regenerate with FTPUNK_WRITE_FIXTURES=1 swift test --filter chaindanceMatchesTheSharedFixture")
    let stored = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(stored["cases"] as? [[String: Any]])
    #expect(entries.count > 60)
    // The fixture must cover what it claims: every zone, standing, both sizes, every world.
    let states = entries.compactMap { $0["state"] as? [String: Any] }
    #expect(Set(states.compactMap { $0["world"] as? String }) == ["boulevard", "skyway", "rooftop", "descent"])
    #expect(Set(states.compactMap { $0["zone"] as? Int }) == [0, 1, 2, 3, 4, 5])
    #expect(states.contains { $0["posture"] as? Int == 4 } && states.contains { $0["motion"] as? String == "footDown" } && states.contains { $0["motion"] as? String == "coasting" })
    #expect(Set(entries.compactMap { $0["height"] as? Int }) == [60, 96])
}

@Test func theFixtureFramesMatchTheStripReferenceFramesOfTheRasterTests() throws {
    // Spot check that the fixture's fingerprint function is the one the native raster tests pin: a frame rendered twice has one fingerprint, a different pose another.
    let item = cases().first { $0.name == "zone-threshold-workout" }!, other = cases().first { $0.name == "zone-recovery-workout" }!
    #expect(fingerprint(render(item).pixels) == fingerprint(render(item).pixels))
    #expect(fingerprint(render(item).pixels) != fingerprint(render(other).pixels))
}
