import Foundation

/// The Chaindance rider as a pixel sprite, from the RG SP design (ftpunk_rgsp mockup/riders.mjs): rider A "Sprinter"
/// (short brown hair, classic road helmet, short sleeves) in rider D "Veteran" colours (violet jersey, yellow helmet,
/// stripe and shorts, violet bike with yellow rims). SNES-RPG style: four-tone shading, coloured outlines, light from
/// the top left. The web twin is `ftpunk_web/src/chaindance/rider-sprite.mjs`; keep them in step.
/// A scene draws it only when `RideVisualScene.spriteRider` is on; the pixel fixtures use the original drawn rider.
enum RideVisualSprite {
    struct Tones { let o: Ink, s: Ink, b: Ink, l: Ink }
    private struct Point: Hashable { let x: Int, y: Int }
    private typealias Pt = (x: Double, y: Double)

    /// JavaScript's Math.round (halves go up), so the sprite lands on the same pixels as the web version.
    private static func round(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

    // MARK: shapes
    private struct Shape {
        var cells = Set<Point>()
        mutating func disc(_ cx: Double, _ cy: Double, _ r: Double) {
            let x0 = RideVisualSprite.round(cx), y0 = RideVisualSprite.round(cy), reach = Int(r.rounded(.up))
            for y in -reach...reach { for x in -reach...reach where Double(x * x + y * y) <= r * r + r * 0.5 { cells.insert(Point(x: x0 + x, y: y0 + y)) } }
        }
        mutating func stroke(_ a: Pt, _ b: Pt, _ r0: Double, _ r1: Double? = nil) {
            let r1 = r1 ?? r0
            let n = max(abs(b.x - a.x), abs(b.y - a.y), 1) * 2
            for k in 0...Int(n) {
                let u = Double(k) / n
                disc(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, r0 + (r1 - r0) * u)
            }
        }
        func has(_ x: Int, _ y: Int) -> Bool { cells.contains(Point(x: x, y: y)) }
        /// Four tones: outline, shade, base, light.
        func paint(_ set: (Int, Int, Ink) -> Void, _ t: Tones) {
            for c in cells {
                let x = c.x, y = c.y
                let ink: Ink
                if !has(x + 1, y) || !has(x - 1, y) || !has(x, y + 1) || !has(x, y - 1) { ink = t.o }
                else if !has(x - 1, y - 1) || !has(x, y - 2) || !has(x - 2, y) { ink = t.l }
                else if !has(x + 1, y + 1) || !has(x, y + 2) || !has(x + 2, y) { ink = t.s }
                else { ink = t.b }
                set(x, y, ink)
            }
        }
    }
    private static func far(_ t: Tones) -> Tones { Tones(o: t.o, s: t.o, b: t.s, l: t.s) }

    private static func dot(_ set: (Int, Int, Ink) -> Void, _ cx: Double, _ cy: Double, _ r: Double, _ c: Ink) {
        let x0 = round(cx), y0 = round(cy), reach = Int(r.rounded(.up))
        for y in -reach...reach { for x in -reach...reach where Double(x * x + y * y) <= r * r + r * 0.5 { set(x0 + x, y0 + y, c) } }
    }
    private static func line(_ set: (Int, Int, Ink) -> Void, _ a: Pt, _ b: Pt, _ c: Ink) {
        let n = Int(max(abs(b.x - a.x), abs(b.y - a.y), 1))
        for k in 0...n {
            let u = Double(k) / Double(n)
            set(round(a.x + (b.x - a.x) * u), round(a.y + (b.y - a.y) * u), c)
        }
    }
    private static func ring(_ set: (Int, Int, Ink) -> Void, _ cx: Int, _ cy: Int, _ r0: Double, _ r1: Double, _ c: Ink, arc: ((Double) -> Bool)? = nil) {
        let reach = Int(r1.rounded(.up)) + 1
        for y in -reach...reach { for x in -reach...reach {
            let d = Double(x * x + y * y).squareRoot()
            if d >= r0 && d < r1 && (arc?(atan2(Double(y), Double(x))) ?? true) { set(cx + x, cy + y, c) }
        } }
    }
    /// Two-bone joint: the bend of a limb of lengths `l1`, `l2` from `a` to `b`. "forward" picks the knee pointing forward, "down" the elbow pointing down.
    private static func joint(_ a: Pt, _ b: Pt, _ l1: Double, _ l2: Double, down: Bool = false) -> Pt {
        let dx = b.x - a.x, dy = b.y - a.y, d = min((dx * dx + dy * dy).squareRoot(), l1 + l2 - 0.01)
        let q = atan2(dy, dx), w = acos((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))
        let k1 = (x: a.x + cos(q - w) * l1, y: a.y + sin(q - w) * l1), k2 = (x: a.x + cos(q + w) * l1, y: a.y + sin(q + w) * l1)
        return down ? (k1.y > k2.y ? k1 : k2) : (k1.x > k2.x ? k1 : k2)
    }

    // MARK: tones
    private static func hex(_ value: UInt32) -> Ink { Ink(UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)) }
    private static func tones(_ o: UInt32, _ s: UInt32, _ b: UInt32, _ l: UInt32) -> Tones { Tones(o: hex(o), s: hex(s), b: hex(b), l: hex(l)) }
    private static let skin = tones(0x7a3a24, 0xd08860, 0xf6c09a, 0xffe2c8)
    private static let metal = tones(0x1a1630, 0x4a4580, 0x8a86b8, 0xd8dcec)
    private static let dark = tones(0x0e0a1e, 0x1c1838, 0x2c2650, 0x4a4580)
    private static let violet = tones(0x1e0a40, 0x4a2a9a, 0x7a4ae0, 0xb89cff)
    private static let yellow = tones(0x4a3a00, 0xb09000, 0xf5d020, 0xfff3a0)
    private static let white = hex(0xffffff)

