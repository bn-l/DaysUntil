import AppKit
import OSLog

private let logger = Logger(subsystem: "com.bn-l.days-until", category: "BadgeIcon")

/// Renders the menubar badge: a filled rounded square with the day count
/// punched out of it, so the digits are transparent against the menubar.
/// Normally rendered as a template image — the system draws it white on a
/// dark menubar (and black on a light one) and handles click highlighting.
/// With a flame intensity > 0 the image can't be a template (templates are
/// alpha-only, the red/orange would be lost), so the square color is chosen
/// from `darkAppearance` instead.
enum BadgeIcon {
    static let size: CGFloat = 18
    private static let cornerRadius: CGFloat = 4.5

    static func image(days: Int, flameIntensity: Double = 0, darkAppearance: Bool = true) -> NSImage {
        let flames = flameIntensity > 0
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else {
                logger.error("No CGContext available for badge rendering")
                return false
            }
            // The handler can run inside someone else's context (e.g. when
            // composited into another image) — don't leak clip/blend state.
            ctx.saveGState()
            defer { ctx.restoreGState() }
            let square = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            squareColor(flameIntensity: flameIntensity, darkAppearance: darkAppearance).setFill()
            square.fill()

            if flames {
                ctx.saveGState()
                square.addClip()
                drawFlames(in: rect, intensity: min(1, flameIntensity))
                ctx.restoreGState()
            }

            ctx.setBlendMode(.destinationOut)
            if days > 999 {
                let topHalf = CGRect(x: 0, y: rect.height / 2, width: rect.width, height: rect.height / 2)
                let bottomHalf = CGRect(x: 0, y: 0, width: rect.width, height: rect.height / 2)
                punch("999", centeredIn: topHalf, pointSize: 7)
                punch("+", centeredIn: bottomHalf, pointSize: 9)
            } else {
                punch("\(days)", centeredIn: rect, pointSize: 11)
            }
            return true
        }
        image.isTemplate = !flames
        image.accessibilityDescription = days > 999 ? "More than 999 days" : "\(days) days"
        return image
    }

    /// Without flames the image is a template, so only alpha matters and the
    /// fill is plain black. With flames the square simulates template
    /// behavior (white on dark, black on light) and warms toward orange as
    /// intensity rises — subtle at 5 days out, clearly heated at day zero.
    private static func squareColor(flameIntensity: Double, darkAppearance: Bool) -> NSColor {
        guard flameIntensity > 0 else { return .black }
        let base: NSColor = darkAppearance ? .white : .black
        let ember = NSColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
        return base.blended(withFraction: 0.4 * min(1, flameIntensity), of: ember) ?? base
    }

    /// Two static layers of wavy tongues rising from the bottom edge —
    /// deliberately not animated. Intensity 0...1 scales their height.
    private static func drawFlames(in rect: CGRect, intensity: Double) {
        let maxHeight = 3 + 8 * intensity
        fillTongues(
            in: rect, maxHeight: maxHeight,
            peaks: [0.9, 0.55, 1.0, 0.7],
            color: NSColor(red: 0.85, green: 0.15, blue: 0.05, alpha: 0.9)
        )
        fillTongues(
            in: rect, maxHeight: maxHeight * 0.62,
            peaks: [0.6, 1.0, 0.5, 0.85],
            color: NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.95)
        )
    }

    private static func fillTongues(in rect: CGRect, maxHeight: CGFloat, peaks: [CGFloat], color: NSColor) {
        let path = NSBezierPath()
        let segment = rect.width / CGFloat(peaks.count)
        let valley = rect.minY + maxHeight * 0.25
        let edge = rect.minY + maxHeight * 0.4
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX, y: edge))
        for (index, peak) in peaks.enumerated() {
            let startX = rect.minX + CGFloat(index) * segment
            let peakX = startX + segment / 2
            let peakY = rect.minY + maxHeight * peak
            path.curve(
                to: CGPoint(x: startX + segment, y: index == peaks.count - 1 ? edge : valley),
                controlPoint1: CGPoint(x: peakX - segment * 0.18, y: peakY),
                controlPoint2: CGPoint(x: peakX + segment * 0.18, y: peakY)
            )
        }
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.close()
        color.setFill()
        path.fill()
    }

    /// Draws `text` so it cuts a transparent hole in whatever was drawn
    /// beneath (context blend mode must already be `.destinationOut`).
    /// Digits are centered optically (baseline to cap height), shrinking
    /// the font when the text would overflow the rect.
    private static func punch(_ text: String, centeredIn rect: CGRect, pointSize: CGFloat) {
        let maxWidth = rect.width - 3
        var font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .bold)
        var width = (text as NSString).size(withAttributes: [.font: font]).width
        if width > maxWidth {
            font = NSFont.monospacedDigitSystemFont(ofSize: pointSize * maxWidth / width, weight: .bold)
            width = (text as NSString).size(withAttributes: [.font: font]).width
        }
        let baseline = rect.midY - font.capHeight / 2
        let origin = CGPoint(x: rect.midX - width / 2, y: baseline + font.descender)
        (text as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.black])
    }
}

extension BadgeIcon {
    /// Debug helper (`--render-icons <dir>`): writes upscaled PNGs of sample
    /// badges composited on a menubar-like background so the punched-out
    /// digits (and flames) are visible for inspection.
    static func writePreviews(to directory: URL) {
        struct Sample {
            let days: Int
            let flames: Bool
            let dark: Bool
            var name: String { "badge-\(days)\(flames ? "-flames" : "")\(dark ? "-dark" : "").png" }
        }
        var samples = [0, 5, 42, 365, 999, 1500, -12].map { Sample(days: $0, flames: false, dark: false) }
        for days in [5, 3, 1, 0] {
            samples.append(Sample(days: days, flames: true, dark: true))
            samples.append(Sample(days: days, flames: true, dark: false))
        }

        let scale: CGFloat = 8
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for sample in samples {
                let intensity = sample.flames ? (6.0 - Double(sample.days)) / 6.0 : 0
                let badge = image(days: sample.days, flameIntensity: intensity, darkAppearance: sample.dark)
                // Rasterize first — compositing a live drawing-handler image
                // inside another one distorts coordinates; the bitmap is also
                // exactly what the status bar will display.
                guard let badgeTiff = badge.tiffRepresentation,
                      let badgeBitmap = NSImage(data: badgeTiff) else {
                    logger.error("Badge rasterize failed for days=\(sample.days, privacy: .public)")
                    continue
                }
                let edge = size * scale
                let canvas = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
                    NSColor(white: sample.dark ? 0.15 : 0.75, alpha: 1).setFill()
                    rect.fill()
                    NSGraphicsContext.current?.imageInterpolation = .none
                    badgeBitmap.draw(in: rect.insetBy(dx: size, dy: size))
                    return true
                }
                guard let tiff = canvas.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    logger.error("Preview encode failed for days=\(sample.days, privacy: .public)")
                    continue
                }
                try png.write(to: directory.appending(path: sample.name))
            }
        } catch {
            logger.error("Preview write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
