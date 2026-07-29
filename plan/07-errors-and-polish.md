# Tasks 19–20: Error handling and polish

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

Design §10 steps 9–10, spec §8 and §9.3. The general rule the whole app answers to: **it has no
right to silently lose text in any scenario.** Tasks 11 and 12 already built the machinery — the
pending queue, the panel draft, the cancelled-on-ambiguity write path. This task makes it visible.

---

### Task 19: Folder banner, panel draft, pending queue, unsaved badge

**Files:**
- Create: `Sources/Dnotes/FolderBannerView.swift`
- Modify: `Sources/Dnotes/MainWindowView.swift`, `Sources/Dnotes/CaptureView.swift`,
  `Sources/Dnotes/Composition.swift`

**Interfaces:**
- Consumes: `NotesModel.storeAvailable`, `lastError`, `pendingCount`, `drainPending()`;
  `SettingsStore.panelDraft`.
- Produces: no new API — this task is entirely presentation over what Tasks 11–12 already expose.

**The §8 table, and where each row is handled:**

| Failure | Handled by | Visible as |
| --- | --- | --- |
| Folder not chosen, moved, not downloaded | `NotesModel.storeAvailable` | banner with a "choose folder" button; confirmed entries queue up |
| File changed between read and write | Task 9's mtime guard | nothing — it just works |
| Line disappeared or matches ambiguous | Task 9 cancels | `lastError` shown quietly, file untouched |
| Unfamiliar markup in the file | §4.3, structural | nothing — those lines are preserved, not entries |
| Write error (no space, no permission) | Task 12 queues it | "unsaved" badge with a retry button |
| Crash with typed but unconfirmed text | `SettingsStore.panelDraft` (Task 13) | the draft is back on the next open |
| Crash with a non-empty queue | `PendingQueue` persistence (Task 11) | drains on the first successful access |

- [ ] **Step 1: Write the banner**

`Sources/Dnotes/FolderBannerView.swift`:

```swift
import SwiftUI
import DnotesCore

/// Shown when the store cannot be reached. The app stays usable — capture still
/// works and queues — so this is a banner, not a modal (§8).
struct FolderBannerView: View {
    let model: NotesModel
    let onChooseFolder: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if !model.storeAvailable {
            banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                message: model.lastError ?? "The notes folder is not available.",
                actionTitle: "Choose Folder…",
                action: onChooseFolder
            )
        } else if model.pendingCount > 0 {
            banner(
                icon: "clock.arrow.circlepath",
                tint: .yellow,
                message: "\(model.pendingCount) unsaved \(model.pendingCount == 1 ? "entry" : "entries")",
                actionTitle: "Retry",
                action: onRetry
            )
        } else if let error = model.lastError {
            banner(icon: "info.circle", tint: .secondary, message: error,
                   actionTitle: nil, action: {})
        }
    }

    @ViewBuilder
    private func banner(icon: String, tint: Color, message: String,
                        actionTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(message).font(.callout).lineLimit(2)
            Spacer(minLength: 8)
            if let actionTitle {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.quaternary)
    }
}
```

- [ ] **Step 2: Put the banner at the top of the window**

In `MainWindowView`, above `TagChipsView`:

```swift
            FolderBannerView(
                model: model,
                onChooseFolder: onChooseFolder,
                onRetry: { Task { await model.drainPending() } }
            )
```

with `onChooseFolder` passed in from `DnotesApp` so the picker keeps living in one place:

```swift
        Window("Notes", id: "main") {
            MainWindowView(model: delegate.composition.model,
                           onChooseFolder: { delegate.chooseFolder() })
        }
```

and in `AppDelegate`:

```swift
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = composition.settings.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await composition.changeFolder(to: url) }
    }
```

- [ ] **Step 3: Show unsaved state in the capture panel too**

Capture is the scenario that matters; the panel must not look like it swallowed a line. In
`CaptureView`, under the field:

```swift
            if !model.storeAvailable {
                Label("Folder unavailable — entries are saved and will be written when it is back",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: Drain the queue whenever the store comes back**

In `Composition`, retry on every external change and on folder switch:

```swift
    func start() async {
        await model.load()
        repository.onExternalChange = { [weak self] in
            guard let self else { return }
            Task { await self.model.drainPending() }
        }
        repository.startObserving()
    }
```

Note `NotesModel` also installs an `onExternalChange` handler in its initializer, so this one must
call the model's refresh path rather than replacing it — set it *after* the model is built and have
it call `model.load()`:

```swift
        repository.onExternalChange = { [weak self] in
            Task { await self?.model.load() }
        }
