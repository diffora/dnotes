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
        issueURLTemplate = defaults.string(forKey: "dnotes.issueURLTemplate") ?? ""
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

    /// Where an issue key like `ABC-1234` points. `{key}` is substituted. Empty by
    /// default: only the reader knows which tracker their keys live in, and a guessed
    /// host would make every key a broken link.
    public var issueURLTemplate: String {
        didSet { defaults.set(issueURLTemplate, forKey: "dnotes.issueURLTemplate") }
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
