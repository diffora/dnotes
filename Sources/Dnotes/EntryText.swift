import AppKit
import SwiftUI
import DnotesCore

/// The entry's text, drawn by AppKit rather than by SwiftUI's `Text`.
///
/// SwiftUI renders a link inside `Text` but does not change the cursor over it on
/// macOS, and it offers no way to ask "is this point on a link?" — the row would have
/// to guess. AppKit knows, because it laid the glyphs out.
///
/// A selectable `NSTextField` would give links and the cursor for free, but text
/// selection then swallows the clicks that select the row and start an edit. So this
/// takes every click itself: on a link it opens it, and anywhere else it hands the
/// click count back to the row.
///
/// A link is only *live* while ⌘ is held: then it underlines, takes the pointing-hand
/// cursor, and opens on click. The colour is always there, so a line still reads as
/// containing a reference — but a stray click on a row can never launch a browser,
/// which is the behaviour editors settled on for the same reason.
struct EntryText: NSViewRepresentable {
    let text: String
    let issueURLTemplate: String
    let isDone: Bool
    /// Asked per tag rather than handed a palette, so the row cannot hold a stale copy
    /// of a colour the user has just overridden.
    let tagColor: (String) -> NSColor
    let onClick: (Int) -> Void

    func makeNSView(context: Context) -> LinkLabel {
        let label = LinkLabel(labelWithString: "")
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.allowsEditingTextAttributes = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: LinkLabel, context: Context) {
        label.onClick = onClick
        label.tagColor = tagColor
        label.apply(text: text, issueURLTemplate: issueURLTemplate, isDone: isDone)
    }
}

final class LinkLabel: NSTextField {
    private var links: [(range: NSRange, url: URL)] = []
    private var tags: [(range: NSRange, tag: String)] = []
    private var content = ""
    private var template = ""
    private var done = false

    var tagColor: ((String) -> NSColor)?

    /// Polled rather than driven by events: ⌘ going down produces no event this view can
    /// rely on — `flagsChanged` only arrives while the app is active, and this window
    /// gets hovered from the background — and no mouse movement either.
    private var hoverPoll: Timer?
    private var lastLiveLink: Int?

    var onClick: ((Int) -> Void)?

    /// Read from the hardware, never received as an event, for the reason above.
    private var isCommandDown: Bool { NSEvent.modifierFlags.contains(.command) }

    // MARK: - content

    func apply(text: String, issueURLTemplate: String, isDone: Bool) {
        content = text
        template = issueURLTemplate
        done = isDone
        restyle()
    }

    private func restyle() {
        let attributed = NSMutableAttributedString(string: content, attributes: [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: done ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .strikethroughStyle: done ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughColor: NSColor.secondaryLabelColor,
        ])

        links = EntryLinks.spans(in: content, issueURLTemplate: template)
            .map { (NSRange($0.range, in: content), $0.url) }

        // Tags first, links second, so where the two disagree the link wins — it is the
        // one a click acts on, and a link that does not look like one is a trap. They
        // overlap only in odd cases (`#tag.com` is a tag to the scanner and a URL to the
        // detector), but two colours fighting over the same glyphs is worth ruling out.
        tags = TagScanner.spans(in: content)
            .map { (NSRange($0.range, in: content), $0.tag) }
            .filter { candidate in !links.contains { NSIntersectionRange($0.range, candidate.range).length > 0 } }

        // Semibold at the body size: weight, not just hue, separates a tag from a link,
        // which is what keeps the two apart for a reader who cannot rely on colour.
        let semibold = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)

        for tag in tags {
            // A completed entry goes quiet all over: a bright tag on a struck-through
            // line would advertise the one thing there is nothing left to do about.
            attributed.addAttributes([
                .font: semibold,
                .foregroundColor: done
                    ? NSColor.secondaryLabelColor
                    : (tagColor?(tag.tag) ?? NSColor.labelColor),
            ], range: tag.range)
        }