```

`NotesModel.load()` already refreshes and then drains, so one handler covers both.

- [ ] **Step 5: Check every §8 row by hand**

Each of these is a real scenario, so run them against a **scratch folder**, not the real notes.

1. Point the folder at a path that does not exist → banner appears, the list is empty, the app does
   not crash.
2. With the folder gone, capture three lines with `⌥Space` `⏎`. The banner shows "3 unsaved
   entries". Quit and relaunch: it still shows 3.
3. Recreate the folder → the queue drains on its own, and the three lines land **under the day they
   were captured on**, in the order they were typed.
4. `chmod 500` the folder, capture a line → it queues with the same badge; `chmod 755` and hit
   Retry → it lands.
5. Type into the panel, press `esc`, quit the app, relaunch, `⌥Space` → the text is back.
6. Open a month file in an editor, delete a line the app currently shows, then press `␣` on that
   line in the app → a quiet message, and the file is **not** rewritten.
7. Put `> a quote` and a markdown table into a month file → they do not appear as entries, and
   editing a neighbouring line leaves them byte for byte intact.

- [ ] **Step 6: Run the suite and commit**

Run: `./scripts/test.sh`
Expected: PASS.

```bash
git add Sources/Dnotes
git commit -m "feat: error surfaces — folder banner, unsaved badge, draft restore

Every row of design §8 now has somewhere to show up; the machinery behind
them was already tested against the in-memory backend."
```

---

### Task 20: Visual polish and the §9.3 manual checklist

**Files:**
- Modify: `Sources/Dnotes/CapturePanel.swift`, `Sources/Dnotes/CaptureView.swift`,
  `Sources/Dnotes/MainWindowView.swift`, `Sources/Dnotes/EntryRowView.swift`
- Create: `docs/manual-checklist.md`

**§7 and §2:** system fonts, `NSVisualEffectView` background, automatic light and dark themes, no
web shell. Polish means using what the system gives rather than adding a design.

- [ ] **Step 1: Materials and appearance**

- Capture panel: `.regularMaterial` behind a 12 pt rounded rectangle (already in Task 15); add a
  subtle shadow and a fade-in:

```swift
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
```

- Main window: `underWindowBackground` (already in Task 17); make the list background clear so the
  material shows through:

```swift
            .scrollContentBackground(.hidden)
```

- Never hard-code a colour that is not a semantic one. `Color.primary`, `.secondary`, `.tertiary`,
  `Color.accentColor` and the material styles already track light and dark; a literal grey does not.

- [ ] **Step 2: Type**

- Capture field: `.system(size: 20)` — it is the one thing on screen.
- List rows: default body size; day headers `.subheadline.weight(.medium)` in `.secondary`.
- Tag chips and counts: `.caption`.

Nothing custom, nothing bundled: the system font is the native look §2 asks for.

- [ ] **Step 3: Write the checklist down**

`docs/manual-checklist.md` — the §9.3 list, so it can be re-run after any change rather than
reconstructed from the spec each time:

```markdown
# Manual checklist (design §9.3)

Run before calling a change done. A scratch notes folder, not the real one.

## Capture
- [ ] Hotkey fires with fullscreen Zoom active; the panel appears over it.
- [ ] Hotkey fires in a fullscreen terminal; typed characters reach the field.
- [ ] After `⏎`, focus is back in the app the hotkey was pressed from.
- [ ] `⇧⏎` saves and keeps the panel open.
- [ ] `esc` with typed text closes the panel; the text is there on the next open.
- [ ] A taken hotkey shows a conflict message in Settings rather than dying silently.

## Main window
- [ ] `⌥⇧Space` from another app: the window is active and its keyboard works at once.
- [ ] `↑↓` `␣` `⏎` `⌘⌫` `⌘F` `esc` all behave as §7 describes.
- [ ] Days are separators in one reverse-chronological flow.
- [ ] An entry completed today stays visible, struck through.

## Appearance
- [ ] Light and dark themes both read correctly.
- [ ] Switching the system theme with the window open updates it live.

## Storage
- [ ] An external edit to a month file shows up in the app within a second.
- [ ] The app's own writes do not make the list flicker.
- [ ] `git status` in the notes folder shows only the lines that were actually changed.
```

- [ ] **Step 4: Run the whole checklist**

Work through `docs/manual-checklist.md` end to end and fix what fails. This is the task's real
deliverable — the polish edits above are minutes of work, and the checklist is what says the app
is done.

- [ ] **Step 5: Final verification**

```bash
./scripts/test.sh          # every test green
./scripts/bundle.sh        # builds cleanly
git status --short         # nothing unintended left behind
```

- [ ] **Step 6: Commit**

```bash
git add Sources docs
git commit -m "feat: visual polish and the manual checklist

System fonts and materials only, semantic colours throughout, so light and
dark come free. §9.3 written down as a checklist to re-run."
```

---

## After the plan

What §12 deliberately deferred, in the order the spec ranks it: auto-links for `ABC-1234` and
URLs; moving an open entry to today with one key; a shiftable day boundary; export and statistics;
configurable file granularity; a full-text index; signing and notarization.

One more that this plan added rather than the spec: the storage seam means a second backend is now
a self-contained piece of work. It conforms to `NotesRepository`, passes
`assertRepositoryConformance`, and gets named in `Composition.swift` — nothing else changes.
