import Foundation
import CoreGraphics
import FTPunkDomain

/// Everything the renderer draws one frame from: the derived state plus what the strip accumulated while animating.
struct RideVisualScene {
    var state: RideVisualState
    var motion = RideVisualMotion()
    /// False under Reduce Motion: no scrolling, parallax, rain or pedalling. Pose, colour and signs still follow the state.
    var animated = true
    /// Increase Contrast: a dark outline (with a thin light rim) around the rider.
    var highContrast = false
    /// Extra sky rows above the strip: 0 for the strip, `HeroLayout.skyRows` for the Large view. Everything else keeps its
    /// row offset from the bottom edge.
    var skyRows = 0
    /// Draws the pixel sprite rider from the RG SP design instead of the original drawn one. Off for the pixel fixtures.
    var spriteRider = false
}

/// The night palette. Zone colours come from the same `ZonePalette` as the workout profile charts (their dark-mode
/// variants, which are the bright ones), so the avatar and the charts always agree.
enum RideVisualPalette {
    static let cyan = Ink(0, 211, 224), magenta = Ink(255, 0, 154), lime = Ink(197, 247, 77), amber = Ink(252, 184, 82)
    static let warmLight = Ink(255, 205, 128), white = Ink(236, 240, 250)
    static func zone(_ zone: IntensityZone?) -> Ink { zone.map { Ink(ZonePalette.pair(for: $0).dark) } ?? cyan }
    static var teal: Ink { zone(.endurance) }
    static func accent(_ district: RideVisualDistrict) -> Ink { district.kind == .residential ? teal : zone(district.zone) }
}

/// A repeating row of buildings, stored per column so a frame can look up any column cheaply.
struct Skyline {
    let period: Int
    let height: [Int], left: [Int], width: [Int], id: [Int]

    init(period: Int, seed: Int, widths: ClosedRange<Int>, heights: ClosedRange<Int>) {
        var height = [Int](repeating: 0, count: period), left = height, width = height, id = height
        var x = 0, n = 0
        while x < period {
            var w = widths.lowerBound + pixelHash(seed, n) % widths.count
            if period - x - w < widths.lowerBound { w = period - x }
            let h = heights.lowerBound + pixelHash(seed, n + 977) % heights.count
            for column in x..<(x + w) { height[column] = h; left[column] = x; width[column] = w; id[column] = n }
            x += w; n += 1
        }
        self.period = period; self.height = height; self.left = left; self.width = width; self.id = id
    }
    /// Buildings that start in the period, for drawing signs once each.
    var buildings: [(id: Int, left: Int, width: Int, height: Int)] {
        var seen = Set<Int>(), result: [(Int, Int, Int, Int)] = []
        for column in 0..<period where seen.insert(id[column]).inserted { result.append((id[column], left[column], width[column], height[column])) }
        return result
    }
}

/// Procedural side view of a rainy night city, 192 × 60, drawn back to front and enlarged with nearest-neighbour
/// sampling. The scenery repeats exactly after `RideVisualMotion.loopDistance` / `loopTime`, so nothing in it counts
/// down to a ramp finish.
enum RideVisualRaster {
    static let width = 192, height = HeroLayout.stripRows
    static let heroHeight = HeroLayout.heroRows
    /// The screen column the road's coordinates are measured from, and the top row of a level road.
    static let riderX = 64, roadBase = 51

    static let far = Skyline(period: 192, seed: 3, widths: 9...20, heights: 8...24)
    static let mid = Skyline(period: 576, seed: 5, widths: 24...46, heights: 24...42)
    static let shops = Skyline(period: 960, seed: 9, widths: 18...34, heights: 9...13)
    static let words = ["24H", "WATT", "FTP", "SPIN", "BAR", "PUNK", "ZONE", "RAMP", "W/KG", "TUNE", "NEON", "GEAR"]

    static func image(_ scene: RideVisualScene) -> CGImage? { pixels(scene).image() }

