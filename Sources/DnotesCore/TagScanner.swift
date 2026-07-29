import Foundation

/// Tags are `#word` substrings of the entry text (§4.1). There is no tag field
/// anywhere — this scanner is the only definition of what a tag is.
public enum TagScanner {
    /// Characters that may precede a `#` and still let it open a tag. Whitespace and
    /// line start also qualify. The stricter rule "no tag after any non-whitespace"
    /// would cost `(#infra)`, which is ordinary writing.
    static let openers: Set<Character> = ["(", "[", "{", "«", "\""]

    /// Tags in order of first appearance, without duplicates.
    public static func tags(in text: String) -> [String] {
        var found: [String] = []
        var seen: Set<String> = []
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "#", canOpenTag(after: previous) else {
                previous = character
                index = text.index(after: index)
                continue
            }

            let bodyStart = text.index(after: index)
            var bodyEnd = bodyStart
            while bodyEnd < text.endIndex, isBodyCharacter(text[bodyEnd]) {
                bodyEnd = text.index(after: bodyEnd)
            }

            if bodyEnd > bodyStart {
                let tag = String(text[bodyStart..<bodyEnd])
                if seen.insert(tag).inserted { found.append(tag) }
                previous = text[text.index(before: bodyEnd)]
                index = bodyEnd
            } else {
                previous = character
                index = bodyStart
            }
        }

        return found
    }

    static func canOpenTag(after previous: Character?) -> Bool {
        guard let previous else { return true }   // start of the text
        if previous.isWhitespace { return true }
        return openers.contains(previous)
    }

    static func isBodyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
