import Foundation
import Observation

/// Everything the app remembers between launches, except the pending queue.
/// The app is not sandboxed (§11), so a folder is a plain path — no bookmarks.
@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folderURL = Self.readFolder(defaults)
        captureHotKey = Self.readCombo(defaults, "dnotes.captureHotKey") ?? .captureDefault
        mainWindowHotKey = Self.readCombo(defaults, "dnotes.mainWindowHotKey") ?? .mainWindowDefault
        panelDraft = defaults.string(forKey: "dnotes.panelDraft") ?? ""
        completionFilter = Self.readFilter(defaults)
        tagLayout = defaults.string(forKey: "dnotes.tagLayout")
            .flatMap(TagLayout.init(rawValue:)) ?? .trailing
        issueURLTemplate = defaults.string(forKey: "dnotes.issueURLTemplate") ?? ""
        tagColorOverrides = Self.readSlots(defaults, "dnotes.tagColorOverrides")
        tagColorAssignments = Self.readSlots(defaults, "dnotes.tagColorAssignments")
    }

    public var folderURL: URL {
        didSet { defaults.set(folderURL.path, forKey: "dnotes.folderPath") }
    }

    public var captureHotKey: HotKeyCombo {
        didSet { write(captureHotKey, "dnotes.captureHotKey") }
    }

    public var mainWindowHotKey: HotKeyCombo {
        didSet { write(mainWindowHotKey, "dnotes.mainWindowHotKey") }
    }

    /// One line, typed but not confirmed. Exactly one slot, which is all that is
    /// needed: there is only one panel (§8).
    public var panelDraft: String {
        didSet { defaults.set(panelDraft, forKey: "dnotes.panelDraft") }
    }

    public var completionFilter: CompletionFilter {
        didSet { defaults.set(completionFilter.rawValue, forKey: "dnotes.completionFilter") }
    }

    /// Trailing by default, at the owner's request: the text of a note reads cleaner
    /// without its tags in the middle of it, and the tags line up in a column that can be
    /// scanned on its own. The cost is the one `TagLayout.trailing` documents — editing a
    /// row opens the stored line, so the text changes shape under the cursor.
    public var tagLayout: TagLayout {
        didSet { defaults.set(tagLayout.rawValue, forKey: "dnotes.tagLayout") }
    }

    /// Where an issue key like `ABC-1234` points. `{key}` is substituted. Empty by
    /// default: only the reader knows which tracker their keys live in, and a guessed
    /// host would make every key a broken link.
    public var issueURLTemplate: String {
        didSet { defaults.set(issueURLTemplate, forKey: "dnotes.issueURLTemplate") }
    }

    /// Tags whose colour the user picked by hand, folded name → palette slot. Only the
    /// exceptions are stored; everything absent here is coloured by `TagPalette.slot`.
    /// Keeping it sparse means the palette can gain a colour later without rewriting
    /// what the user chose, and a tag never carries a stored colour it never needed.
    public private(set) var tagColorOverrides: [String: Int] {
        didSet { defaults.set(tagColorOverrides, forKey: "dnotes.tagColorOverrides") }
    }

    /// Colours handed out automatically, folded name → slot. Recorded rather than
    /// recomputed because the assignment depends on which colours were already taken
    /// (see `assignColors`), and a tag must not change colour just because a *different*
    /// tag appeared later.
    public private(set) var tagColorAssignments: [String: Int] {
        didSet { defaults.set(tagColorAssignments, forKey: "dnotes.tagColorAssignments") }
    }

    /// The slot a tag is actually drawn in. Every view asks this rather than
    /// `TagPalette` directly, so the chip bar and the list can never disagree.
    ///
    /// Three answers in order of authority: what the user picked, what was handed out
    /// when the tag first appeared, and — for a tag nobody has assigned yet — the hash.
    /// The last case is what a row falls back to for the instant between a note arriving
    /// and `assignColors` running, so a new tag never flashes in the wrong colour.
    public func colorSlot(for tag: String) -> Int {
        let key = TagPalette.fold(tag)
        if let slot = tagColorOverrides[key], TagPalette.colors.indices.contains(slot) {
            return slot
        }
        if let slot = tagColorAssignments[key], TagPalette.colors.indices.contains(slot) {
            return slot
        }
        return TagPalette.slot(for: tag)
    }

    /// Gives a colour to every tag that does not have one yet.
    ///
    /// The hash alone is not good enough to ship: with eight colours it put two of five
    /// real tags on one colour and averaged 3.9 distinct colours per five tags —
    /// spending the palette on collisions. So the hash is only the *first* choice here.
    /// A tag takes its hashed colour when that colour is still free, and otherwise the
    /// least-used one, which keeps the first eight tags on eight different colours.
    ///
    /// The cost, stated where it will be found: a tag's colour now depends on what else
    /// existed when it first appeared, so the same tag can be a different colour in
    /// another folder or on another Mac. Within one install it never moves — which is
    /// the property that actually matters, since the colour is there to be recognised
    /// tomorrow, not to be quoted between machines.
    public func assignColors(for tags: [String]) {
        let known = Set(tagColorAssignments.keys).union(tagColorOverrides.keys)
        // Sorted so a batch of new tags is assigned in one definite order rather than in
        // whatever order a Set happened to iterate.
        let unassigned = Set(tags.map(TagPalette.fold)).subtracting(known).sorted()
        guard !unassigned.isEmpty else { return }

        var used: [Int: Int] = [:]
        for slot in tagColorAssignments.values { used[slot, default: 0] += 1 }
        for slot in tagColorOverrides.values { used[slot, default: 0] += 1 }

        for tag in unassigned {
            let preferred = TagPalette.slot(for: tag)
            let fewest = TagPalette.colors.indices.map { used[$0] ?? 0 }.min() ?? 0
            let slot = (used[preferred] ?? 0) == fewest
                ? preferred
                : TagPalette.colors.indices.first { (used[$0] ?? 0) == fewest } ?? preferred
            tagColorAssignments[tag] = slot
            used[slot, default: 0] += 1
        }
    }

    public func color(for tag: String) -> TagColor {
        TagPalette.colors[colorSlot(for: tag)]
    }

    /// `nil` restores the automatic colour — that is what "Auto" in the menu means, and
    /// it is why the entry is removed rather than set to the hashed value: a stored copy
    /// of today's hash would silently freeze if the palette ever changed.
    public func setColorSlot(_ slot: Int?, for tag: String) {
        let key = TagPalette.fold(tag)
        guard let slot, TagPalette.colors.indices.contains(slot) else {
            tagColorOverrides.removeValue(forKey: key)
            return
        }
        tagColorOverrides[key] = slot
    }

    /// Anything unreadable is dropped rather than repaired: a bad slot index is a colour
    /// preference, and losing one means a tag goes back to its automatic colour. This is
    /// also what happens to slots stored by a build whose palette was larger.
    private static func readSlots(_ defaults: UserDefaults, _ key: String) -> [String: Int] {
        let stored = defaults.dictionary(forKey: key) ?? [:]
        return stored.compactMapValues { value in
            guard let slot = value as? Int, TagPalette.colors.indices.contains(slot) else { return nil }
            return slot
        }
    }

    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/diffora/dnotes")
    }

    private func write(_ combo: HotKeyCombo, _ key: String) {
        defaults.set(try? JSONEncoder().encode(combo), forKey: key)
    }

    private static func readFolder(_ defaults: UserDefaults) -> URL {
        guard let path = defaults.string(forKey: "dnotes.folderPath"), !path.isEmpty else {
            return defaultFolder
        }
        return URL(fileURLWithPath: path)
    }

    /// Falls back to the boolean this setting used to be, so an existing install does
    /// not silently lose a preference it had already expressed.
    private static func readFilter(_ defaults: UserDefaults) -> CompletionFilter {
        if let raw = defaults.string(forKey: "dnotes.completionFilter"),
           let filter = CompletionFilter(rawValue: raw) {
            return filter
        }
        return defaults.bool(forKey: "dnotes.showsCompleted") ? .all : .completedToday
    }

    private static func readCombo(_ defaults: UserDefaults, _ key: String) -> HotKeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyCombo.self, from: data)
    }
}