    static func pixels(_ scene: RideVisualScene) -> Pixels {
        let renderer = RideVisualRenderer(scene)
        scenery(renderer)
        renderer.rider()
        return renderer.canvas.base
    }
    private static func scenery(_ renderer: RideVisualRenderer) {
        renderer.sky()
        renderer.heroSky()
        renderer.farSkyline()
        renderer.heroTowers()
        renderer.spire()
        renderer.midTowers()
        renderer.shopfronts()
        renderer.rail()
        renderer.road()
        renderer.markers()
        renderer.signs()
        renderer.rain()
    }

    /// Rows (from the top of the image) that the rider's drawing changes, found by drawing the same frame without it.
    static func riderRows(_ scene: RideVisualScene) -> Range<Int>? {
        let with = pixels(scene)
        let renderer = RideVisualRenderer(scene)
        scenery(renderer)
        let without = renderer.canvas.base
        var first: Int?, last = 0
        for y in 0..<with.height { for x in 0..<with.width where with.ink(x, y) != without.ink(x, y) { first = first ?? y; last = y } }
        return first.map { $0..<(last + 1) }
    }
}

final class RideVisualRenderer {
    typealias R = RideVisualRaster
    var canvas: PixelLayer
    /// Extra sky rows above the strip (0 outside the Large view).
    let extra: Int
    let scene: RideVisualScene
    let state: RideVisualState
    let motion: RideVisualMotion
    let d: Int
    let time: Double
    let slope: Double
    let sink: Double
    let columns: [Column]
    var reflections: [(x0: Int, x1: Int, ink: Ink, alpha: Double)] = []

    struct Column { var accent: Ink; var residential: Bool }

    init(_ scene: RideVisualScene) {
        self.scene = scene
        extra = scene.skyRows
        canvas = PixelLayer(width: R.width, height: R.height, rowsAbove: scene.skyRows, background: Ink(10, 10, 32))
        state = scene.state
        motion = scene.animated ? scene.motion : RideVisualMotion()
        d = Int(motion.distance.rounded(.down))
        // Whole milliseconds, so a frame one loop later is exactly the same frame.
        time = Double(Int((motion.time * 1000).rounded()) % Int(RideVisualMotion.loopTime * 1000)) / 1000
        switch scene.state.world {
        case .skyway: slope = 0.25
        case .descent: slope = -0.25
        case .boulevard, .rooftop: slope = 0
        }
        // The skyline sinks as the rider climbs, with no end: it only slows down.
        let risen = 26 * (1 - exp(-scene.state.climbSeconds / 120))
        switch scene.state.world {
        case .boulevard: sink = 0
        case .skyway: sink = risen
        case .descent: sink = risen * (1 - scene.state.descent)
        case .rooftop: sink = risen * 0.5 + 12
        }
        let motion = self.motion, state = scene.state, d = d
        let ftp = state.mode == .ftpTest
        columns = (0..<R.width).map { sx in
            if ftp || state.mode != .workout {
                return Column(accent: RideVisualPalette.cyan, residential: false)
            }
            let district = motion.district(atWorldX: Double(d + sx - R.riderX)) ?? state.district
            return Column(accent: RideVisualPalette.accent(district), residential: district.kind == .residential)
        }
    }

    func mod(_ value: Int, _ period: Int) -> Int { ((value % period) + period) % period }
    func floorDiv(_ value: Int, _ size: Int) -> Int { (value - mod(value, size)) / size }
    func roadTop(_ x: Int) -> Int { R.roadBase - Int((slope * Double(x - R.riderX)).rounded(.down)) }
    var glow: Double { state.glow }

    // MARK: Sky and skylines

    func sky() {
        let top = Ink(8, 8, 28), middle = Ink(26, 16, 62), horizon = Ink(78, 30, 104)
        for y in (-extra)..<R.height {
            let f = Double(y) / 50
            canvas.rect(0, y, R.width, 1, f < 0.55 ? top.mixed(with: middle, f / 0.55) : middle.mixed(with: horizon, (f - 0.55) / 0.45))
        }
        let haze = Ink(110, 80, 170)
        for i in 0..<5 {
            let x = mod(pixelHash(7, i) % 192 - d / 8, 192), y = 3 + pixelHash(8, i) % 14, w = 26 + pixelHash(9, i) % 30
            for shift in [-192, 0, 192] {
                canvas.rect(x + shift, y, w, 2, haze, alpha: 0.13)
                canvas.rect(x + shift + 5, y - 1, w - 10, 1, haze, alpha: 0.1)
            }
        }
        if state.world == .rooftop {
            // The city glows below the roof.
            for y in 30..<52 { canvas.rect(0, y, R.width, 1, Ink(255, 70, 190), alpha: 0.1 * Double(y - 30) / 22) }
        }
    }

