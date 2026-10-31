import AppKit
import CoderSwitchCore

/// Draws the menu bar meter: the followed provider's logo and two thin bars,
/// top = session usage, bottom = weekly usage.
///
/// The image is not a template, so the bars can turn orange and red. The logo and the
/// low-usage bars use the menu bar's own foreground color (white on a dark menu bar),
/// which the drawing handler resolves from the current drawing appearance.
/// A nil fraction means "no data": its bar draws as an empty dimmed track.
enum MenuBarMeterRenderer {
    static let height: CGFloat = 18
    static let size = NSSize(width: 42, height: height)

    private static let logoRect = NSRect(x: 1, y: 2, width: 14, height: 14)
    private static let switchGlyphRect = NSRect(x: 1, y: 4.5, width: 14, height: 9)
    private static let barX: CGFloat = 20
    private static let barWidth: CGFloat = 21
    private static let barHeight: CGFloat = 3.5

    /// Usage above these fractions turns a bar orange, then red.
    static let warningFraction = 0.5
    static let criticalFraction = 0.8

    static func image(for state: MenuBarMeterState) -> NSImage {
        let reading = state.reading
        let provider = state.provider
        let hasData = reading.session != nil || reading.weekly != nil
        let image = NSImage(size: size, flipped: false) { _ in
            let foreground = foregroundColor()
            let glyphColor = foreground.withAlphaComponent(hasData ? 1 : 0.55)
            if let provider, let logo = logo(for: provider) {
                drawTinted(logo, in: logoRect, color: glyphColor)
            } else {
                drawSwitchGlyph(color: glyphColor)
            }
            drawBar(fraction: reading.session, y: 10.25, foreground: foreground)
            drawBar(fraction: reading.weekly, y: 4.25, foreground: foreground)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = state.tooltip
        return image
    }

    static func fillColor(for fraction: Double, foreground: NSColor) -> NSColor {
        if fraction > criticalFraction { return .systemRed }
        if fraction > warningFraction { return .systemOrange }
        return foreground
    }

    /// White on a dark menu bar, black on a light one.
    private static func foregroundColor() -> NSColor {
        isDark(NSAppearance.currentDrawing()) ? .white : .black
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return match == .darkAqua || match == .vibrantDark
    }

    /// The bundled brand logo, or the provider's SF Symbol for custom providers.
    private static func logo(for provider: Provider) -> NSImage? {
        if let name = provider.logoAssetName, let image = NSImage(named: "ProviderLogos/\(name)") {
            return image
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return NSImage(systemSymbolName: provider.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    /// Draws a one-color image aspect-fit in `rect`, recolored with `color`.
    private static func drawTinted(_ image: NSImage, in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext, image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let fitted = NSRect(
            x: rect.midX - image.size.width * scale / 2,
            y: rect.midY - image.size.height * scale / 2,
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        // The layer keeps the source-atop fill from touching anything drawn before the logo.
        context.beginTransparencyLayer(in: fitted, auxiliaryInfo: nil)
        image.draw(in: fitted)
        color.setFill()
        fitted.fill(using: .sourceAtop)
        context.endTransparencyLayer()
    }

    /// The CoderSwitch toggle, shown when no account is followed.
    private static func drawSwitchGlyph(color: NSColor) {
        color.setStroke()
        let track = NSBezierPath(roundedRect: switchGlyphRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.75, yRadius: 3.75)
        track.lineWidth = 1.5
        track.stroke()

        color.setFill()
        let knobDiameter: CGFloat = 5
        let knob = NSRect(
            x: switchGlyphRect.maxX - 2.75 - knobDiameter,
            y: switchGlyphRect.midY - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )
        NSBezierPath(ovalIn: knob).fill()
    }

    private static func drawBar(fraction: Double?, y: CGFloat, foreground: NSColor) {
        let track = NSRect(x: barX, y: y, width: barWidth, height: barHeight)
        let radius = barHeight / 2
        foreground.withAlphaComponent(fraction == nil ? 0.22 : 0.32).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard let fraction, fraction > 0 else { return }
        fillColor(for: fraction, foreground: foreground).setFill()
        var fill = track
        fill.size.width = max(barHeight, barWidth * min(1, fraction))
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
