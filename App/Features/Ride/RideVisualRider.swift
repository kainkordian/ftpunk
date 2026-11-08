import Foundation
import FTPunkDomain

/// The cyclist from the app icon, in profile and facing right: magenta helmet, lime jacket, dark bike with cyan rims.
/// Every joint is placed in bike coordinates (x forward, y down, origin at the rear axle) and tilted with the road,
/// then drawn as pixel strokes, so the same code gives every posture and every pedal frame.
extension RideVisualRenderer {
    private enum Colors {
        static let frame = Ink(56, 64, 114), frameLight = Ink(104, 116, 178), tyre = Ink(8, 10, 24)
        static let rim = RideVisualPalette.cyan, spoke = Ink(0, 104, 124), hub = Ink(210, 220, 240)
        static let tights = Ink(78, 86, 146), farTights = Ink(36, 40, 78), shoe = Ink(238, 242, 250), farShoe = Ink(126, 132, 160)
        static let crank = Ink(150, 158, 184), jacket = RideVisualPalette.lime, jacketShade = Ink(120, 170, 52)
        static let sleeve = Ink(160, 214, 62), glove = Ink(236, 240, 250), skin = Ink(240, 192, 142)
        static let helmet = RideVisualPalette.magenta, helmetShade = Ink(150, 0, 92), helmetLight = Ink(255, 128, 204)
        static let lens = Ink(8, 8, 22), sweat = Ink(160, 226, 255)
    }

