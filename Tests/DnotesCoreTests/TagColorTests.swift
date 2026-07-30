import Foundation
import Testing
@testable import DnotesCore

// MARK: - the palette itself

@Test func paletteHasEightDistinctColors() {
    #expect(TagPalette.count == 8)
    #expect(Set(TagPalette.colors.map(\.name)).count == 8)
    #expect(Set(TagPalette.colors.map { "\($0.light)" }).count == 8)
    #expect(Set(TagPalette.colors.map { "\($0.dark)" }).count == 8)
}

/// The measured floor the palette was chosen against. A tag is text, so it takes the
/// WCAG *text* bar of 4.5:1 rather than the 3:1 a chart fill would — and it takes it on
/// both surfaces, which is the whole reason the light and dark steps differ.
@Test func everyColorIsReadableOnItsOwnSurface() {
    let light = TagColor.RGB(hex: "#f0f0ee")   // the window's light surface
    let dark = TagColor.RGB(hex: "#262626")    // and its dark one

    for color in TagPalette.colors {
        let onLight = contrastRatio(color.light, light)
        let onDark = contrastRatio(color.dark, dark)
        #expect(onLight >= 4.5, "\(color.name) on light: \(onLight)")
        #expect(onDark >= 4.5, "\(color.name) on dark: \(onDark)")
    }
}

/// Blue belongs to links (`EntryLinks` draws them in `NSColor.linkColor`). A tag that
/// reads as blue reads as a link that does not work, so the palette keeps a guard band
/// around blue's hue.
///
/// Measured in OKLCH, which is the space the palette was built in: comparing RGB
/// channels instead calls violet blue, because violet genuinely has the most blue in it
/// while looking nothing like a link.
@Test func noColorImpersonatesALink() {
    let linkHue = okHue(TagColor.RGB(hex: "#0a84ff"))   // macOS system blue

    for color in TagPalette.colors {
        for (theme, rgb) in [("light", color.light), ("dark", color.dark)] {
            let separation = hueDistance(okHue(rgb), linkHue)
            #expect(separation >= 40, "\(color.name) \(theme) sits \(separation)° from link blue")
        }
    }
}

private func hueDistance(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d)
}