    // MARK: head
    private static let helmet = [
        ".......oooooo.....",
        ".....ooHHhhhhHoo..",
        "....oHHVHHhVhHHHo.",
        "...oHHVHHHVHHHVHHo",
        "..oDHHHHHHHHHHHHHo",
        "..oDDHVHHHHVHHHHDo",
        "..oDDDDDDDDDDDDDo.",
    ]
    private static let face = [
        "..rRRqRktsLLLLLsk.",
        "..rRRRkSktssswesk.",
        "..rrRRkkstssseesk.",
        "...rrRksstsssssssk",
        "...rrkSssstsssssk.",
        "....rkSSsstssssk..",
        ".....kkSSSSSSkk...",
        ".......kkkkkk.....",
    ]
    /// One letter per colour: the helmet in rider D's yellow, A's short brown hair, light skin.
    private static let headPalette: [Character: Ink] = [
        "o": yellow.o, "D": yellow.s, "H": yellow.b, "h": yellow.l, "V": yellow.o, "t": yellow.o,
        "k": skin.o, "S": skin.s, "s": skin.b, "L": skin.l, "e": hex(0x20101a), "w": white,
        "r": hex(0x3a1c0c), "R": hex(0x7a4220), "q": hex(0xb06a34),
    ]

    // MARK: geometry (torso 15 px, thigh and shin 10 px each)
    private static let rearWheel: Pt = (18, 41), frontWheel: Pt = (47, 41), bottomBracket: Pt = (30, 41)
    private static let seat: Pt = (25, 28), headTube: Pt = (43, 28), hip: Pt = (26, 27), shoulder: Pt = (37, 19), bars: Pt = (48, 27)
    private static let wheelRadius = 9.0, crank = 4.0, legLength = 10.0
    private static let headOrigin = (x: 31, y: 4)
    /// Where the rear wheel's centre sits in the sprite box; the scene puts this on its rear axle.
    static let rearAxle = (x: 18, y: 41), tyreRadius = 9

    // MARK: wheels
    private static func wheel(_ set: (Int, Int, Ink) -> Void, _ c: Pt, spin: Double) {
        let x = Int(c.x), y = Int(c.y), tyreIn = wheelRadius - 1.5
        let tyre = hex(0x1c1838), tyreHighlight = hex(0x4a4580), rim = yellow.b, spoke = hex(0x6a6590), hub = yellow.l, out = hex(0x0e0a1e)
        for k in 0..<4 {
            let q = spin + Double(k) * .pi / 4
            line(set, (c.x - cos(q) * (tyreIn - 1), c.y - sin(q) * (tyreIn - 1)), (c.x + cos(q) * (tyreIn - 1), c.y + sin(q) * (tyreIn - 1)), spoke)
        }
        ring(set, x, y, tyreIn - 1, tyreIn, rim)
        ring(set, x, y, tyreIn, wheelRadius + 0.5, tyre)
        ring(set, x, y, wheelRadius - 0.5, wheelRadius + 0.5, tyreHighlight) { $0 < -.pi * 0.45 && $0 > -.pi * 0.95 }
        ring(set, x, y, wheelRadius + 0.5, wheelRadius + 1.5, out)
        dot(set, c.x, c.y, 1.5, out); set(x, y, hub)
    }