    /// Large view only: stars, a moon and the tips of a few very tall far towers in the extra sky above the strip.
    func heroSky() {
        guard extra > 0 else { return }
        for i in 0..<64 {
            let x = pixelHash(i, 301) % R.width, y = -extra + pixelHash(i, 302) % (extra + 2)
            let twinkle = scene.animated && (Int(time / 0.5) + i) % 6 == 0
            let bright = pixelHash(i, 303) % 4 == 0
            canvas.blend(x, y, bright ? RideVisualPalette.white : Ink(150, 160, 215), twinkle ? 0.3 : bright ? 0.95 : 0.6)
        }
        let moon = Ink(224, 228, 250), shade = Ink(176, 182, 222)
        canvas.disc(150, -extra + 13, 12, moon, alpha: 0.1)
        canvas.disc(150, -extra + 13, 7, moon)
        canvas.disc(152, -extra + 11, 2, shade); canvas.disc(147, -extra + 16, 2, shade); canvas.set(153, -extra + 16, shade); canvas.set(146, -extra + 11, shade)
    }

    /// Large view only: slender far towers whose tips reach into the extra sky, with a slow red beacon.
    func heroTowers() {
        guard extra > 0 else { return }
        let base = 47 + Int(sink)
        let body = Ink(25, 21, 63), edge = Ink(48, 40, 104)
        for (index, tower) in [(left: 22, width: 6, height: 62), (left: 88, width: 7, height: 74), (left: 146, width: 5, height: 56)].enumerated() {
            for sx in 0..<R.width {
                let u = mod(sx + d / 8, 192), lx = mod(u - tower.left, 192)
                guard lx < tower.width else { continue }
                let top = base - tower.height
                for y in max(-extra, top)..<min(R.height, base + 1) {
                    canvas.set(sx, y, y == top ? edge : lx == 0 ? edge.mixed(with: body, 0.5) : body.mixed(with: Ink(70, 28, 100), Double(y - top) / Double(tower.height) * 0.5))
                    let cell = pixelHash(index * 31 + lx, 500 + y)
                    if lx % 2 == 1, (y - top) % 5 == 3, cell % 4 == 0 { canvas.blend(sx, y, RideVisualPalette.warmLight, 0.6) }
                }
                if lx == tower.width / 2 {
                    for y in max(-extra, top - 6)..<top { canvas.set(sx, y, edge) }
                    if !scene.animated || (Int(time / 0.75) + index) % 2 == 0 { canvas.set(sx, top - 7, Ink(255, 64, 84)); canvas.blend(sx, top - 8, Ink(255, 64, 84), 0.35) }
                }
            }
        }
    }

    func farSkyline() {
        let base = 47 + Int(sink)
        let body = Ink(25, 21, 63), edge = Ink(48, 40, 104)
        for sx in 0..<R.width {
            let u = mod(sx + d / 8, 192), h = R.far.height[u], top = base - h
            guard top < R.height else { continue }
            let lx = u - R.far.left[u], index = R.far.id[u]
            for y in max(-extra, top)..<min(R.height, base + 1) {
                let depth = Double(y - top) / Double(max(1, h))
                canvas.set(sx, y, y == top ? edge : body.mixed(with: Ink(70, 28, 100), depth * 0.5))
                let ly = y - top
                guard lx % 3 == 1, ly % 4 == 2, ly > 1, lx < R.far.width[u] - 1 else { continue }
                let cell = pixelHash(index, (lx / 3) * 41 + ly / 4)
                let lit = cell % 19 == 2 ? (Int(time / 1.5) + cell) % 2 == 0 : true
                if cell % 8 == 0, lit { canvas.blend(sx, y, RideVisualPalette.warmLight, 0.75) }
                else if cell % 8 == 1, lit { canvas.blend(sx, y, RideVisualPalette.cyan, 0.6) }
            }
        }
        if state.world == .rooftop {
            // A carpet of distant lights far below the roof.
            for sx in 0..<R.width { for row in 0..<3 {
                let cell = pixelHash(sx + d / 8, 400 + row)
                if cell % 5 == 0 { canvas.blend(sx, 49 + row * 3, cell % 3 == 0 ? RideVisualPalette.cyan : RideVisualPalette.warmLight, 0.55) }
            } }
        }
    }