    func rider() {
        let zone = RideVisualPalette.zone(state.zone)
        let rearX = 53
        let angle = atan(slope)
        let rearY = roadTop(rearX) - 7
        let cosA = cos(angle), sinA = sin(angle)
        func p(_ x: Double, _ y: Double) -> (x: Int, y: Int) {
            (rearX + Int((x * cosA + y * sinA).rounded()), rearY + Int((-x * sinA + y * cosA).rounded()))
        }
        let power = intensity
        underglow(zone: zone, strength: power)
        headlightBeam(from: p(23, -4), toward: [p(72, -2), p(72, 8)])
        trail(zone: zone, from: p(-6, 0), tilt: slope)
        if state.showsSpeedLines && scene.animated { speedLines(zone: zone, y: rearY - 18) }
        let before = scene.highContrast ? canvas : nil
        if scene.spriteRider {
            spriteRider(rear: p(0, 0), roadY: roadTop(rearX))
            if let before { outline(comparedWith: before) }
            return
        }

        // Posture. Joints are relative to the rear axle.
        // Standing: hip raised and forward over the bottom bracket (12 px up; 13 would overreach the 17 px leg at the bottom of the stroke).
        let hip: (x: Double, y: Double) = state.posture == .standing ? (x: 9.0, y: -12.0) : (x: 5.0, y: -9.0)
        let (shoulderOffset, headOffset, handPosition): ((Double, Double), (Double, Double), (Double, Double))
        switch state.posture {
        case .upright: (shoulderOffset, headOffset, handPosition) = ((2.5, -10.5), (1.5, -3), (16.5, -10.5))
        case .hoods: (shoulderOffset, headOffset, handPosition) = ((6, -8.5), (3, -3), (19, -9.5))
        case .low: (shoulderOffset, headOffset, handPosition) = ((8.8, -6), (3, -3), (20.5, -8))
        case .drops: (shoulderOffset, headOffset, handPosition) = ((10.5, -3.5), (3, -3), (21.5, -6.5))
        case .standing: (shoulderOffset, headOffset, handPosition) = ((8, -9), (3, -3), (20, -9.5)) // upright, hands on the hoods
        }
        let shoulder = (x: hip.x + shoulderOffset.0, y: hip.y + shoulderOffset.1)
        let head = (x: shoulder.x + headOffset.0, y: shoulder.y + headOffset.1)

        // Cranks: four frames a turn at the rider's real cadence; coasting holds them level.
        let frame = state.motion == .pedalling ? Int(motion.crankTurns * 4) & 3 : 0
        let bottomBracket = (x: 9.0, y: 1.0)
        func pedal(_ quarter: Int) -> (x: Double, y: Double) {
            let a = Double(quarter) * .pi / 2
            return (bottomBracket.x + 3.5 * cos(a), bottomBracket.y + 3.5 * sin(a))
        }
        let nearPedal = state.motion == .footDown ? (x: 8.5, y: 6.0) : pedal(frame)
        let farPedal = pedal(state.motion == .footDown ? 0 : frame + 2)
        let crankPedal = pedal(state.motion == .footDown ? 2 : frame)

        func knee(to foot: (x: Double, y: Double)) -> (x: Double, y: Double) {
            let upper = 8.5, lower = 8.5
            let dx = foot.x - hip.x, dy = foot.y - hip.y
            let distance = min(upper + lower - 0.05, max(0.5, (dx * dx + dy * dy).squareRoot()))
            let a = distance / 2, h = (max(0, upper * upper - a * a)).squareRoot()
            let ux = dx / distance, uy = dy / distance
            var nx = -uy, ny = ux
            if nx * 1 + ny * -0.3 < 0 { nx = -nx; ny = -ny } // knees point forward
            return (hip.x + ux * a + nx * h, hip.y + uy * a + ny * h)
        }
        func leg(_ foot: (x: Double, y: Double), thigh: Ink, shoe: Ink) {
            let k = knee(to: foot), h = p(hip.x, hip.y), kn = p(k.x, k.y), f = p(foot.x, foot.y)
            canvas.stroke(h.x, h.y, kn.x, kn.y, width: 2, thigh)
            canvas.stroke(kn.x, kn.y, f.x, f.y, width: 2, thigh)
            canvas.rect(f.x - 1, f.y, 4, 1, shoe); canvas.rect(f.x, f.y - 1, 2, 1, shoe)
        }

        leg(farPedal, thigh: Colors.farTights, shoe: Colors.farShoe)
        let bb = p(bottomBracket.x, bottomBracket.y), far = p(farPedal.x, farPedal.y)
        canvas.line(bb.x, bb.y, far.x, far.y, Colors.crank, alpha: 0.7)
        bike(p, state: state)
        let headlight = p(22.5, -4), tail = p(2.5, -7)
        canvas.set(headlight.x, headlight.y, Ink(255, 248, 214)); canvas.blend(headlight.x + 1, headlight.y, Ink(255, 248, 214), 0.5)
        if !scene.animated || Int(time / 0.75) % 2 == 0 { canvas.set(tail.x, tail.y, Ink(255, 64, 84)) } // blinks once every 1.5 s
        let near = p(crankPedal.x, crankPedal.y)
        canvas.line(bb.x, bb.y, near.x, near.y, Colors.crank)
        canvas.rect(bb.x - 1, bb.y - 1, 3, 3, Colors.crank)

        leg(nearPedal, thigh: Colors.tights, shoe: Colors.shoe)

        // Torso: shaded jacket with a stripe in the zone colour.
        let h = p(hip.x, hip.y), s = p(shoulder.x, shoulder.y)
        let steep = abs(s.y - h.y) > abs(s.x - h.x)
        let lift = steep ? (1, 0) : (0, -1)
        canvas.stroke(h.x, h.y, s.x, s.y, width: 3, Colors.jacketShade)
        canvas.stroke(h.x + lift.0, h.y + lift.1, s.x + lift.0, s.y + lift.1, width: 2, Colors.jacket)
        let mx = Double(h.x + s.x) / 2 + Double(s.x - h.x) * -0.05, my = Double(h.y + s.y) / 2 + Double(s.y - h.y) * -0.05
        let length = max(1, (Double((s.x - h.x) * (s.x - h.x) + (s.y - h.y) * (s.y - h.y))).squareRoot())
        let px = -Double(s.y - h.y) / length, py = Double(s.x - h.x) / length
        for k in -1...1 { canvas.set(Int((mx + px * Double(k)).rounded()), Int((my + py * Double(k)).rounded()), zone) }
        canvas.set(Int((mx + px * 2).rounded()), Int((my + py * 2).rounded()), zone.mixed(with: Colors.jacket, 0.5))

        // Arms to the bars, elbows bent more the lower the rider sits.
        let hand = p(handPosition.0, handPosition.1)
        let elbow = (x: (shoulder.x + handPosition.0) / 2 - 0.5, y: (shoulder.y + handPosition.1) / 2 + (state.posture >= .low && state.posture != .standing ? 2.2 : 1.4))
        let e = p(elbow.x, elbow.y)
        canvas.stroke(s.x, s.y, e.x, e.y, width: 2, Colors.sleeve)
        canvas.stroke(e.x, e.y, hand.x, hand.y, width: 2, Colors.sleeve)
        canvas.rect(hand.x, hand.y, 2, 2, Colors.glove)

        // Head: skin, sunglasses and the magenta helmet.
        let c = p(head.x, head.y)
        canvas.rect(c.x, c.y + 3, 2, 1, Colors.skin)
        canvas.rect(c.x - 1, c.y, 4, 1, Colors.skin); canvas.rect(c.x, c.y + 1, 3, 1, Colors.skin); canvas.rect(c.x, c.y + 2, 2, 1, Colors.skin)
        canvas.rect(c.x + 1, c.y, 2, 1, Colors.lens)
        canvas.set(c.x + 2, c.y, RideVisualPalette.cyan.mixed(with: Colors.lens, 0.3))
        canvas.rect(c.x - 1, c.y - 3, 3, 1, Colors.helmet)
        canvas.rect(c.x - 2, c.y - 2, 5, 1, Colors.helmet)
        canvas.rect(c.x - 3, c.y - 1, 6, 1, Colors.helmet)
        canvas.set(c.x, c.y - 3, Colors.helmetLight); canvas.set(c.x + 1, c.y - 2, Colors.helmetLight)
        canvas.set(c.x - 1, c.y - 2, Colors.helmetShade); canvas.set(c.x - 2, c.y - 1, Colors.helmetShade)
        canvas.set(c.x + 2, c.y - 1, Colors.helmetShade)

        if state.showsSweat { sweat(near: c) }
        if state.showsSparks && scene.animated { sparks(contact: p(0, 6)) }
        if let before { outline(comparedWith: before) }
    }

