import Foundation

/// Turns the parts of an entry that are already references into links: URLs, and issue
/// keys like `ABC-1234`.
///
/// This adds nothing to the stored line — §2.3 keeps markdown the source of truth and
/// §4.1 keeps tags as plain text — it only recognises what the text already says. The
/// entry format stays one line either way.
public enum EntryLinks {
    public struct Span: Equatable, Sendable {
        public let range: Range<String.Index>
        public let url: URL
    }

    /// Issue keys need a template because only the reader knows which tracker they
    /// live in. `{key}` is substituted; an empty template means issue keys are left
    /// as plain text rather than pointed at a guess.
    public static let issueKeyPlaceholder = "{key}"

    public static func spans(in text: String, issueURLTemplate: String = "") -> [Span] {
        var spans = urlSpans(in: text)
        spans += issueSpans(in: text, template: issueURLTemplate,
                            avoiding: spans.map(\.range))
        return spans.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - URLs

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func urlSpans(in text: String) -> [Span] {
        guard let detector else { return [] }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: full).compactMap { match in
            guard let url = match.url, let range = Range(match.range, in: text) else { return nil }
            return Span(range: range, url: url)
        }
    }

    // MARK: - issue keys

    /// `ABC-123`: two or more capitals, a hyphen, digits. Deliberately narrow — a
    /// looser rule would light up ordinary hyphenated words and dates.
    private static let issueKey = try? NSRegularExpression(pattern: "\\b[A-Z][A-Z0-9]+-[0-9]+\\b")

    private static func issueSpans(in text: String,
                                   template: String,
                                   avoiding taken: [Range<String.Index>]) -> [Span] {
        guard !template.isEmpty, template.contains(issueKeyPlaceholder),
              let issueKey else { return [] }

        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        return issueKey.matches(in: text, range: full).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            // A key inside a URL is already part of that link; two overlapping links
            // would fight over the same characters.
            guard !taken.contains(where: { $0.overlaps(range) }) else { return nil }

            let key = String(text[range])
            let replaced = template.replacingOccurrences(of: issueKeyPlaceholder, with: key)
            guard let url = URL(string: replaced) else { return nil }
            return Span(range: range, url: url)
        }
    }
}