/// OKLCH hue, in degrees.
private func okHue(_ rgb: TagColor.RGB) -> Double {
    let linear = { (v: Double) in v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    let (r, g, b) = (linear(rgb.red), linear(rgb.green), linear(rgb.blue))

    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

    let aStar = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let bStar = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return (atan2(bStar, aStar) * 180 / .pi).truncatingRemainder(dividingBy: 360) + 360
}

private func contrastRatio(_ a: TagColor.RGB, _ b: TagColor.RGB) -> Double {
    let luminance = { (c: TagColor.RGB) -> Double in
        let channel = { (v: Double) in v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }
    let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
    return (high + 0.05) / (low + 0.05)
}

// MARK: - the automatic colour

/// The hash is spelled out rather than taken from `Hasher` so that it cannot move
/// between launches; these are the literal slots this build derives. If the palette or
/// the hash ever changes, every unassigned tag changes colour at once — that is a
/// decision, and this test is what makes it a deliberate one instead of a surprise.
@Test(arguments: [
    ("review", 1), ("call", 1), ("daily", 6), ("hotfixes", 7),
    ("minotoring", 7), ("infra", 5), ("oss", 4),
])
func hashedSlotsAreStable(_ tag: String, _ slot: Int) {
    #expect(TagPalette.slot(for: tag) == slot)
}

@Test func slotsStayInsideThePalette() {
    for tag in ["a", "", "инфра", "very-long-tag-name-with-many-parts", "v2", "🙂"] {
        #expect(TagPalette.colors.indices.contains(TagPalette.slot(for: tag)))
    }
}

@Test func caseDoesNotChangeTheColor() {
    #expect(TagPalette.slot(for: "Review") == TagPalette.slot(for: "review"))
    #expect(TagPalette.slot(for: "REVIEW") == TagPalette.slot(for: "review"))
}

// MARK: - handing colours out

/// Why `assignColors` exists at all. On its own the hash puts `#review` and `#call` on
/// one colour and `#hotfixes` and `#minotoring` on another — three colours for five
/// tags, with five of eight slots idle. Assignment is what spends the palette.
@MainActor
@Test func assignmentSeparatesTagsTheHashCollides() {
    let tags = ["review", "call", "daily", "hotfixes", "minotoring"]
    #expect(Set(tags.map(TagPalette.slot(for:))).count == 3)   // the problem

    let settings = SettingsStore(defaults: freshDefaults())
    settings.assignColors(for: tags)
    #expect(Set(tags.map(settings.colorSlot(for:))).count == 5) // the fix
}

@MainActor
@Test func theFirstEightTagsAllGetDifferentColors() {
    let tags = ["review", "call", "daily", "hotfixes", "minotoring", "infra", "oss", "vstor"]
    let settings = SettingsStore(defaults: freshDefaults())
    settings.assignColors(for: tags)
    #expect(Set(tags.map(settings.colorSlot(for:))).count == TagPalette.count)
}

/// A tag keeps the colour it was given. This is the property the whole stored-assignment
/// design exists for: recognising `#review` by colour tomorrow only works if a *different*
/// tag appearing today cannot move it.
@MainActor
@Test func anAssignedColorNeverMovesWhenNewTagsArrive() {
    let settings = SettingsStore(defaults: freshDefaults())
    settings.assignColors(for: ["review"])
    let original = settings.colorSlot(for: "review")

    settings.assignColors(for: ["review", "call", "daily", "infra", "oss", "vstor", "spi", "perf", "docs"])
    #expect(settings.colorSlot(for: "review") == original)
}

@MainActor
@Test func assigningIsIdempotent() {
    let settings = SettingsStore(defaults: freshDefaults())
    settings.assignColors(for: ["review", "call"])
    let first = settings.tagColorAssignments

    settings.assignColors(for: ["review", "call"])
    #expect(settings.tagColorAssignments == first)
}

/// Past eight tags colours must repeat — there are only eight. What matters is that the
/// ninth tag lands on a *least*-used colour rather than piling onto a busy one.
@MainActor
@Test func theNinthTagReusesAColorEvenly() {
    let settings = SettingsStore(defaults: freshDefaults())
    let nine = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    settings.assignColors(for: nine)

    var counts: [Int: Int] = [:]
    for tag in nine { counts[settings.colorSlot(for: tag), default: 0] += 1 }
    #expect(counts.values.max() == 2)
    #expect(counts.count == TagPalette.count)
}

@MainActor
@Test func assignmentsSurviveARelaunch() {
    let defaults = freshDefaults()
    let first = SettingsStore(defaults: defaults)
    first.assignColors(for: ["review", "call", "daily"])
    let before = ["review", "call", "daily"].map(first.colorSlot(for:))

    let second = SettingsStore(defaults: defaults)
    #expect(["review", "call", "daily"].map(second.colorSlot(for:)) == before)
}

/// A colour the user picked by hand counts as taken, so automatic assignment routes
/// around it instead of doubling up on it while other colours sit unused.
@MainActor
@Test func assignmentAvoidsAColorTheUserAlreadyChose() {
    let settings = SettingsStore(defaults: freshDefaults())
    settings.setColorSlot(0, for: "pinned")
    settings.assignColors(for: ["pinned", "a", "b", "c", "d", "e", "f", "g"])

    let auto = ["a", "b", "c", "d", "e", "f", "g"].map(settings.colorSlot(for:))
    #expect(!auto.contains(0))
    #expect(Set(auto).count == 7)
}

// MARK: - the manual override

@MainActor
@Test func overrideWinsOverTheHashAndAutoRestoresIt() {
    let settings = SettingsStore(defaults: freshDefaults())
    let automatic = settings.colorSlot(for: "review")

    settings.setColorSlot(5, for: "review")
    #expect(settings.colorSlot(for: "review") == 5)
    #expect(settings.color(for: "review").name == TagPalette.colors[5].name)

    settings.setColorSlot(nil, for: "review")
    #expect(settings.colorSlot(for: "review") == automatic)
    // Restored by removal, not by storing today's hash: a frozen copy would stop
    // following the palette.
    #expect(settings.tagColorOverrides.isEmpty)
}

@MainActor
@Test func anOverrideAppliesRegardlessOfCase() {
    let settings = SettingsStore(defaults: freshDefaults())
    settings.setColorSlot(3, for: "Review")
    #expect(settings.colorSlot(for: "review") == 3)
    #expect(settings.colorSlot(for: "REVIEW") == 3)
}

@MainActor
@Test func overridesSurviveARelaunch() {
    let defaults = freshDefaults()
    SettingsStore(defaults: defaults).setColorSlot(6, for: "infra")
    #expect(SettingsStore(defaults: defaults).colorSlot(for: "infra") == 6)
}

@MainActor
@Test func aSlotOutsideThePaletteIsIgnoredRatherThanStored() {
    let settings = SettingsStore(defaults: freshDefaults())
    settings.setColorSlot(99, for: "review")
    #expect(settings.tagColorOverrides.isEmpty)
    #expect(settings.colorSlot(for: "review") == TagPalette.slot(for: "review"))
}

/// A slot that was valid in an older build (or was hand-edited) must not crash the app
/// or paint an out-of-range colour — the tag falls back to automatic.
@MainActor
@Test func aStoredSlotFromAnotherPaletteIsDropped() {
    let defaults = freshDefaults()
    defaults.set(["review": 42, "infra": 3], forKey: "dnotes.tagColorOverrides")

    let settings = SettingsStore(defaults: defaults)
    #expect(settings.colorSlot(for: "review") == TagPalette.slot(for: "review"))
    #expect(settings.colorSlot(for: "infra") == 3)
}

private func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: "dnotes.tests.\(UUID().uuidString)")!
    defaults.removePersistentDomain(forName: defaults.description)
    return defaults
}
