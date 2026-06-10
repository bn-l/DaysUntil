import AppKit
import Testing
@testable import DaysUntil

@Suite("BadgeIcon rendering")
struct BadgeIconTests {
    /// Rasterizes the badge and returns the bitmap plus a pixel sampler that
    /// works in fractional coordinates (0...1, origin top-left) so the tests
    /// hold regardless of backing scale. Colors come back in sRGB.
    private func rasterize(_ image: NSImage) throws -> (rep: NSBitmapImageRep, pixel: (Double, Double) -> NSColor?) {
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let pixel: (Double, Double) -> NSColor? = { fx, fy in
            let x = min(rep.pixelsWide - 1, Int(fx * Double(rep.pixelsWide)))
            let y = min(rep.pixelsHigh - 1, Int(fy * Double(rep.pixelsHigh)))
            return rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        }
        return (rep, pixel)
    }

    private func hasTransparentPixel(in rep: NSBitmapImageRep, xRange: ClosedRange<Double>, yRange: ClosedRange<Double>) -> Bool {
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                let fx = Double(x) / Double(rep.pixelsWide)
                let fy = Double(y) / Double(rep.pixelsHigh)
                guard xRange.contains(fx), yRange.contains(fy) else { continue }
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent < 0.5 {
                    return true
                }
            }
        }
        return false
    }

    @Test("Plain badge is an 18×18 template image")
    func plainBadgeIsTemplate() {
        let image = BadgeIcon.image(days: 42)

        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }

    @Test("Corners are transparent (rounded square), edges are opaque")
    func roundedCorners() throws {
        let image = BadgeIcon.image(days: 42)

        let (_, pixel) = try rasterize(image)

        let corner = try #require(pixel(0.0, 0.0))
        let midLeftEdge = try #require(pixel(0.06, 0.5))
        #expect(corner.alphaComponent < 0.1)
        #expect(midLeftEdge.alphaComponent > 0.9)
    }

    @Test("Digits are punched out — transparent pixels inside the square", arguments: [0, 8, 42, 365, -12])
    func digitsArePunched(days: Int) throws {
        let image = BadgeIcon.image(days: days)

        let (rep, _) = try rasterize(image)

        #expect(hasTransparentPixel(in: rep, xRange: 0.2...0.8, yRange: 0.2...0.8),
                "no punched digit pixels for days=\(days)")
    }

    @Test("Over 999 uses the stacked layout: punches in both the top and bottom halves")
    func stackedLayoutOver999() throws {
        let image = BadgeIcon.image(days: 1500)

        let (rep, _) = try rasterize(image)

        #expect(hasTransparentPixel(in: rep, xRange: 0.15...0.85, yRange: 0.05...0.45), "no '999' in top half")
        #expect(hasTransparentPixel(in: rep, xRange: 0.3...0.7, yRange: 0.55...0.95), "no '+' in bottom half")
    }

    @Test("Exactly 999 stays centered — bottom half has no '+' punched into it")
    func exactly999IsCentered() throws {
        let image = BadgeIcon.image(days: 999)

        let (rep, _) = try rasterize(image)

        #expect(hasTransparentPixel(in: rep, xRange: 0.15...0.85, yRange: 0.25...0.75))
        #expect(!hasTransparentPixel(in: rep, xRange: 0.3...0.7, yRange: 0.85...0.95),
                "999 must not use the stacked >999 layout")
    }

    @Test("Flame badge drops template mode and paints fire at the bottom")
    func flamesAreColored() throws {
        let image = BadgeIcon.image(days: 0, flameIntensity: 1, darkAppearance: true)

        #expect(!image.isTemplate)
        let (_, pixel) = try rasterize(image)

        // Bottom-center should be saturated flame (red dominant over blue).
        let flame = try #require(pixel(0.5, 0.93))
        #expect(flame.alphaComponent > 0.9)
        #expect(flame.redComponent > 0.5)
        #expect(flame.redComponent - flame.blueComponent > 0.2,
                "expected fire colors, got \(flame)")
    }

    @Test("Square warms toward orange as intensity rises, on both appearances")
    func emberTint() throws {
        for dark in [true, false] {
            let image = BadgeIcon.image(days: 1, flameIntensity: 1, darkAppearance: dark)

            let (_, pixel) = try rasterize(image)

            // Top of the square is above the flames — pure base color would
            // have r == b; the ember tint must push red above blue.
            let top = try #require(pixel(0.5, 0.08))
            #expect(top.redComponent - top.blueComponent > 0.05,
                    "no ember tint (dark=\(dark)): \(top)")
        }
    }

    @Test("Without flames the square stays neutral — no accidental tint")
    func plainBadgeStaysNeutral() throws {
        let image = BadgeIcon.image(days: 3)  // within flame range but intensity 0

        let (_, pixel) = try rasterize(image)

        let top = try #require(pixel(0.5, 0.08))
        #expect(abs(top.redComponent - top.blueComponent) < 0.01)
        #expect(image.isTemplate)
    }

    @Test("Flame heights scale with intensity")
    func flameHeightScales() throws {
        let ember = BadgeIcon.image(days: 5, flameIntensity: 1.0 / 6.0, darkAppearance: true)
        let blaze = BadgeIcon.image(days: 0, flameIntensity: 1.0, darkAppearance: true)

        func highestFlameRow(_ image: NSImage) throws -> Double {
            let (rep, _) = try rasterize(image)
            for y in 0..<rep.pixelsHigh {  // bitmap row 0 = top
                for x in 0..<rep.pixelsWide {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.alphaComponent > 0.5 else { continue }
                    if color.redComponent > 0.6, color.redComponent - color.blueComponent > 0.3 {
                        return Double(y) / Double(rep.pixelsHigh)
                    }
                }
            }
            return 1.0
        }

        let emberTop = try highestFlameRow(ember)
        let blazeTop = try highestFlameRow(blaze)
        #expect(blazeTop < emberTop, "day-zero flames (\(blazeTop)) should reach higher than 5-day embers (\(emberTop))")
        #expect(emberTop > 0.6, "5-day embers should stay in the bottom of the badge")
    }
}
