import AppKit

/// Draws the menu bar meter: a small switch glyph and two thin bars,
/// top = session usage, bottom = weekly usage.
///
/// The result is a template image, so macOS tints it for light and dark menu bars.
/// A nil fraction means "no data": its bar draws as an empty dimmed track.
enum MenuBarMeterRenderer {
    static let height: CGFloat = 18
    static let size = NSSize(width: 42, height: height)

    private static let glyphRect = NSRect(x: 1, y: 4.5, width: 14, height: 9)
    private static let barX: CGFloat = 20
    private static let barWidth: CGFloat = 21
    private static let barHeight: CGFloat = 3.5

    static func image(session: Double?, weekly: Double?) -> NSImage {
        let hasData = session != nil || weekly != nil
        let image = NSImage(size: size, flipped: false) { _ in
            drawGlyph(alpha: hasData ? 1 : 0.55)
            drawBar(fraction: session, y: 10.25)
            drawBar(fraction: weekly, y: 4.25)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawGlyph(alpha: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setStroke()
        let track = NSBezierPath(roundedRect: glyphRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.75, yRadius: 3.75)
        track.lineWidth = 1.5
        track.stroke()

        NSColor.black.withAlphaComponent(alpha).setFill()
        let knobDiameter: CGFloat = 5
        let knob = NSRect(
            x: glyphRect.maxX - 2.75 - knobDiameter,
            y: glyphRect.midY - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )
        NSBezierPath(ovalIn: knob).fill()
    }

    private static func drawBar(fraction: Double?, y: CGFloat) {
        let track = NSRect(x: barX, y: y, width: barWidth, height: barHeight)
        let radius = barHeight / 2
        NSColor.black.withAlphaComponent(fraction == nil ? 0.22 : 0.32).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard let fraction, fraction > 0 else { return }
        NSColor.black.setFill()
        var fill = track
        fill.size.width = max(barHeight, barWidth * min(1, fraction))
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
