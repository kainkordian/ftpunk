import Foundation
import CoreGraphics

/// One opaque colour of the pixel palette.
struct Ink: Equatable {
    let r: UInt8, g: UInt8, b: UInt8
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    init(_ color: ActionRGB) {
        func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        self.init(byte(color.red), byte(color.green), byte(color.blue))
    }
    /// Linear mix towards another colour (0 keeps this one).
    func mixed(with other: Ink, _ amount: Double) -> Ink {
        let t = max(0, min(1, amount))
        func channel(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return Ink(channel(r, other.r), channel(g, other.g), channel(b, other.b))
    }
    func scaled(_ factor: Double) -> Ink {
        func channel(_ a: UInt8) -> UInt8 { UInt8(max(0, min(255, (Double(a) * factor).rounded()))) }
        return Ink(channel(r), channel(g), channel(b))
    }
}

/// A small RGBA canvas drawn with integer coordinates and enlarged with nearest-neighbour sampling.
struct Pixels {
    let width: Int, height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, background: Ink) {
        self.width = width; self.height = height
        bytes = [UInt8](repeating: 255, count: width * height * 4)
        rect(0, 0, width, height, background)
    }

    func ink(_ x: Int, _ y: Int) -> Ink {
        guard x >= 0, y >= 0, x < width, y < height else { return Ink(0, 0, 0) }
        let i = (y * width + x) * 4
        return Ink(bytes[i], bytes[i + 1], bytes[i + 2])
    }
    mutating func set(_ x: Int, _ y: Int, _ color: Ink) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = color.r; bytes[i + 1] = color.g; bytes[i + 2] = color.b
    }
    /// Draws a colour over what is there; `alpha` 1 replaces it.
    mutating func blend(_ x: Int, _ y: Int, _ color: Ink, _ alpha: Double) {
        guard alpha > 0 else { return }
        if alpha >= 1 { set(x, y, color); return }
        set(x, y, ink(x, y).mixed(with: color, alpha))
    }
    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Ink) {
        let left = max(0, x), right = min(width, x + w), top = max(0, y), bottom = min(height, y + h)
        guard left < right, top < bottom else { return }
        for row in top..<bottom { for col in left..<right {
            let i = (row * width + col) * 4
            bytes[i] = color.r; bytes[i + 1] = color.g; bytes[i + 2] = color.b
        } }
    }
    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Ink, alpha: Double) {
        guard w > 0, h > 0 else { return }
        for row in y..<(y + h) { for col in x..<(x + w) { blend(col, row, color, alpha) } }
    }
    mutating func line(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ color: Ink, alpha: Double = 1) {
        let steps = max(abs(x2 - x1), abs(y2 - y1))
        guard steps > 0 else { blend(x1, y1, color, alpha); return }
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            blend(x1 + Int((Double(x2 - x1) * t).rounded()), y1 + Int((Double(y2 - y1) * t).rounded()), color, alpha)
        }
    }
    /// A line drawn with a square brush, so limbs and tubes get a pixel-art thickness.
    mutating func stroke(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, width brush: Int, _ color: Ink) {
        let steps = max(abs(x2 - x1), abs(y2 - y1))
        let offset = (brush - 1) / 2
        for step in 0...max(1, steps) {
            let t = steps == 0 ? 0 : Double(step) / Double(steps)
            let x = x1 + Int((Double(x2 - x1) * t).rounded()), y = y1 + Int((Double(y2 - y1) * t).rounded())
            rect(x - offset, y - offset, brush, brush, color)
        }
    }
    mutating func polygon(_ points: [(Int, Int)], _ color: Ink, alpha: Double = 1) {
        let top = max(0, points.map(\.1).min() ?? 0), bottom = min(height - 1, points.map(\.1).max() ?? 0)
        guard top <= bottom else { return }
        for y in top...bottom {
            var xs: [Int] = []
            for index in points.indices {
                let a = points[index], b = points[(index + 1) % points.count]
                if (a.1 <= y && b.1 > y) || (b.1 <= y && a.1 > y) {
                    xs.append(a.0 + (y - a.1) * (b.0 - a.0) / (b.1 - a.1))
                }
            }
            xs.sort()
            for i in stride(from: 0, to: max(0, xs.count - 1), by: 2) {
                if alpha >= 1 { rect(xs[i], y, xs[i + 1] - xs[i] + 1, 1, color) }
                else { for x in xs[i]...xs[i + 1] { blend(x, y, color, alpha) } }
            }
        }
    }
    /// A circle one pixel thick, symmetric about its centre pixel.
    mutating func ring(_ cx: Int, _ cy: Int, _ radius: Int, _ color: Ink) {
        for dy in -radius...radius { for dx in -radius...radius {
            if abs(sqrt(Double(dx * dx + dy * dy)) - Double(radius)) <= 0.5 { set(cx + dx, cy + dy, color) }
        } }
    }
    mutating func disc(_ cx: Int, _ cy: Int, _ radius: Int, _ color: Ink, alpha: Double = 1) {
        for dy in -radius...radius { for dx in -radius...radius where dx * dx + dy * dy <= radius * radius + radius / 2 {
            blend(cx + dx, cy + dy, color, alpha)
        } }
    }

    // MARK: Text

    /// A 3 × 5 pixel face, enough for neon signs. Unknown characters are blank.
    private static let glyphs: [Character: [String]] = [
        "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"], "C": ["011", "100", "100", "100", "011"],
        "D": ["110", "101", "101", "101", "110"], "E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
        "G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"], "I": ["111", "010", "010", "010", "111"],
        "J": ["001", "001", "001", "101", "010"], "K": ["101", "101", "110", "101", "101"], "L": ["100", "100", "100", "100", "111"],
        "M": ["101", "111", "111", "101", "101"], "N": ["110", "101", "101", "101", "101"], "O": ["111", "101", "101", "101", "111"],
        "P": ["110", "101", "110", "100", "100"], "Q": ["010", "101", "101", "110", "011"], "R": ["110", "101", "110", "101", "101"],
        "S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
        "V": ["101", "101", "101", "101", "010"], "W": ["101", "101", "111", "111", "101"], "X": ["101", "101", "010", "101", "101"],
        "Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"],
        "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"], "2": ["110", "001", "010", "100", "111"],
        "3": ["110", "001", "010", "001", "110"], "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "110", "001", "110"],
        "6": ["011", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"], "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "110"],
        ".": ["000", "000", "000", "000", "010"], ":": ["000", "010", "000", "010", "000"], "·": ["000", "000", "010", "000", "000"],
        "-": ["000", "000", "111", "000", "000"], "/": ["001", "001", "010", "100", "100"], "%": ["101", "001", "010", "100", "101"],
        "+": ["000", "010", "111", "010", "000"]
    ]
    static func textWidth(_ text: String) -> Int { max(0, text.count * 4 - 1) }
    mutating func text(_ text: String, x: Int, y: Int, _ color: Ink, alpha: Double = 1) {
        for (index, character) in text.uppercased().enumerated() {
            for (row, bits) in (Self.glyphs[character] ?? []).enumerated() {
                for (col, bit) in bits.enumerated() where bit == "1" { blend(x + index * 4 + col, y + row, color, alpha) }
            }
        }
    }

    // MARK: Output

    func image() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// A drawing surface whose y axis starts `rowsAbove` rows below the top of the image, so negative y reaches the extra sky