    /// Strength of the underglow and trail, 0...1, by zone.
    private var intensity: Double {
        guard let zone = state.zone else { return 0.5 }
        return [0.35, 0.5, 0.65, 0.8, 0.95, 1.0][zone.rawValue]
    }

    private func bike(_ p: (Double, Double) -> (x: Int, y: Int), state: RideVisualState) {
        let rear = p(0, 0), front = p(22, 0), bb = p(9, 1), seat = p(5, -8), head = p(19, -8)
        let spokes = Int(Double(d) / 4) & 1
        for centre in [rear, front] { wheel(centre.x, centre.y, spokes: spokes) }
        canvas.line(bb.x, bb.y, rear.x, rear.y, Colors.frame)
        canvas.line(seat.x, seat.y, rear.x, rear.y, Colors.frame)
        canvas.line(bb.x, bb.y, seat.x, seat.y, Colors.frame)
        canvas.line(seat.x, seat.y, head.x, head.y, Colors.frameLight)
        canvas.line(head.x, head.y, bb.x, bb.y, Colors.frame)
        canvas.line(head.x, head.y, front.x, front.y, Colors.frame)
        // Saddle, stem and drop bars.
        let post = p(5, -9), saddleBack = p(2, -9.5), saddleFront = p(8, -9.5)
        canvas.line(seat.x, seat.y, post.x, post.y, Colors.frame)
        canvas.line(saddleBack.x, saddleBack.y, saddleFront.x, saddleFront.y, Colors.frameLight)
        let stem = p(18, -10), bar = p(21, -10), drop = p(22, -7)
        canvas.line(head.x, head.y, stem.x, stem.y, Colors.frame)
        canvas.line(stem.x, stem.y, bar.x, bar.y, Colors.frameLight)
        canvas.line(bar.x, bar.y, drop.x, drop.y, Colors.frameLight)
    }

    private func wheel(_ cx: Int, _ cy: Int, spokes: Int) {
        canvas.ring(cx, cy, 6, Colors.tyre)
        canvas.ring(cx, cy, 5, Colors.rim)
        if spokes == 0 {
            canvas.line(cx - 4, cy, cx + 4, cy, Colors.spoke); canvas.line(cx, cy - 4, cx, cy + 4, Colors.spoke)
        } else {
            canvas.line(cx - 3, cy - 3, cx + 3, cy + 3, Colors.spoke); canvas.line(cx - 3, cy + 3, cx + 3, cy - 3, Colors.spoke)
        }
        canvas.set(cx, cy, Colors.hub)
    }

    /// A faint cone of light on the wet road ahead of the bike.
    private func headlightBeam(from lamp: (x: Int, y: Int), toward ends: [(x: Int, y: Int)]) {
        canvas.polygon([(lamp.x, lamp.y), (ends[0].x, ends[0].y), (ends[1].x, ends[1].y)], Ink(255, 244, 205), alpha: 0.075)
    }

