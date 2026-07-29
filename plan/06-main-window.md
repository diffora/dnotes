# Tasks 17–18: The main window

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

Design §10 steps 7–8, spec §7. One reverse-chronological list of everything. No folder sidebar, no
split between notes and tasks — a note becomes a task simply because it can be closed.

The filtering and ordering rules were decided and tested in Task 12; these two tasks render what
`NotesModel.visibleEntries` already returns and must not re-implement any of it.

---

### Task 17: List, day separators, keyboard navigation, completing an entry

**Files:**
- Create: `Sources/Dnotes/MainWindowView.swift`, `Sources/Dnotes/EntryRowView.swift`
- Modify: `Sources/Dnotes/DnotesApp.swift` (the `Window` scene and `AppDelegate.showMainWindow`)

**Interfaces:**
- Consumes: `NotesModel`, `HotKeyManager`.
- Produces: the `main` window scene. Task 18 adds the toolbar's search field and the tag chips;
  Task 19 adds the folder banner and the unsaved badge.

**Activation is wanted here, unlike the capture panel** (§7). The app is `LSUIElement`, so it never
becomes active on its own: showing the window is always accompanied by
`NSApp.activate(ignoringOtherApps: true)`, or the window appears with a keyboard that does nothing.

**Keyboard (§7):** `↑↓` navigates, `␣` completes/reopens, `⏎` edits the line in place, `⌘⌫` deletes,
`⌘F` focuses search, `esc` clears search and filter.

- [ ] **Step 1: Write the row**

`Sources/Dnotes/EntryRowView.swift`:

```swift
import SwiftUI
import DnotesCore

struct EntryRowView: View {
    let entry: NoteEntry
    let isSelected: Bool
    let isEditing: Bool
    let onCommitEdit: (String) -> Void
    let onCancelEdit: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isDone ? .secondary : .tertiary)
                .font(.system(size: 13))

            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { onCommitEdit(draft) }
                    .onExitCommand(perform: onCancelEdit)
                    .onAppear { draft = entry.text; focused = true }
            } else {
                Text(entry.text)
                    .strikethrough(entry.isDone, color: .secondary)
                    .foregroundStyle(entry.isDone ? .secondary : .primary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Write the window**

`Sources/Dnotes/MainWindowView.swift`:

```swift
import AppKit
import SwiftUI
import DnotesCore

struct MainWindowView: View {
    let model: NotesModel
    let onChooseFolder: () -> Void

    private enum Focus: Hashable { case search, list }

