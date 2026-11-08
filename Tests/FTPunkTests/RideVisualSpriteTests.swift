import Testing
import FTPunkDomain
@testable import FTPunkApp

/// The sprite rider from the RG SP design: rider A's build in rider D's colours.
@Suite struct RideVisualSpriteTests {
    private func frame(time: Double) -> [Int: Ink] {
        var pixels: [Int: Ink] = [:]
        RideVisualSprite.draw(time: time) { x, y, ink in pixels[y * 1000 + x] = ink }
        return pixels
    }

    @Test func staysInsideItsBoxAndUsesRiderDColours() {
        let pixels = frame(time: 0.3)
        #expect(!pixels.isEmpty)
        for key in pixels.keys {
            let x = key % 1000, y = key / 1000
            #expect(x >= 0 && x < 60 && y >= 0 && y < 52)
        }
        let inks = Set(pixels.values.map { [$0.r, $0.g, $0.b] })
        #expect(inks.contains([0xf5, 0xd0, 0x20]), "yellow helmet and shorts")
        #expect(inks.contains([0x7a, 0x4a, 0xe0]), "violet jersey")
        #expect(!inks.contains([0x00, 0xb8, 0xa8]), "no rider A teal")
    }

    @Test func pedalsAndHoldsStillAtZero() {
        #expect(frame(time: 0) == frame(time: 0))
        #expect(frame(time: 0) != frame(time: 0.2))
    }

    @Test func sceneDrawsItOnlyWhenAsked() {
        let state = RideVisualState.make(.init(mode: .freeERG, phase: .riding, power: 200, cadence: 90, ftp: 250, target: 150))
        let plain = RideVisualRaster.pixels(RideVisualScene(state: state, animated: false))
        let sprite = RideVisualRaster.pixels(RideVisualScene(state: state, animated: false, spriteRider: true))
        #expect(plain.bytes != sprite.bytes)
    }
}