    /// Zone-coloured light under the bike, reflected a little in the wet road.
    private func underglow(zone: Ink, strength: Double) {
        let centre = 53 + 11, reach = 24
        for dx in -reach...reach {
            let x = centre + dx, top = roadTop(x)
            let falloff = pow(1 - abs(Double(dx)) / Double(reach + 1), 2) * strength
            canvas.blend(x, top - 1, zone, falloff * 0.3)
            canvas.blend(x, top, zone, falloff * 0.75)
            canvas.blend(x, top + 1, zone, falloff * 0.5)
            canvas.blend(x, top + 2, zone, falloff * 0.3)
            canvas.blend(x, top + 3, zone, falloff * 0.14)
        }
    }

    /// A light trail behind the rear wheel: longer and brighter the harder the effort.
    private func trail(zone: Ink, from start: (x: Int, y: Int), tilt: Double) {
        let spec = state.trail, length = spec.length
        for (row, share) in [(-2, 0.55), (0, 1.0), (2, 0.8), (4, 0.4)] {
            let rowLength = Int(Double(length) * share)
            guard rowLength > 0 else { continue }
            for step in 0..<rowLength {
                let fade = 1 - Double(step) / Double(rowLength)
                let y = start.y + row + Int((Double(step) * tilt).rounded())
                canvas.blend(start.x - step, y, zone, fade * (spec.dim ? 0.3 : 0.75))
            }
        }
    }

    private func speedLines(zone: Ink, y: Int) {
        for i in 0..<4 {
            let speed = 1.2 + 0.3 * Double(i)
            let phase = (time / RideVisualMotion.loopTime * speed * 3).truncatingRemainder(dividingBy: 1)
            let length = 7 + (i % 3) * 3
            let x = 44 - Int(phase * 44) - (i % 2) * 10
            let ly = y + i * 6 + (i % 2) * 2
            canvas.line(x, ly, x - length, ly, RideVisualPalette.white.mixed(with: zone, 0.4), alpha: 0.5 * (1 - phase))
        }
    }

    /// Two drops flying back from the head.
    private func sweat(near head: (x: Int, y: Int)) {
        for i in 0..<2 {
            let phase = scene.animated ? (time / 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1) : 0.15 + Double(i) * 0.5
            let x = head.x - 3 - Int(phase * 5), y = head.y - 3 + Int(phase * 9)
            canvas.set(x, y, Colors.sweat); canvas.set(x, y + 1, Colors.sweat)
            canvas.blend(x, y - 1, Colors.sweat, 0.4)
        }
    }

    /// VO2max: sparks thrown off the rear tyre. They move; they never blink.
    private func sparks(contact: (x: Int, y: Int)) {
        for i in 0..<6 {
            let phase = (time / 0.5 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
            let reach = 5 + Double(pixelHash(i, 5) % 9)
            let x = contact.x - 2 - Int(phase * reach)
            let y = contact.y - Int(sin(phase * .pi) * (2 + Double(pixelHash(i, 6) % 4)))
            let ink = Ink(255, 232, 140).mixed(with: Ink(255, 110, 40), phase)
            canvas.blend(x, y, ink, 1 - phase * 0.6)
        }
    }

    /// Increase Contrast: a near-black outline around the body, and a thin light rim outside it so it shows on the night.
    private func outline(comparedWith before: PixelLayer) {
        var rider = Set<Int>()
        for y in 0..<canvas.height { for x in 0..<canvas.width where canvas.ink(x, y) != before.ink(x, y) { rider.insert(y * canvas.width + x) } }
        func neighbours(_ index: Int) -> [Int] {
            let x = index % canvas.width, y = index / canvas.width
            return [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)].filter { $0.0 >= 0 && $0.1 >= 0 && $0.0 < canvas.width && $0.1 < canvas.height }
                .map { $0.1 * canvas.width + $0.0 }
        }
        var ring = Set<Int>()
        for index in rider { for n in neighbours(index) where !rider.contains(n) { ring.insert(n) } }
        var rim = Set<Int>()
        for index in ring { for n in neighbours(index) where !rider.contains(n) && !ring.contains(n) { rim.insert(n) } }
        for index in rim { canvas.blend(index % canvas.width, index / canvas.width, Ink(244, 247, 255), 0.7) }
        for index in ring { canvas.set(index % canvas.width, index / canvas.width, Ink(3, 3, 12)) }
    }
}