/// the hero scene has above the strip. With `rowsAbove` 0 it draws exactly like `Pixels`.
struct PixelLayer {
    private(set) var base: Pixels
    let rowsAbove: Int
    var width: Int { base.width }
    /// Rows from y = 0 down: the strip itself.
    var height: Int { base.height - rowsAbove }

    init(width: Int, height: Int, rowsAbove: Int, background: Ink) {
        base = Pixels(width: width, height: height + rowsAbove, background: background); self.rowsAbove = rowsAbove
    }
    func ink(_ x: Int, _ y: Int) -> Ink { base.ink(x, y + rowsAbove) }
    mutating func set(_ x: Int, _ y: Int, _ color: Ink) { base.set(x, y + rowsAbove, color) }
    mutating func blend(_ x: Int, _ y: Int, _ color: Ink, _ alpha: Double) { base.blend(x, y + rowsAbove, color, alpha) }
    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Ink) { base.rect(x, y + rowsAbove, w, h, color) }
    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Ink, alpha: Double) { base.rect(x, y + rowsAbove, w, h, color, alpha: alpha) }
    mutating func line(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ color: Ink, alpha: Double = 1) {
        base.line(x1, y1 + rowsAbove, x2, y2 + rowsAbove, color, alpha: alpha)
    }
    mutating func stroke(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, width brush: Int, _ color: Ink) {
        base.stroke(x1, y1 + rowsAbove, x2, y2 + rowsAbove, width: brush, color)
    }
    mutating func polygon(_ points: [(Int, Int)], _ color: Ink, alpha: Double = 1) { base.polygon(points.map { ($0.0, $0.1 + rowsAbove) }, color, alpha: alpha) }
    mutating func ring(_ cx: Int, _ cy: Int, _ radius: Int, _ color: Ink) { base.ring(cx, cy + rowsAbove, radius, color) }
    mutating func disc(_ cx: Int, _ cy: Int, _ radius: Int, _ color: Ink, alpha: Double = 1) { base.disc(cx, cy + rowsAbove, radius, color, alpha: alpha) }
    mutating func text(_ text: String, x: Int, y: Int, _ color: Ink, alpha: Double = 1) { base.text(text, x: x, y: y + rowsAbove, color, alpha: alpha) }
}

/// Deterministic, well-mixed integers for placing scenery without a random generator.
func pixelHash(_ a: Int, _ b: Int = 0) -> Int {
    var h = UInt64(truncatingIfNeeded: a) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(truncatingIfNeeded: b) &* 0xC2B2_AE3D_27D4_EB4F
    h ^= h >> 29; h = h &* 0xBF58_476D_1CE4_E5B9; h ^= h >> 32
    return Int(h & 0x7fff_ffff)
}
