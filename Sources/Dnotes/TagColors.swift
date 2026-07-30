import AppKit
import SwiftUI
import DnotesCore

extension TagColor.RGB {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension TagColor {
    /// One colour that answers differently in each theme, rather than two colours the
    /// views have to choose between. AppKit resolves it at draw time, which is the only
    /// thing that gets the list right: the window sits on an `NSVisualEffectView`, and
    /// its appearance can change under a view that is already on screen.
    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (isDark ? self.dark : self.light).nsColor
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}