        for (index, link) in links.enumerated() {
            // Colour always, underline only while the link is live. In a list of short
            // lines a permanent underline is noise; the underline appearing under ⌘ is
            // also the feedback that says "this click will follow the link".
            var attributes: [NSAttributedString.Key: Any] = [
                .link: link.url,
                .foregroundColor: done ? NSColor.secondaryLabelColor : NSColor.linkColor,
            ]
            if index == liveLink {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributed.addAttributes(attributes, range: link.range)
        }

        attributedStringValue = attributed
        window?.invalidateCursorRects(for: self)

        // Only when the pointer is over this row: `restyle()` runs for every visible row
        // on every update, and setting the cursor unconditionally would let any one of
        // them stamp on the cursor belonging to whatever is under the mouse.
        if containsPointer {
            (liveLink != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
        }

        startPolling()   // links may have only just appeared
    }

    // MARK: - what is live

    /// The link under the pointer, and only while ⌘ is down. Asked for rather than
    /// remembered: caching it from a `mouseMoved` cannot answer the case this feature is
    /// for — ⌘ pressed while the pointer sits still.
    private var liveLink: Int? {
        guard isCommandDown, !links.isEmpty, let point = pointerLocation else { return nil }
        return linkIndex(at: point)
    }

    private var containsPointer: Bool { pointerLocation != nil }

    /// The pointer in this view's coordinates, or nil when it is elsewhere.
    private var pointerLocation: NSPoint? {
        guard let window else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.contains(point) ? point : nil
    }

    // MARK: - the cursor

    override func resetCursorRects() {
        super.resetCursorRects()
        // Only while ⌘ is down: a hand cursor over a link that a click would not follow
        // is a promise the view does not keep.
        guard isCommandDown else { return }
        for rect in linkRects() {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    /// Cursor rects are only re-evaluated when the pointer moves, so pressing ⌘ over a
    /// stationary pointer would leave an arrow. This sets it directly.
    override func cursorUpdate(with event: NSEvent) {
        if liveLink != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - tracking and polling

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Without this the window generates no mouse-moved events at all, and a tracking
        // area asking for them gets nothing.
        window?.acceptsMouseMovedEvents = true
        // Rows are recycled by the lazy stack; a poll left running on a view that has
        // left the window would tick forever. `deinit` cannot do this — it is not allowed
        // to touch a non-Sendable Timer.
        if window == nil { stopPolling() } else { startPolling() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard !links.isEmpty else { return }
        // `.activeAlways`, not `.activeInKeyWindow`: this window gets hovered while the
        // app is in the background, which is exactly when the feature is wanted.
        // `.inVisibleRect` keeps the area in step with the row's bounds by itself, which
        // matters inside a scrolling list.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate,
                      .inVisibleRect, .activeAlways],
            owner: self
        ))
    }

    /// Moving with ⌘ held has to move the underline from one link to the next.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        refreshIfLiveLinkChanged()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        refreshIfLiveLinkChanged()
    }

    /// Runs while the row is on screen and holds a link, not merely while the pointer is
    /// inside it: `mouseEntered` turned out never to arrive here. One tenth-second timer
    /// per *visible* row with a link — the lazy stack only realises those — and it does
    /// no work unless the answer actually changed.
    private func startPolling() {
        guard hoverPoll == nil, !links.isEmpty, window != nil else { return }
        hoverPoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfLiveLinkChanged() }
        }
    }

    private func stopPolling() {
        hoverPoll?.invalidate()
        hoverPoll = nil
    }

    private func refreshIfLiveLinkChanged() {
        let live = liveLink
        guard live != lastLiveLink else { return }
        lastLiveLink = live
        restyle()
    }

    // MARK: - clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Following a link takes ⌘, so an ordinary click on a row never opens a browser.
        if isCommandDown, let index = linkIndex(at: point) {
            NSWorkspace.shared.open(links[index].url)
            return
        }
        onClick?(event.clickCount)
    }

    // MARK: - layout, borrowed to answer geometry questions

    /// All three parts travel together, and that is the whole point.
    ///
    /// `NSTextStorage` owns its layout managers; the manager's reference back to the
    /// storage does not keep it alive. Left as a local, the storage died on return and
    /// the manager was found with no text — zero glyphs, every link rect empty, which is
    /// what actually broke ⌘-hover for three rounds of wrong guesses. Returning it in a
    /// tuple was not enough either: the caller bound it to `_` and ARC released it on the
    /// spot. A struct the caller holds makes the lifetime impossible to drop by accident.
    private struct TextLayout {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let container: NSTextContainer
    }

    /// A throwaway text system over the same string and width. `NSTextField` does not
    /// expose the layout it draws with, and re-deriving it is cheaper than replacing the
    /// field with an `NSTextView` that would bring its own selection behaviour.
    private func makeLayout() -> TextLayout? {
        guard !links.isEmpty, bounds.width > 0 else { return nil }

        // Order matters: attaching the container to a layout manager that has no text
        // storage yet leaves nothing to lay out.
        let storage = NSTextStorage(attributedString: attributedStringValue)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)

        let container = NSTextContainer(size: NSSize(width: bounds.width,
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)

        return TextLayout(storage: storage, manager: manager, container: container)
    }

    private func linkRects() -> [NSRect] {
        guard let layout = makeLayout() else { return [] }
        return links.map { link in
            let glyphs = layout.manager.glyphRange(forCharacterRange: link.range,
                                                   actualCharacterRange: nil)
            return flipped(layout.manager.boundingRect(forGlyphRange: glyphs,
                                                       in: layout.container))
        }
    }

    private func linkIndex(at point: NSPoint) -> Int? {
        guard let layout = makeLayout() else { return nil }
        let inText = NSPoint(x: point.x, y: bounds.height - point.y)
        let character = layout.manager.characterIndex(
            for: inText,
            in: layout.container,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        return links.firstIndex { NSLocationInRange(character, $0.range) }
    }

    /// The layout manager measures from the top; an unflipped view draws from the bottom.
    private func flipped(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: bounds.height - rect.maxY,
               width: rect.width, height: rect.height)
    }
}