    // MARK: The Spire

    func spire() {
        let growth = state.spire
        guard growth > 0, state.world != .rooftop else { rooftopMast(); return }
        let left = R.width - Int(20 + 52 * growth)
        let moving = state.world == .skyway || state.world == .descent
        let shiftU = moving ? d * 3 / 8 : 0, shiftV = moving ? Int(Double(d) * 0.09375) : 0
        let distant = 1 - growth
        let body = Ink(20, 24, 66).mixed(with: Ink(60, 30, 98), distant * 0.6)
        let rib = Ink(34, 40, 96).mixed(with: Ink(70, 40, 112), distant * 0.6)
        for sx in max(0, left)..<R.width {
            let u = sx + shiftU
            for y in (-extra)..<R.height {
                let v = state.world == .descent ? y + shiftV : y - shiftV
                var color = (u / 4) % 6 == 0 ? rib : body
                if mod(v, 24) < 2 { color = rib.mixed(with: RideVisualPalette.cyan, 0.35 * (1 - distant)) }
                canvas.set(sx, y, color)
                // Windows: 2 × 3 pixels on a 4 × 6 grid, hashed over a period that divides the road's loop.
                guard growth > 0.5, (1...2).contains(mod(u, 4)), (2...4).contains(mod(v, 6)), mod(v, 24) > 2 else { continue }
                let cell = pixelHash(mod(floorDiv(u, 4), 144), mod(floorDiv(v, 6), 24) + 61)
                if cell % 3 == 0 {
                    let ink = cell % 9 == 0 ? RideVisualPalette.magenta : cell % 9 == 3 ? RideVisualPalette.cyan : RideVisualPalette.warmLight
                    canvas.blend(sx, y, ink, 0.7 * growth)
                }
            }
        }
        // Neon edge down the side facing the rider, with a soft glow.
        if left >= 0 && left < R.width {
            canvas.rect(left, -extra, 1, R.height + extra, RideVisualPalette.magenta, alpha: 0.9)
            canvas.rect(left - 1, -extra, 1, R.height + extra, RideVisualPalette.magenta, alpha: 0.3)
            canvas.rect(left - 2, -extra, 1, R.height + extra, RideVisualPalette.magenta, alpha: 0.12)
            canvas.rect(left + 1, -extra, 1, R.height + extra, RideVisualPalette.magenta, alpha: 0.18)
        }
    }

    private func rooftopMast() {
        guard state.world == .rooftop else { return }
        canvas.rect(176, 8, 1, 43, Ink(60, 66, 120))
        canvas.rect(175, 12, 3, 1, Ink(60, 66, 120)); canvas.rect(174, 20, 5, 1, Ink(60, 66, 120))
        if Int(time / 0.75) % 2 == 0 { canvas.set(176, 7, RideVisualPalette.magenta); canvas.blend(176, 6, RideVisualPalette.magenta, 0.4) }
    }

    // MARK: Mid towers and their neon

