# Tasks 15–16: The capture panel

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

Design §10 steps 5–6, spec §6. This is the primary scenario — everything else in the app is
subordinate to it. Task 15 gets the end-to-end path working; Task 16 adds tagging while typing.

**Before starting Task 15, read the spike result recorded in §6 of the design doc** (Task 0). It
tells you whether the panel takes the primary non-activating path or the activation fallback. The
code below has both, behind one constant.

---

### Task 15: `CapturePanel` + `CaptureView` — end-to-end capture

**Files:**
- Create: `Sources/Dnotes/CapturePanel.swift`, `Sources/Dnotes/CaptureView.swift`
- Modify: `Sources/Dnotes/DnotesApp.swift` (`AppDelegate.toggleCapturePanel`)

**Interfaces:**
- Consumes: `NotesModel`, `SettingsStore`, `HotKeyManager`.
- Produces: `CapturePanel` with `toggle()`, `show()`, `hide()`. Task 16 adds completion inside
  `CaptureView`; Task 19 uses `SettingsStore.panelDraft`, already written here.

**Panel behaviour, from §6:**
- borderless, floating above everything including fullscreen windows;
- `⏎` saves and closes; `⇧⏎` saves and stays open for several thoughts in a row; `esc` closes and
  keeps what was typed as a draft;
- one line only — no multi-line entries by design;
- 560 pt wide.

- [ ] **Step 1: Write the panel**

`Sources/Dnotes/CapturePanel.swift`:

```swift
import AppKit
import SwiftUI
import DnotesCore

/// A borderless panel refuses key status unless this is overridden, which would
/// leave the field unable to receive a single keystroke.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CapturePanel {
    /// Set from the Task 0 spike result recorded in design §6. `false` is the primary
    /// non-activating path; `true` activates the app and restores the previous one on
    /// close, which looks the same from outside at the cost of an activation cycle.
    static let usesActivationFallback = false

    private let model: NotesModel
    private let settings: SettingsStore
    private let panel: KeyablePanel
    private var previousApp: NSRunningApplication?
    private var text: String = ""

    init(model: NotesModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 96),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false

        panel.contentView = NSHostingView(rootView: CaptureView(
            model: model,
            settings: settings,
            onSubmit: { [weak self] text, keepOpen in self?.submit(text, keepOpen: keepOpen) },
            onCancel: { [weak self] draft in self?.cancel(keepingDraft: draft) }
        ))
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        positionNearTopOfScreen()
        panel.makeKeyAndOrderFront(nil)
        if Self.usesActivationFallback { NSApp.activate(ignoringOtherApps: true) }
    }

    func hide() {
        panel.orderOut(nil)
        // Focus goes back where it came from — that is the whole point (§6).
        if Self.usesActivationFallback { previousApp?.activate() }
        previousApp = nil
    }

    private func submit(_ text: String, keepOpen: Bool) {
        settings.panelDraft = ""
        Task { await model.add(text) }
        if !keepOpen { hide() }
    }

    private func cancel(keepingDraft draft: String) {
        // esc keeps what was typed: unconfirmed text is still text (§8).
        settings.panelDraft = draft
        hide()
    }

    /// A capture panel belongs where a Spotlight window would be, not dead centre.
    private func positionNearTopOfScreen() {
        guard let screen = NSScreen.main else { panel.center(); return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - frame.height * 0.22
        ))
    }
}
```

- [ ] **Step 2: Write the view**

`Sources/Dnotes/CaptureView.swift`:

```swift
import SwiftUI
import DnotesCore

struct CaptureView: View {
    let model: NotesModel
    let settings: SettingsStore
    let onSubmit: (String, Bool) -> Void
    let onCancel: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $text, prompt: Text("What happened?"))
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit { submit(keepOpen: NSEvent.modifierFlags.contains(.shift)) }
                .onExitCommand { onCancel(text) }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 560)
        .onAppear {
            // A draft from a previous esc or crash is restored, not silently dropped.
            text = settings.panelDraft
            focused = true
        }
    }

    private func submit(keepOpen: Bool) {
        let captured = text
        guard !captured.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        text = ""
        onSubmit(captured, keepOpen)
    }
}
```

`⇧⏎` is read from `NSEvent.modifierFlags` at submit time because SwiftUI's `onSubmit` does not
carry the modifiers. It is the one place in the app that reaches for global modifier state.

- [ ] **Step 3: Wire the hotkey to the panel**

In `Sources/Dnotes/DnotesApp.swift`, replace the `AppDelegate` placeholder:

```swift
    private var capturePanel: CapturePanel?

    func toggleCapturePanel() {
        if capturePanel == nil {
            capturePanel = CapturePanel(model: composition.model,
                                        settings: composition.settings)
        }
        capturePanel?.toggle()
    }
```

and make the menu item call it:

```swift
            Button("Capture…") { delegate.toggleCapturePanel() }
```

