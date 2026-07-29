import Foundation
import Observation

/// Completion state for the capture field. Lives in the core rather than the view
/// because this is the part of tagging that has edge cases worth testing.
@MainActor
@Observable
public final class TagCompletionModel {
    public private(set) var isActive: Bool = false
    public private(set) var suggestions: [TagCount] = []
    public private(set) var selectedIndex: Int = 0
    /// Non-nil when what has been typed is not an existing tag: the "create tag" item.
    public private(set) var newTagName: String?

    public init() {}

    /// Recomputed on every keystroke over the tag currently being typed — the one
    /// whose `#` is the last tag opener in the text and which has not been closed by
    /// a space yet.
    public func update(text: String, available: [TagCount]) {
        guard let typed = Self.tagBeingTyped(in: text) else {
            isActive = false
            suggestions = []
            newTagName = nil
            return
        }

        isActive = true
        suggestions = typed.isEmpty
            ? available
            : available.filter { $0.tag.lowercased().hasPrefix(typed.lowercased()) }
        newTagName = (typed.isEmpty || suggestions.contains { $0.tag == typed }) ? nil : typed
        selectedIndex = 0
    }

    public func moveSelection(by delta: Int) {
        let count = suggestions.count + (newTagName == nil ? 0 : 1)
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    /// Replaces the partial tag with the selected one and leaves a trailing space,
    /// so the next word can be typed without reaching for the space bar first.
    public func complete(in text: String) -> String {
        let chosen: String
        if selectedIndex < suggestions.count {
            chosen = suggestions[selectedIndex].tag
        } else if let newTagName {
            chosen = newTagName
        } else {
            return text
        }

        guard let hash = Self.lastTagOpenerIndex(in: text) else { return text }
        return String(text[text.startIndex...hash]) + chosen + " "
    }

    /// Appending a frequent tag must not move the caret (§6), so it goes at the end
    /// and the field's selection is left alone by the caller.
    public static func appending(_ tag: String, to text: String) -> String {
        guard !TagScanner.tags(in: text).contains(tag) else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "#\(tag)" : trimmed + " #\(tag)"
    }

    // MARK: - scanning

    /// The `#` that opens the tag currently being typed, if the caret is inside one.
    /// Same opening rules as `TagScanner`, so a URL anchor never starts completion.
    static func lastTagOpenerIndex(in text: String) -> String.Index? {
        var opener: String.Index?
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "#", TagScanner.canOpenTag(after: previous) {
                opener = index
            } else if opener != nil, !TagScanner.isBodyCharacter(character) {
                opener = nil
            }
            previous = character
            index = text.index(after: index)
        }
        return opener
    }

    static func tagBeingTyped(in text: String) -> String? {
        guard let opener = lastTagOpenerIndex(in: text) else { return nil }
        return String(text[text.index(after: opener)...])
    }
}