    /// Draws one frame into a 60 × 52 box through `set`. `time` is in seconds at the sprite's own pedalling rate (84 rpm).
    static func draw(time t: Double, set: (Int, Int, Ink) -> Void) {
        let theta = t * .pi * 2 * 1.4, spin = t * 9
        let bob = sin(theta * 2) > 0.2 ? 1.0 : 0.0
        func pedal(_ phase: Double) -> Pt { (bottomBracket.x + cos(theta + phase) * crank, bottomBracket.y + sin(theta + phase) * crank) }
        let sh: Pt = (shoulder.x, shoulder.y + bob)
        func leg(_ phase: Double, near: Bool) {
            let f = pedal(phase), k = joint(hip, f, legLength, legLength), ankle: Pt = (f.x - 0.5, f.y - 1.5)
            func tone(_ t: Tones) -> Tones { near ? t : far(t) }
            var shin = Shape(); shin.stroke(k, ankle, 2, 1.5); shin.paint(set, tone(skin))
            line(set, (ankle.x - 1, ankle.y), (ankle.x + 1, ankle.y), near ? white : hex(0x6a6590))
            var thigh = Shape(); thigh.stroke(hip, k, 2.7, 2); thigh.paint(set, tone(yellow))
            var shoe = Shape(); shoe.stroke((f.x - 2, f.y), (f.x + 2.5, f.y), 1.5); shoe.paint(set, tone(dark))
        }
        leg(.pi, near: false)

        // Bike.
        wheel(set, rearWheel, spin: spin); wheel(set, frontWheel, spin: spin)
        var frame = Shape()
        for (a, b) in [(rearWheel, bottomBracket), (rearWheel, seat), (bottomBracket, seat), (seat, headTube), (bottomBracket, headTube), (headTube, frontWheel)] { frame.stroke(a, b, 1) }
        let stemTop: Pt = (headTube.x + 1, bars.y + 1)
        frame.stroke(headTube, stemTop, 1)
        frame.paint(set, Tones(o: violet.o, s: violet.s, b: violet.b, l: violet.b))
        var handlebar = Shape()
        handlebar.stroke(stemTop, (bars.x + 1, bars.y), 1)
        handlebar.stroke((bars.x + 1, bars.y), (bars.x + 2, bars.y + 3), 1)
        handlebar.paint(set, metal)
        var saddle = Shape(); saddle.stroke((seat.x - 3, seat.y - 1), (seat.x + 2, seat.y - 1), 1); saddle.paint(set, dark)
        var hub = Shape(); hub.disc(bottomBracket.x, bottomBracket.y, 2.5); hub.paint(set, metal)

        // Rider: shaded torso with a stripe, bare arm under a short sleeve, head.
        var torso = Shape(); torso.stroke(hip, sh, 2.7, 3.5); torso.disc(sh.x - 1, sh.y + 1, 3.5); torso.paint(set, violet)
        line(set, (hip.x + 1, hip.y - 1), (sh.x, sh.y + 2), yellow.b)
        let elbow = joint(sh, bars, 7.5, 7.5, down: true)
        let cuff: Pt = (sh.x + (elbow.x - sh.x) * 0.5, sh.y + (elbow.y - sh.y) * 0.5)
        var forearm = Shape(); forearm.stroke(cuff, elbow, 2); forearm.stroke(elbow, bars, 2, 1.5); forearm.paint(set, skin)
        var sleeve = Shape(); sleeve.stroke(sh, cuff, 2.7, 2.2); sleeve.paint(set, violet)
        var glove = Shape(); glove.disc(bars.x, bars.y, 2); glove.paint(set, dark)
        for (row, text) in (helmet + face).enumerated() {
            for (column, ch) in text.enumerated() { if let ink = headPalette[ch] { set(headOrigin.x + column, headOrigin.y + Int(bob) + row, ink) } }
        }
        line(set, bottomBracket, pedal(0), metal.s); dot(set, bottomBracket.x, bottomBracket.y, 0.5, metal.l)
        leg(0, near: true)
    }
}

extension RideVisualRenderer {
    /// The sprite rider: rear wheel on the road under the scene's rear axle, pedalling at the scene's real cadence.
    func spriteRider(rear: (x: Int, y: Int), roadY: Int) {
        let ox = rear.x - RideVisualSprite.rearAxle.x
        let oy = roadY - RideVisualSprite.tyreRadius - 2 - RideVisualSprite.rearAxle.y
        let seconds = scene.animated && state.motion == .pedalling ? motion.crankTurns / 1.4 : 0
        RideVisualSprite.draw(time: seconds) { x, y, ink in canvas.set(ox + x, oy + y, ink) }
    }
}