- [ ] **Step 4: Run the §9.3 checks that matter here**

```bash
./scripts/bundle.sh && open dnotes.app
```

1. From Safari: `⌥Space` → panel appears → type → `⏎` → panel closes, and the caret is back in
   Safari. `2026-07.md` in the notes folder has gained the line under today's heading.
2. Same over **fullscreen Zoom** and a **fullscreen terminal** — the panel appears over the
   fullscreen window rather than switching Spaces, and typing reaches the field.
3. `⇧⏎` saves and leaves the panel open; three thoughts in a row land as three lines.
4. `esc` with text typed: panel closes; reopening shows the text again.
5. `⌥Space` twice in a row toggles the panel closed.

If check 1 or 2 fails on keyboard input, set `CapturePanel.usesActivationFallback = true`, rebuild,
and repeat — that is the §6 fallback, and the spike should already have told you which one applies.

- [ ] **Step 5: Run the suite and commit**

Run: `./scripts/test.sh`
Expected: PASS (unchanged — this task adds no testable logic).

```bash
git add Sources/Dnotes
git commit -m "feat: capture panel — hotkey to a line in the file

Non-activating floating panel over fullscreen spaces; enter saves and
closes, shift-enter keeps it open, esc keeps the text as a draft (§6, §8)."
```

---

### Task 16: Tag completion and `⌘1`–`⌘3`

**Files:**
- Create: `Sources/DnotesCore/TagCompletionModel.swift`
- Modify: `Sources/Dnotes/CaptureView.swift`
- Test: `Tests/DnotesCoreTests/TagCompletionTests.swift`

**Interfaces:**
- Consumes: `TagCount` (Task 12).
- Produces:
  ```swift
  @MainActor @Observable public final class TagCompletionModel {
      public init()
      public private(set) var isActive: Bool
      public private(set) var suggestions: [TagCount]
      public private(set) var selectedIndex: Int
      public var newTagName: String?          // non-nil when the typed tag does not exist yet
      public func update(text: String, available: [TagCount])
      public func moveSelection(by delta: Int)
      public func complete(in text: String) -> String
      public static func appending(_ tag: String, to text: String) -> String
  }
  ```

The completion logic lives in `DnotesCore` rather than in the view, because it is the only part of
this feature that can be tested without a window — and it is the part with the edge cases.

**Behaviour, from §6:** the three most frequent tags of the last 30 days sit under the field bound
to `⌘1`–`⌘3`, and appending one does not move the caret. Typing `#` opens completion over all
existing tags with their counts, plus a "create tag" item; `⇥` completes, `↑↓` selects. Tags are
optional — `⏎` with no tag saves the line as is.

- [ ] **Step 1: Write the failing tests**

`Tests/DnotesCoreTests/TagCompletionTests.swift`:

```swift
import Testing
@testable import DnotesCore

private let available = [
    TagCount(tag: "infra", count: 12),
    TagCount(tag: "oss", count: 7),
    TagCount(tag: "vsphere", count: 3),
]

@Test @MainActor func staysClosedUntilAHashIsTyped() {
    let completion = TagCompletionModel()
    completion.update(text: "just a thought", available: available)
    #expect(!completion.isActive)
}

@Test @MainActor func opensOnAHashAndOffersEverything() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #", available: available)

    #expect(completion.isActive)
    #expect(completion.suggestions.map(\.tag) == ["infra", "oss", "vsphere"])
    #expect(completion.newTagName == nil)   // nothing typed yet, nothing to create
}

@Test @MainActor func narrowsAsThePrefixGrows() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #vs", available: available)

    #expect(completion.suggestions.map(\.tag) == ["infra", "vsphere"])
}

@Test @MainActor func offersToCreateATagThatDoesNotExist() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #brandnew", available: available)

    #expect(completion.suggestions.isEmpty)
    #expect(completion.newTagName == "brandnew")
}

@Test @MainActor func closesWhenTheTagIsFinishedWithASpace() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #oss and more", available: available)
    #expect(!completion.isActive)
}

@Test @MainActor func onlyTheTagBeingTypedCounts() {
    let completion = TagCompletionModel()
    completion.update(text: "#oss then #vs", available: available)
    #expect(completion.suggestions.map(\.tag) == ["infra", "vsphere"])
}

@Test @MainActor func aUrlAnchorDoesNotOpenCompletion() {
    let completion = TagCompletionModel()
    completion.update(text: "see https://example.com/page#anchor", available: available)
    #expect(!completion.isActive)
}

@Test @MainActor func selectionMovesAndClamps() {
    let completion = TagCompletionModel()
    // Two matches plus the "create #vs" item, because `vs` is a prefix of existing
    // tags but is not itself one yet.
    completion.update(text: "#vs", available: available)
    #expect(completion.suggestions.count == 2)
    #expect(completion.newTagName == "vs")

    #expect(completion.selectedIndex == 0)
    completion.moveSelection(by: 1)
    #expect(completion.selectedIndex == 1)
    completion.moveSelection(by: 5)
    #expect(completion.selectedIndex == 2)   // clamped to the create item, not wrapped
    completion.moveSelection(by: -9)
    #expect(completion.selectedIndex == 0)
}

@Test @MainActor func completingReplacesThePartialTag() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #vs", available: available)

    #expect(completion.complete(in: "ship it #vs") == "ship it #infra ")
}

@Test @MainActor func completingANewTagKeepsWhatWasTyped() {
    let completion = TagCompletionModel()
    completion.update(text: "ship it #brandnew", available: available)

    #expect(completion.complete(in: "ship it #brandnew") == "ship it #brandnew ")
}

@Test @MainActor func appendingATagAddsItAtTheEnd() {
    #expect(TagCompletionModel.appending("oss", to: "ship the parser")
            == "ship the parser #oss")
    #expect(TagCompletionModel.appending("oss", to: "ship the parser ")
            == "ship the parser #oss")
    #expect(TagCompletionModel.appending("oss", to: "") == "#oss")
}

@Test @MainActor func appendingATagAlreadyPresentChangesNothing() {
    #expect(TagCompletionModel.appending("oss", to: "already #oss here")
            == "already #oss here")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter TagCompletion`
