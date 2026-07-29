import AppKit

/// The menu bar item's icon: the `d` monogram from the app icon, reduced to what
/// survives 18pt.
///
/// Drawn in code rather than shipped as an asset, for two reasons. A menu bar item
/// wants a *template* image — monochrome plus alpha, which macOS tints for light,
/// dark and highlighted bars — so the app icon's dark purple artwork cannot be used
/// here: on a dark menu bar it would be a dark smudge, and its stars and spine turn
/// to mud below about 32px. And a drawing handler is resolution-independent, so the
/// same code serves 1x, 2x and whatever menu bar height the system picks.
enum MenuBarIcon {
    /// Nominal size in points. The glyph is fitted inside this with a margin.
    static let size = NSSize(width: 18, height: 18)

    static func makeImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            path(boxSize: rect.width).stroke()
            return true
        }
        // Template: the colour above is ignored and macOS tints the alpha channel.
        image.isTemplate = true
        return image
    }

    /// A stroked bowl plus an ascender on its right edge — two shapes, no detail
    /// that cannot survive the size.
    private static func path(boxSize: CGFloat) -> NSBezierPath {
        let scale = boxSize / 18.0
        let lineWidth = 2.0 * scale

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round

        let bowlDiameter = 9.0 * scale
        path.appendOval(in: NSRect(x: 0, y: 0, width: bowlDiameter, height: bowlDiameter))

        let stemX = bowlDiameter - lineWidth / 2
        path.move(to: NSPoint(x: stemX, y: bowlDiameter / 2))
        path.line(to: NSPoint(x: stemX, y: 14.5 * scale))

        // Fit the *stroked* bounds — the round caps and the stroke width are what the
        // eye sees — into a box with a margin, then centre it. Without the margin the
        // glyph reaches all four edges and reads as oversized next to the system's own
        // items; without centring on the stroked bounds it sits visibly left of centre,
        // because of the empty space beside the bowl.
        let margin = 2.0 * scale
        let drawn = path.bounds.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        let available = boxSize - margin * 2
        let fit = min(available / drawn.width, available / drawn.height)

        let transform = NSAffineTransform()
        transform.translateX(by: (boxSize - drawn.width * fit) / 2,
                             yBy: (boxSize - drawn.height * fit) / 2)
        transform.scale(by: fit)
        transform.translateX(by: -drawn.minX, yBy: -drawn.minY)
        path.transform(using: transform as AffineTransform)
        path.lineWidth = lineWidth * fit

        return path
    }
}
