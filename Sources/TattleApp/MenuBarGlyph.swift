import AppKit

/// The menu bar glyph: a whistle, drawn as a template image so the system tints
/// it for light/dark menu bars. 24-unit artwork cropped to its bounding box at 1 unit = 1pt (22x16pt).
/// Idle = dim whistle, no rays. Active = full whistle whose three rays light up
/// one after another, hold, then go out in the same order (`activeSequence`).
enum MenuBarGlyph {
    /// Seconds per step of `activeSequence`; the full cycle is 10 steps.
    static let stepInterval: TimeInterval = 0.12

    /// Bit 0/1/2 = first/second/third ray lit.
    static let activeSequence: [UInt8] = [
        0b000, 0b001, 0b011, 0b111, 0b111, 0b111, 0b110, 0b100, 0b000, 0b000,
    ]

    static let idle = make(active: false, rays: 0)

    static func frame(rays: UInt8) -> NSImage { frames[Int(rays & 0b111)] }

    private static let frames: [NSImage] = (0..<8).map { make(active: true, rays: UInt8($0)) }

    private static let rays: [(from: CGPoint, to: CGPoint)] = [
        (CGPoint(x: 8.2, y: 7.2), CGPoint(x: 7.6, y: 5.6)),
        (CGPoint(x: 4.6, y: 9.7), CGPoint(x: 3.3, y: 8.6)),
        (CGPoint(x: 2.8, y: 13.6), CGPoint(x: 1.1, y: 13.3)),
    ]

    private static func make(active: Bool, rays lit: UInt8) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: -0.55, y: -5.3)  // crop to the art; 1 unit = 1pt
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)

            ctx.setAlpha(active ? 1 : 0.5)
            ctx.fillEllipse(in: CGRect(x: 4.8, y: 8.8, width: 12.4, height: 12.4))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 11, y: 8.8, width: 11, height: 4.8), cornerWidth: 1.3, cornerHeight: 1.3, transform: nil))
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: 8.8, y: 12.8, width: 4.4, height: 4.4))  // the whistle's hole

            ctx.setBlendMode(.normal)
            ctx.setAlpha(1)
            ctx.setLineWidth(1.6)
            for (index, ray) in Self.rays.enumerated() where lit & (1 << UInt8(index)) != 0 {
                ctx.move(to: ray.from)
                ctx.addLine(to: ray.to)
                ctx.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