Expected: FAIL, `cannot find 'TagCompletionModel' in scope`.

- [ ] **Step 3: Implement**

`Sources/DnotesCore/TagCompletionModel.swift`:

```swift
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

    private var partial: String = ""

    public init() {}

    /// Recomputed on every keystroke over the tag currently being typed — the one
    /// whose `#` is the last tag opener in the text and which has not been closed by
    /// a space yet.
    public func update(text: String, available: [TagCount]) {
        guard let typed = Self.tagBeingTyped(in: text) else {
            isActive = false
            suggestions = []
            newTagName = nil
            partial = ""
            return
        }

        partial = typed
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
        let head = text[text.startIndex...hash]
        return String(head) + chosen + " "
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
    static func lastTagOpenerIndex(in text: String) -> String.Index? {
        var opener: String.Index?
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "#", canOpen(after: previous) {
                opener = index
            } else if character.isWhitespace {
                opener = nil
            } else if let current = opener, index > current, !isBody(character) {
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

    private static func canOpen(after previous: Character?) -> Bool {
        guard let previous else { return true }
        if previous.isWhitespace { return true }
        return ["(", "[", "{", "«", "\""].contains(previous)
    }

    private static func isBody(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./scripts/test.sh --filter TagCompletion`
Expected: PASS.

- [ ] **Step 5: Put it in the capture view**

Extend `Sources/Dnotes/CaptureView.swift`:

```swift
    @State private var completion = TagCompletionModel()

    // inside the VStack, under the TextField:
            if completion.isActive {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(completion.suggestions.enumerated()), id: \.element.tag) { index, tag in
                        row(title: "#\(tag.tag)", detail: "\(tag.count)",
                            selected: index == completion.selectedIndex)
                    }
                    if let name = completion.newTagName {
                        row(title: "#\(name)", detail: "new tag",
                            selected: completion.selectedIndex == completion.suggestions.count)
                    }
                }
            } else if !model.topTags.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(model.topTags.enumerated()), id: \.element) { index, tag in
                        Text("⌘\(index + 1)  #\(tag)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
```

with the helpers and the key handling:

```swift
    @ViewBuilder
    private func row(title: String, detail: String, selected: Bool) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }
```

Attach to the `TextField`:

```swift
                .onChange(of: text) { completion.update(text: text, available: model.tagCounts) }
                .onKeyPress(.tab) {
                    guard completion.isActive else { return .ignored }
                    text = completion.complete(in: text)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard completion.isActive else { return .ignored }
                    completion.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard completion.isActive else { return .ignored }
                    completion.moveSelection(by: 1)
                    return .handled
                }
```

and the three frequent-tag bindings, as invisible buttons in the same `VStack`:

```swift
            ForEach(Array(model.topTags.enumerated()), id: \.element) { index, tag in
                Button("") { text = TagCompletionModel.appending(tag, to: text) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)
            }
```

- [ ] **Step 6: Check it by hand**

```bash
./scripts/bundle.sh && open dnotes.app
```

1. `⌥Space`, type `ship it #` — the list appears with counts.
2. Type `vs` — the list narrows; `↑↓` moves the highlight; `⇥` completes to `#infra `.
3. Type `#somethingnew` — the "new tag" row appears and `⇥` accepts what was typed.
4. With the field empty of tags, `⌘1` appends the most frequent tag at the end and the caret does
   not move.
5. `⏎` with no tag at all still saves the line.

- [ ] **Step 7: Run the suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources Tests
git commit -m "feat: tag completion in the capture panel

The scanning rules match TagScanner's, so a URL anchor does not open the
completion list; ⌘1–⌘3 append a frequent tag without moving the caret (§6)."
```