    func midTowers() {
        let skyway = state.world != .boulevard
        let base = 52 + Int(sink * (skyway ? 1.4 : 1)) + (state.world == .rooftop ? 10 : 0)
        let body = Ink(13, 12, 40)
        for sx in 0..<R.width {
            let u = mod(sx + d * 3 / 8, 576), h = R.mid.height[u], top = base - h
            guard top < R.height else { continue }
            let lx = u - R.mid.left[u], index = R.mid.id[u], column = columns[sx]
            for y in max(0, top)..<min(R.height, base + 1) {
                let ly = y - top
                var color = body
                if ly == 0 { color = Ink(38, 33, 88) }
                else if lx == 0 { color = column.accent.mixed(with: body, 0.6 + 0.3 * (1 - glow)) }
                else if lx == R.mid.width[u] - 1 { color = Ink(8, 8, 26) }
                canvas.set(sx, y, color)
                guard lx > 1, lx < R.mid.width[u] - 2, ly > 2, mod(lx, 5) < 2, mod(ly, 6) < 2 else { continue }
                let cell = pixelHash(index, (lx / 5) * 53 + ly / 6)
                if cell % 4 == 0 {
                    let accent = column.accent
                    let ink = column.residential ? (cell % 8 == 0 ? RideVisualPalette.warmLight : accent.mixed(with: .init(255, 230, 170), 0.4))
                                                  : (cell % 8 == 0 ? RideVisualPalette.warmLight : accent)
                    canvas.blend(sx, y, ink, 0.55 + 0.35 * glow)
                }
            }
        }
        // Neon signs: one per building at most, once per visible repeat of the layer.
        for building in R.mid.buildings where building.width >= 26 && pixelHash(building.id, 11) % 3 == 0 {
            let word = R.words[pixelHash(building.id, 12) % R.words.count]
            let w = Pixels.textWidth(word) + 4
            for repeatIndex in -1...1 {
                let sx = building.left + repeatIndex * 576 - d * 3 / 8 + (building.width - w) / 2
                guard sx > -w, sx < R.width else { continue }
                let centre = min(R.width - 1, max(0, sx + w / 2)), column = columns[centre]
                if column.residential && pixelHash(building.id, 13) % 2 == 0 { continue }
                let palette = [RideVisualPalette.magenta, RideVisualPalette.cyan, RideVisualPalette.lime]
                let ink = pixelHash(building.id, 14) % 2 == 0 ? column.accent : palette[pixelHash(building.id, 15) % palette.count]
                let y = base - building.height + 5 + pixelHash(building.id, 16) % 9
                let dim = scene.animated && pixelHash(building.id, 17) % 5 == 0 && time < 0.25 // a brief flicker, never under Reduce Motion
                neonBoard(x: sx, y: y, word, ink, alpha: (dim ? 0.45 : 1) * (0.55 + 0.45 * glow))
                reflections.append((sx, sx + w, ink, 0.2))
            }
        }
    }

    /// Street-level shops behind the railing: awnings and lit windows in the district's colour, calmer in residential blocks.
    func shopfronts() {
        guard state.world == .boulevard else { return }
        let base = 50, night = Ink(11, 10, 34)
        for sx in 0..<R.width {
            let u = mod(sx + d * 5 / 8, 960), height = R.shops.height[u], top = base - height
            let lx = u - R.shops.left[u], width = R.shops.width[u], index = R.shops.id[u]
            let column = columns[sx], strength = column.residential ? 0.5 : 0.6 + 0.4 * glow
            guard lx > 0, lx < width - 1 else { canvas.rect(sx, top, 1, height + 1, Ink(6, 6, 22)); continue }
            for y in top...base {
                let ly = y - top
                canvas.set(sx, y, ly == 0 ? Ink(30, 28, 70) : night)
                if ly == 1 || ly == 2 {
                    canvas.blend(sx, y, column.accent.mixed(with: night, (lx / 2) % 2 == 0 ? 0.2 : 0.55), strength)
                } else if ly >= 4, ly <= height - 2, lx >= 2, lx < width - 2, abs(lx - width / 2) > 1, pixelHash(index, 77) % 4 != 0 {
                    let warm = RideVisualPalette.warmLight.mixed(with: column.accent, pixelHash(index, 78) % 3 == 0 ? 0.7 : 0.25)
                    canvas.blend(sx, y, warm, 0.42 * strength)
                }
            }
        }
    }

    /// A framed neon word with a soft halo.
    func neonBoard(x: Int, y: Int, _ text: String, _ ink: Ink, alpha: Double = 1, height h: Int = 9) {
        let w = Pixels.textWidth(text) + 4
        canvas.rect(x - 1, y - 1, w + 2, h + 2, ink, alpha: 0.2 * alpha)
        canvas.rect(x, y, w, h, Ink(5, 5, 20))
        canvas.rect(x, y, w, 1, ink, alpha: alpha); canvas.rect(x, y + h - 1, w, 1, ink, alpha: alpha)
        canvas.rect(x, y, 1, h, ink, alpha: alpha); canvas.rect(x + w - 1, y, 1, h, ink, alpha: alpha)
        canvas.text(text, x: x + 2, y: y + (h - 5) / 2, ink.mixed(with: .init(255, 255, 255), 0.35), alpha: alpha)
    }

