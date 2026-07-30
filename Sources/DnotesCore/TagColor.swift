import Foundation

/// The colour a tag is drawn in, in both themes.
///
/// Plain numbers rather than an `NSColor`: this layer knows nothing about AppKit, and
/// the palette is the one part of the feature worth holding to measured invariants in
/// tests rather than to somebody's taste.
public struct TagColor: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public let red: Double, green: Double, blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// `#rrggbb`. Traps on a malformed literal on purpose — the only caller is the
        /// palette below, and a typo there is a bug to fix, not a case to handle.
        public init(hex: String) {
            let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            precondition(digits.count == 6, "expected #rrggbb, got \(hex)")
            let value = UInt32(digits, radix: 16)!
            self.init(red: Double((value >> 16) & 0xff) / 255,
                      green: Double((value >> 8) & 0xff) / 255,
                      blue: Double(value & 0xff) / 255)
        }
    }

    /// The name is for the colour-picker menu, where a row of unlabelled swatches
    /// gives a screen reader nothing to say.
    public let name: String
    /// Steps chosen per theme, not one colour dimmed twice: a tag is *text*, and the
    /// lightness that makes a hue readable on white is not the one that works on grey.
    public let light: RGB
    public let dark: RGB
}

/// The eight tag colours, and the rule that maps a tag to one of them (§4.1 keeps tags
/// as plain text, so this is derived from the name and stored nowhere).
///
/// How these eight were chosen — the constraints are the interesting part, because most
/// of them are not negotiable:
///
/// - **Blue is missing on purpose.** `NSColor.linkColor` owns blue in this list already
///   (`EntryLinks`), so a ±45° guard around it is excluded. A cyan-blue tag beside a
///   link reads as a broken link.
/// - **Contrast ≥ 4.5:1 against both surfaces.** A tag is a word you read inside a
///   sentence, so it takes the WCAG *text* bar, not the 3:1 that fills and marks get.
///   This is what makes the light steps deep and wine-like rather than bright: on a
///   light surface, 4.5:1 pulls every hue down the lightness scale. Light themes in
///   editors look the same way for the same reason.
/// - **Teal is absent and cannot be added.** At the lightness 4.5:1 demands on a light
///   surface, sRGB cannot give cyan enough chroma to clear the "reads as grey" floor.
/// - **Red and orange cannot both be canonical.** They sit ~29° apart; a set holding
///   both collapses that pair. The hues here are spaced where the eye actually
///   separates them instead of on the round numbers.
///
/// What eight colours do **not** buy, stated plainly: they do not clear the pairwise
/// separation gates a chart palette must clear. Measured worst pair is ΔE 12.1 (light)
/// and 11.2 (dark) against a floor of 15, and under deuteranopia most of the set
/// converges. That is a deliberate trade, and it is only sound because the tag's own
/// name is always written right there — colour is a scanning aid here, never the thing
/// that carries identity. Where a specific pair does get in the way, the manual
/// override in `SettingsStore` moves one of them.
///
/// Slot *order* is free: the set was validated on all pairs, not adjacent ones, so
/// reordering cannot change its verdict. It is sorted by hue purely to be read.
public enum TagPalette {
    public static let colors: [TagColor] = [
        TagColor(name: "Crimson", light: .init(hex: "#b41a3d"), dark: .init(hex: "#ff6779")),
        TagColor(name: "Rust",    light: .init(hex: "#6c2700"), dark: .init(hex: "#ff996c")),
        TagColor(name: "Amber",   light: .init(hex: "#946400"), dark: .init(hex: "#c28400")),
        TagColor(name: "Olive",   light: .init(hex: "#505900"), dark: .init(hex: "#a6b700")),
        TagColor(name: "Emerald", light: .init(hex: "#007b62"), dark: .init(hex: "#00a786")),
        TagColor(name: "Violet",  light: .init(hex: "#64219c"), dark: .init(hex: "#cda5ff")),
        TagColor(name: "Orchid",  light: .init(hex: "#a73fa7"), dark: .init(hex: "#cf65ce")),
        TagColor(name: "Wine",    light: .init(hex: "#760048"), dark: .init(hex: "#ff92c4")),
    ]

    public static var count: Int { colors.count }

    /// The automatic colour for a tag: FNV-1a over the folded name, modulo the palette.
    ///
    /// A hash rather than "the order tags first appeared" so the answer does not depend
    /// on which notes happen to be loaded, on the order of a dictionary, or on the
    /// machine: `#review` is the same colour tomorrow, in another folder, on another
    /// Mac. FNV-1a is spelled out rather than taken from `Hasher`, whose output is
    /// seeded per process and would repaint every tag on every launch.
    public static func slot(for tag: String) -> Int {
        var hash: UInt32 = 0x811c9dc5
        for byte in fold(tag).utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return Int(hash % UInt32(count))
    }

    public static func color(for tag: String) -> TagColor {
        colors[slot(for: tag)]
    }

    /// Case is folded for colouring although `TagScanner` keeps it (`#OSS` and `#oss`
    /// are two tags in the filter bar): somebody who capitalised a tag by accident
    /// meant the same tag, and two shades of the same word is not information.
    /// Also the key manual overrides are stored under, so an override set on `#Review`
    /// applies to `#review`.
    public static func fold(_ tag: String) -> String {
        tag.lowercased()
    }
}