    @State private var selection: EntryID?
    @State private var editing: EntryID?
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(spacing: 0) {
            FolderBannerView(
                model: model,
                onChooseFolder: onChooseFolder,
                onRetry: { Task { await model.drainPending() } }
            )
            header
            Divider()
            TagChipsView(model: model)
            Divider()
            list
            shortcuts
        }
        .frame(minWidth: 520, minHeight: 380)
        .background(VisualEffectBackground())
        .task {
            await model.load()
            focus = .list
        }
    }

    // MARK: - pieces

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: Binding(get: { model.searchText },
                                              set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onSubmit { focus = .list }
                .onExitCommand { clearFilters() }

            Toggle(isOn: Binding(get: { model.showsCompleted },
                                 set: { model.showsCompleted = $0 })) {
                Image(systemName: "checkmark.circle")
            }
            .toggleStyle(.button)
            .help("Show entries completed on earlier days")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var list: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                    ForEach(days, id: \.self) { day in
                        Section {
                            ForEach(entries(on: day)) { entry in
                                EntryRowView(
                                    entry: entry,
                                    isSelected: selection == entry.id,
                                    isEditing: editing == entry.id,
                                    onCommitEdit: { text in
                                        editing = nil
                                        focus = .list
                                        Task { await model.edit(entry, to: text) }
                                    },
                                    onCancelEdit: {
                                        editing = nil
                                        focus = .list
                                    }
                                )
                                .id(entry.id)
                                .onTapGesture {
                                    selection = entry.id
                                    focus = .list
                                }
                            }
                        } header: {
                            Text(dayTitle(day))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollContentBackground(.hidden)
            .focusable()
            .focused($focus, equals: .list)
            .focusEffectDisabled()
            .onKeyPress { press in handle(press) }
            .onExitCommand { clearFilters() }
            .onChange(of: selection) { _, new in
                if let new { withAnimation { scroller.scrollTo(new, anchor: .center) } }
            }
        }
    }

    /// Menu-level shortcuts have no menu in an LSUIElement app, so they live here as
    /// zero-sized buttons.
    private var shortcuts: some View {
        ZStack {
            Button("") { focus = .search }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - grouping

    private var days: [CalendarDay] {
        var seen: Set<CalendarDay> = []
        return model.visibleEntries.compactMap { seen.insert($0.day).inserted ? $0.day : nil }
    }

    private func entries(on day: CalendarDay) -> [NoteEntry] {
        model.visibleEntries.filter { $0.day == day }
    }

    private func dayTitle(_ day: CalendarDay) -> String {
        day == model.today ? "Today — \(day)" : day.description
    }

    // MARK: - keyboard

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard editing == nil else { return .ignored }

        switch press.key {
        case .upArrow: return move(-1)
        case .downArrow: return move(1)
        case .space: return toggleSelected()
        case .return: return startEditingSelected()
        default: return .ignored
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let all = model.visibleEntries
        guard !all.isEmpty else { return .handled }
        let current = all.firstIndex { $0.id == selection } ?? -1
        selection = all[min(max(current + delta, 0), all.count - 1)].id
        return .handled
    }

    private func toggleSelected() -> KeyPress.Result {
        guard let entry = selectedEntry else { return .ignored }
        Task { await model.toggle(entry) }
        return .handled
    }

    private func startEditingSelected() -> KeyPress.Result {
        guard let entry = selectedEntry else { return .ignored }
        editing = entry.id
        return .handled
    }

    private func deleteSelected() {
        guard editing == nil, let entry = selectedEntry else { return }
        Task { await model.delete(entry) }
    }

    private func clearFilters() {
        // esc clears search and filter, in that order of usefulness (§7).
        model.searchText = ""
        model.selectedTag = nil
        focus = .list
    }

    private var selectedEntry: NoteEntry? {
        model.visibleEntries.first { $0.id == selection }
    }
}

/// `NSVisualEffectView` as the background (§7); SwiftUI has no direct equivalent
/// that also picks up the window's active state.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

**Implementation note — the window is AppKit, not a SwiftUI `Window` scene.** An `LSUIElement`
app has to open its window from an `AppDelegate` callback (the hotkey), and threading
`openWindow` out of a scene into the delegate needs a hidden helper view that exists only to
capture the environment action. An `NSWindow` with an `NSHostingView`, owned by the delegate, is
one object with no ceremony — and the app already owns an `NSPanel`, so it is the same pattern
twice rather than two patterns.

For the same reason the list is a `ScrollView` + `LazyVStack` rather than a `List`: `List` brings
its own selection and key handling, which then has to be fought to get §7's exact bindings.
`⌘F` and `⌘⌫` are zero-sized `Button`s with `keyboardShortcut`, because an `LSUIElement` app has no
menu bar to hang menu commands on.

- [ ] **Step 3: Open the window from the hotkey and the menu**

In `AppDelegate`:

```swift
    private var mainWindow: NSWindow?

    func showMainWindow() {
        // LSUIElement means the app never becomes active on its own; without this the
        // window would appear with a keyboard that does nothing (§7).
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Notes"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: MainWindowView(
            model: composition.model,
            onChooseFolder: { [weak self] in self?.chooseFolder() }
        ))
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }
```

and the menu item calls the same method:

```swift
            Button("Notes…") { delegate.showMainWindow() }
```

- [ ] **Step 4: Check it by hand**

```bash
./scripts/bundle.sh && open dnotes.app
```

1. `⌥⇧Space` from another app: the window appears **and is active** — `↑↓` moves the selection
   immediately, with no click first.
2. Days are separators in one flow, newest first; today's section says "Today".
3. `␣` on a selected line strikes it through and the file gains `- [x] `; `␣` again reopens it and
   the file goes back to `- `.
4. `⏎` edits in place; `⏎` again commits, `esc` cancels and leaves the text as it was.
5. `⌘⌫` deletes the selected line and only that line.
6. An entry completed today stays visible, struck through. Restart with the system date rolled
   forward and it is gone from the list.

- [ ] **Step 5: Run the suite and commit**

Run: `./scripts/test.sh`
Expected: PASS (unchanged — the list renders what Task 12 already tested).

```bash
git add Sources/Dnotes
git commit -m "feat: main window — one reverse-chronological list with keyboard control

Showing the window always activates the app: LSUIElement means it never
becomes active on its own, and a window with a dead keyboard is worse than
no window (§7)."
```

---

### Task 18: Search and tag chips

**Files:**
- Create: `Sources/Dnotes/TagChipsView.swift`
- Modify: `Sources/Dnotes/MainWindowView.swift`

**Interfaces:**
- Consumes: `NotesModel.searchText`, `selectedTag`, `showsCompleted`, `tagCounts`.
- Produces: the toolbar and the chip row. No new model logic — Task 12 owns all of it.

**§7:** search filters as you type; chips show entry counts; a click filters, a second click clears;
search and tag filter compose; `⌘F` focuses search; `esc` clears both.

- [ ] **Step 1: Write the chips**

`Sources/Dnotes/TagChipsView.swift`:

```swift
import SwiftUI
import DnotesCore

struct TagChipsView: View {
    let model: NotesModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.tagCounts, id: \.tag) { tag in
                    Button {
                        // A second click on the same chip clears the filter (§7).
                        model.selectedTag = model.selectedTag == tag.tag ? nil : tag.tag
                    } label: {
                        HStack(spacing: 4) {
                            Text("#\(tag.tag)")
                            Text("\(tag.count)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            model.selectedTag == tag.tag
                                ? AnyShapeStyle(Color.accentColor.opacity(0.30))
                                : AnyShapeStyle(.quaternary),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
```

- [ ] **Step 2: Add the search header and wire the shortcuts**

The search field is a plain `TextField` in a header row rather than `.searchable`: that modifier
wants a `NavigationStack` or a toolbar, and this window is an `NSHostingView` with neither. A header
row also makes `⌘F` explicit instead of inherited, which is one less thing to verify by hope.

In `MainWindowView`:

```swift
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: Binding(get: { model.searchText },
                                              set: { model.searchText = $0 }))
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onSubmit { focus = .list }
                .onExitCommand { clearFilters() }

            Toggle(isOn: Binding(get: { model.showsCompleted },
                                 set: { model.showsCompleted = $0 })) {
                Image(systemName: "checkmark.circle")
            }
            .toggleStyle(.button)
            .help("Show entries completed on earlier days")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
```

Focus is an explicit `@FocusState` with two cases, `.search` and `.list`, which is what keeps the
list's `onKeyPress` from eating characters meant for the search field.

- [ ] **Step 3: Check it by hand**

1. Type in the search field: the list narrows as you type; `Émile` matches `émile`, `cafe`
   matches `CAFÉ`.
2. A completed entry from an earlier day does not show in the list but *is* found by search.
3. Click a chip: the list filters and the chip highlights. Click it again: the filter clears.
4. With a chip selected, type in search — both apply. The other chips still show their counts
   rather than dropping to zero.
5. `⌘F` focuses the search field; `esc` clears both search and chip.
6. The "Completed" toggle brings back earlier completed entries and putting it back hides them.

- [ ] **Step 4: Run the suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources/Dnotes
git commit -m "feat: search field and tag chips in the main window

Chip counts are computed before the tag filter is applied, so selecting one
does not zero every other chip and strand the user (§7)."
```