    // MARK: Railing, lamps and road

    func rail() {
        for sx in 0..<R.width {
            let top = roadTop(sx), column = columns[sx]
            let post = mod(d + sx - R.riderX, 8) == 0
            let railInk = Ink(78, 90, 148).mixed(with: column.accent, 0.3 * glow)
            canvas.set(sx, top - 8, railInk)
            canvas.set(sx, top - 5, Ink(44, 50, 100))
            if post { for y in (top - 7)..<top { canvas.set(sx, y, Ink(40, 46, 92)) } }
        }
        // Lamp posts every 96 road pixels.
        let first = Int((Double(d - R.riderX) / 96).rounded(.down)) - 1
        for k in first...(first + 4) {
            let x = R.riderX + 40 + k * 96 - d
            guard x > -8, x < R.width + 8 else { continue }
            let top = roadTop(x), headY = top - 27
            let column = columns[min(R.width - 1, max(0, x))]
            let light = RideVisualPalette.warmLight.mixed(with: column.accent, 0.25)
            canvas.rect(x, headY, 1, 27, Ink(62, 70, 118))
            canvas.rect(x + 1, headY, 3, 1, Ink(62, 70, 118))
            canvas.rect(x + 2, headY + 1, 3, 1, light)
            canvas.disc(x + 3, headY + 2, 3, light, alpha: 0.2)
            canvas.polygon([(x + 2, headY + 2), (x + 4, headY + 2), (x + 11, top), (x - 5, top)], light, alpha: 0.07)
            reflections.append((x - 1, x + 5, light, 0.22))
        }
    }

    func road() {
        let deck = Ink(26, 28, 56)
        for sx in 0..<R.width {
            let top = roadTop(sx), column = columns[sx]
            guard top < R.height else { continue }
            canvas.set(sx, top, column.accent.mixed(with: Ink(20, 22, 44), 0.35 - 0.25 * glow))
            for y in (top + 1)..<min(R.height, top + 8) {
                canvas.set(sx, y, deck.mixed(with: Ink(14, 15, 34), Double(y - top) / 8))
            }
            if top + 8 < R.height { for y in (top + 8)..<min(R.height, top + 11) { canvas.set(sx, y, Ink(34, 38, 78)) } }
            if top + 9 < R.height, mod(d + sx - R.riderX, 12) == 0 { canvas.set(sx, top + 9, column.accent) }
            // Lane dashes.
            if mod(d + sx - R.riderX, 24) < 10 { canvas.blend(sx, top + 4, Ink(170, 180, 220), 0.55) }
        }
        // Wet reflections of the neon above and puddles that slide with the road.
        for item in reflections {
            let low = max(0, item.x0), high = min(R.width, max(item.x0 + 1, item.x1))
            guard low < high else { continue } // a lamp or sign just off either edge
            for sx in low..<high {
                let top = roadTop(sx)
                for row in 2...6 { canvas.blend(sx, top + row, item.ink, item.alpha * (1 - Double(row - 2) / 6)) }
            }
        }
        for k in -1...3 {
            let base = Int((Double(d) / 192).rounded(.down)) + k
            let x = R.riderX + base * 192 + pixelHash(base % 8 + 8, 3) % 150 - d
            guard x > -30, x < R.width + 10 else { continue }
            let top = roadTop(x + 8), w = 12 + pixelHash(base % 8 + 8, 4) % 12
            canvas.rect(x, top + 5, w, 1, Ink(110, 120, 190), alpha: 0.28)
            canvas.rect(x + 2, top + 6, w - 4, 1, Ink(110, 120, 190), alpha: 0.16)
        }
        // Struts under the skyway.
        if state.world == .skyway || state.world == .descent {
            for k in -1...4 {
                let x = R.riderX + 20 + k * 64 - mod(d, 64)
                let top = roadTop(x) + 11
                canvas.stroke(x, top, x - 12, top + 22, width: 2, Ink(30, 34, 72))
            }
        }
    }

    // MARK: Signs that pass the rider

    func markers() {
        for marker in motion.markers {
            let sx = R.riderX + Int(marker.worldX.rounded(.down)) - d
            guard sx > -90, sx < R.width + 90 else { continue }
            let top = roadTop(sx)
            switch marker.kind {
            case .level:
                post(sx, from: top, to: top - 9)
                neonBoard(x: sx - Pixels.textWidth(marker.text) / 2 - 2, y: top - 18, marker.text, RideVisualPalette.lime)
            case .gate:
                post(sx, from: top, to: top - 11)
                neonBoard(x: sx - Pixels.textWidth(marker.text) / 2 - 2, y: top - 20, marker.text, RideVisualPalette.cyan)
            case .billboard:
                let accent = RideVisualPalette.accent(motion.district(atWorldX: marker.worldX + 40) ?? state.district)
                let w = Pixels.textWidth(marker.text) + 4, x = sx - w / 2
                post(x + 4, from: top, to: 14); post(x + w - 5, from: top, to: 14)
                neonBoard(x: x, y: 3, marker.text, accent, height: 11)
            case .gantry:
                let accent = RideVisualPalette.accent(motion.district(atWorldX: marker.worldX + 2) ?? state.district)
                canvas.rect(sx, top - 36, 2, 36, Ink(62, 70, 118))
                canvas.rect(sx - 10, top - 37, 22, 2, Ink(62, 70, 118))
                for led in 0..<5 { canvas.set(sx - 8 + led * 4, top - 35, accent) }
                for y in (top - 34)..<top { canvas.blend(sx + 3, y, accent, 0.1) }
                canvas.rect(sx - 10, top - 37, 22, 1, accent, alpha: 0.35)
            }
        }
    }
    private func post(_ x: Int, from bottom: Int, to top: Int) {
        guard bottom > top else { return }
        canvas.rect(x, top, 1, bottom - top, Ink(58, 66, 112))
    }

    /// Fixed signs: PAUSED, the finish sign on the rooftop, and the current level, step or gate under Reduce Motion.
    func signs() {
        guard let sign = state.sign else { return }
        switch sign.kind {
        case .paused:
            let w = Pixels.textWidth(sign.text) + 4, x = 142 - w / 2
            canvas.line(x + 3, 0, x + 3, 4, Ink(70, 78, 128)); canvas.line(x + w - 4, 0, x + w - 4, 4, Ink(70, 78, 128))
            neonBoard(x: x, y: 5, sign.text, RideVisualPalette.amber, height: 11)
        case .finish:
            let w = Pixels.textWidth(sign.text) + 4, x = min(R.width - w - 6, 138 - w / 2 + 8)
            post(x + 5, from: R.roadBase, to: 22); post(x + w - 6, from: R.roadBase, to: 22)
            canvas.rect(x - 3, 5, w + 6, 19, RideVisualPalette.magenta, alpha: 0.12)
            neonBoard(x: x, y: 8, sign.text, RideVisualPalette.lime, height: 13)
        case .level, .step, .gate:
            guard !scene.animated else { return }
            let ink = sign.kind == .level ? RideVisualPalette.lime : RideVisualPalette.cyan
            neonBoard(x: 150 - Pixels.textWidth(sign.text) / 2, y: 8, sign.text, ink)
        }
    }

    // MARK: Rain

    func rain() {
        guard scene.animated else { return }
        let slant = state.rainSlant * 0.8
        let phase = time.truncatingRemainder(dividingBy: 1.5) / 1.5
        for i in 0..<44 {
            let near = i < 26
            let span = R.height + extra + 12
            let x0 = pixelHash(i, 91) % (R.width + 40) - 20, y0 = pixelHash(i, 92) % span
            let travel = Double(span * (near ? 2 : 1)) * phase
            let y = (y0 + Int(travel)) % span - 6 - extra
            let x = x0 - Int(slant * Double(y))
            let length = near ? 3 : 2
            canvas.line(x, y, x - Int((slant * Double(length)).rounded()), y + length, Ink(170, 192, 255), alpha: near ? 0.42 : 0.24)
        }
    }
}
