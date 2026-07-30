# dnotes — macOS quick-capture notes and task app — Design

- **Status**: Draft (approved in brainstorming, review applied, ready for implementation plan)
- **Owner**: diffora
- **Platform**: macOS, Swift 6.2 / SwiftUI + AppKit
- **Storage**: plain markdown files in a user-chosen folder
- **Date**: 2026-07-29

## 1. Context

Notes and tasks currently live in `dnotes/notes.md` — a flat markdown file with
day headings (`## 2026-07-29`) and one entry per line. The format is fine: it
reads by eye, sits in git, and edits in any editor. What is not fine is the
input path — writing a thought down means finding a terminal or an editor,
opening the file, appending a line. During a call or a debugging session that is
expensive enough that the thought is simply lost.

Existing tools (Things, Todoist, Obsidian, Apple Notes) solve capture, but each
imposes its own model — projects, areas, due dates, nesting — and its own
storage. What is wanted here is the opposite trade: keep the model as simple as
possible, keep the files mine, and spend all the engineering on capture speed.

## 2. Goals

1. **Capture in two seconds from any app** — global hotkey, one line of input,
   `⏎`, focus returns where it came from. This is the primary scenario;
   everything else is subordinate to it.
2. **One entity** — the line. A note becomes a task simply because it can be
   closed. No separate types, no due-date fields, no priorities, no projects.
3. **Markdown as the source of truth** — data is readable, hand-editable, and
   lives in git or any cloud folder. Delete the app and the notes remain.
4. **Keyboard-driven overview** — a single reverse-chronological list, substring
   search, tag filter, close an entry with one key.
5. **Native look and behavior** — system fonts and materials, light and dark
   themes, no web shell.

## 3. Non-goals

- Sync as an app feature. The folder can go in iCloud Drive, Dropbox, or git —
  that is enough; there is no sync protocol of our own.
- Mobile or web client.
- Multi-user work, sharing, collaborative editing.
- Nested lists, subtasks, links between notes, backlinks.
- Due dates, reminders, recurring tasks, time estimates.
- Rich text, images, attachments.
- Distribution and signing: the app is built for personal use, notarization is
  out of scope (see §11).

## 4. Storage format

`dnotes` works with a single folder (chosen in settings, defaulting to
`~/Projects/diffora/dnotes`, where `notes.md` currently lives). Inside it, one
file per month:

```
~/Projects/diffora/dnotes/
  2026-06.md
  2026-07.md
```

**File discovery.** Only files whose name matches the `YYYY-MM.md` pattern
exactly are treated as notes; subdirectories are not traversed. Everything
else — `README.md`, `notes.md`, and cloud conflict copies such as
`2026-07 2.md` (iCloud) or `2026-07 (conflicted copy).md` (Dropbox) — is neither
read nor written. The strict pattern *is* the defense against conflict copies:
when a folder is edited from two machines, the cloud drops a copy next to the
original, and without the pattern half the month would appear twice in the list
as ghosts.

**First-launch import.** If the chosen folder contains no file matching the
pattern but does contain `notes.md`, its content is parsed and split by month:
each day goes into the file for its month, unparsed lines are carried over byte
for byte per §4.3, and any lines preceding the first day heading go to the top
of the earliest file created. `notes.md` itself is neither deleted nor renamed —
it simply stops matching the pattern; whether to remove it is the user's call.
An app that promises never to lose text does not open by deleting someone's
file. The import runs once: on the next launch the monthly files already exist.

Inside a file: day sections, and inside a day, entries, one per line:

```markdown
## 2026-07-29

- open source editor plugin #oss
- [x] run their artifact analysis tool
- single node metrics — ABC-1234 #infra
```

### 4.1 Parsing rules

| Line | Meaning |
| --- | --- |
| `## YYYY-MM-DD` | start of a day |
| `- text` | open entry |
| `- [ ] text` | open entry (compatibility with other tools) |
| `- [x] text` | closed entry |
| anything else | **unparsed line**: preserved byte for byte, not treated as an entry |

- Days appear in ascending date order; a new day is inserted in its place by
  order, not appended at the end of the file.
- Entry order within a day is insertion order. Time is not stored.
- Tags are `#word` substrings in the entry text; there is no separate field. The
  tag body is letters, including non-ASCII ones, digits, `-`, and `_`; the first
  character outside that set ends the tag, so `#infra,` yields the tag `infra`,
  not `infra,`.
- A `#` starts a tag when it is at the start of a line, or follows whitespace or
  one of the opening characters `(`, `[`, `{`, `«`, `"`. After a letter, a
  digit, or `/` it is not a tag, which is what excludes URL anchors
  (`https://example.com/page#anchor`). The stricter rule "not a tag when it
  follows any non-whitespace character" would cost us too much: `(#infra)` is
  ordinary writing and should not silently lose its tag.
- An entry's date comes from the day heading. No identifiers of our own are
  written to the files: an entry's identity is the pair "file + line number",
  recomputed on every read.

### 4.2 Completing an entry

A completed entry stays where it is within its day — only the prefix changes
(`- ` → `- [x] `). Text never migrates between files or days, so a day in the
file remains an honest history, and "complete" edits exactly one line.

### 4.3 Preservation invariant

**Rewriting a file never loses what we did not understand.** Unparsed lines,
blank lines, and separators are preserved byte for byte; `parse → serialize`
with no changes reproduces the original text bit for bit. This is the project's
key invariant and its most densely tested one (§9.1).

Line endings are part of that preservation. When inserting new lines we use the
file's dominant style: if the file has more `CRLF` than `LF`, we append `CRLF`,
otherwise `LF`; a new file gets `LF`. Without this rule a single capture from
the panel turns a CRLF file into a mixed one, and the very next round-trip stops
being byte-exact.

### 4.4 Writing to disk

- Writes are atomic: a temporary file next to the target, then a replace.
- Before writing, the file's mtime is compared against the one seen at the last
  read. If the mtime changed, the file is re-read and the operation is reapplied
  by **matching the line's text**, not its number.
- **Ambiguity resolution.** Identical lines within one day are normal
  (`- write the tests` twice in a day), so a text match alone is not enough — and
  hitting the neighboring line is data loss, i.e. a violation of §8. The rule:
  1. search only within the same day the read came from; a match in an adjacent
     day never counts;
  2. at read time, remember not only the text but the entry's ordinal among the
     lines identical to it within that day (`N`); after the re-read, edit the
     `N`-th occurrence;
  3. if the number of identical lines dropped, the `N`-th occurrence no longer
     exists, or the day itself is gone — the operation is cancelled outright.

  Ambiguity always resolves to refusal rather than a guess: a cancelled
  operation costs the user one repeated keystroke, a corrupted neighboring line
  costs them silently lost text.
- If the line is not found after the re-read (deleted externally), the operation
  is cancelled, the user is notified, and the file is not rewritten.

## 5. Architecture

Five units, each with a single responsibility:

| Unit | Job | Knows about |
| --- | --- | --- |
| `MarkdownDocument` | `parse(String) -> Document`, `serialize(Document) -> String`; holds entries and unparsed lines | nothing external |
| `NotesRepository` | the only thing that touches files: reading the folder, `append`/`toggleDone`/`edit`/`delete`, atomic writes, mtime guard, folder watching | `MarkdownDocument`, `FileManager`, FSEvents |
| `NotesModel` (`@Observable`) | UI state: entries, search string, selected tag, whether to show completed; calls the repository | `NotesRepository` |
| `HotKeyManager` | wrapper around `RegisterEventHotKey`, exposes a "pressed" event | Carbon |
| `CapturePanel` | `NSPanel` (`.nonactivatingPanel`): show, take a line, hide | AppKit, `NotesModel` |

Views — `CaptureView`, `MainWindowView`, `SettingsView` — read `NotesModel` and
never reach for the repository directly. Menu bar is `MenuBarExtra`.

The folder path is injected into `NotesRepository`, so tests use a temporary
directory rather than the user's folder.

### 5.1 Data flow

**Capture:** hotkey → `CapturePanel` shown → `⏎` → `NotesModel.add(text)` →
`NotesRepository.append` → line appended to today's day (the day is created if
missing; the month file is created if missing) → panel hidden. The main window
redraws from the same model change — an entry has one way in, regardless of
where it was added from.

**"Today" is the system calendar date** in the current time zone, with no
day-boundary offset. An entry made at 00:30 lands in the new day, and an evening
session that runs past midnight is split across two days in the file. The trade
is deliberate: the date in the heading always matches what the system shows, and
a file opened by hand in any editor needs no mental correction. A shiftable day
boundary is §12.

**External edit:** FSEvents → `NotesRepository` re-reads the changed file →
`NotesModel` updates → the list redraws. File and app always converge, because
there is a single source of truth — the file.

**Our own writes must not come back through FSEvents.** After the atomic
replace, `NotesRepository` remembers the resulting mtime and ignores the event
carrying that same mtime. Otherwise every capture costs an extra "re-read →
rebuild model → redraw list" cycle: a visible flicker of the list for nothing,
and in the worst case a race with the edit just applied. On top of that, a
~200 ms debounce: `git checkout` and cloud sync change a batch of files at once,
and there is no reason to parse the folder once per event in the batch.

### 5.2 Search and filtering

At startup every file in the folder is parsed; filtering is a pass over the
in-memory entry array. At realistic volumes (tens of thousands of lines) that is
microseconds, which is why there is no index, no FTS, and no SQLite. If volume
ever becomes a problem, an index goes behind `NotesRepository` with no UI
changes.

## 6. Capture panel

- Invoked by a global hotkey, `⌥Space` by default (configurable). If the
  combination is taken, `RegisterEventHotKey` returns an error — it is shown in
  settings next to the hotkey field ("combination in use, pick another"). A
  silently dead hotkey is unacceptable: you would find out about the conflict at
  the exact moment the thought is already lost.
- `NSPanel` with the `.nonactivatingPanel` style, floating above all windows
  including fullscreen ones: it does not take focus from the active app, and
  after it closes focus stays where it was. The panel is borderless, so
  `canBecomeKey` is overridden to `true` and `collectionBehavior` is
  `[.canJoinAllSpaces, .fullScreenAuxiliary]`.
- **Fallback if the non-activating panel will not hold keyboard input.** This is
  the riskiest assumption in the project, so the backup path is fixed here in
  advance rather than invented on the way: activate the app explicitly
  (`NSApp.activate(ignoringOtherApps: true)`), remember
  `NSWorkspace.shared.frontmostApplication` before showing, and reactivate it
  when the panel closes. From the outside the behavior is the same — focus
  returns where it came from — at the cost of one extra activation cycle. The
  choice between the primary path and the fallback is made by the spike in §10,
  before task 1.
- **Spike result (2026-07-29): the primary non-activating path holds keyboard
  input.** Verified on macOS 26.5 against a normal (non-fullscreen) app: `⌥Space`
  showed the panel over the frontmost window without activating dnotes, typed
  characters landed in the field rather than in the app underneath, and `⏎`
  appended the line to today's heading in `2026-07.md` — two captures in a row,
  in order, with a diff that touched nothing else. So
  `CapturePanel.usesActivationFallback` stays `false`.
  **Still unverified:** the two fullscreen cases of §9.3 (fullscreen Zoom, a
  fullscreen terminal) and whether focus returns to the originating app after the
  panel closes. Those remain open items on the manual checklist; if either fails,
  the fallback is one constant away.
- One text field, no buttons and no dropdowns. Width 560 pt.
- `⏎` saves and closes. `⇧⏎` saves and keeps the panel open, for writing several
  thoughts in a row. `esc` closes, keeping what was typed as a draft. There are
  no multi-line entries by design: one line, one entry.
- **Tagging while typing:**
  - the three most frequent tags of the last 30 days are always visible under
    the field, bound to `⌘1`–`⌘3`; pressing one appends the tag at the end of
    the line without moving the cursor;
  - `#` opens completion over all existing tags (with entry counts) plus a
    "create tag" item; `⇥` completes, `↑↓` selects;
  - tags are optional: `⏎` with no tag saves the entry into the day as is.
- A tag stays part of the line's text in the file — there are no hidden fields.
- **Amended 2026-07-30 (bug fix):** completion draws its tags as chips flowing left
  to right, not one per line, and the list scrolls past about five rows. It used to be
  a line per tag inside a panel window whose height never changed from the 120pt it was
  built with — so a long list was laid out over the text field rather than under it.
  Two things were wrong and both are fixed: the window now follows its content's height
  (holding the **top** edge still, so the field never moves under the reader), and the
  content is bounded, so no tag list can push the panel off the bottom of the screen.

## 7. Main window

- Invoked by `⌥⇧Space` (configurable), from the menu bar, from the Dock icon, or with
  `⌘L` from the capture panel. **Amended 2026-07-29:** the app was originally marked
  `LSUIElement` (menu bar only, no Dock icon). On this machine a full menu bar hides
  the status item — its button is placed at x 597 of a 1512pt screen, left of the
  notch, where the frontmost app's menus win — so the app is now a regular app with a
  Dock icon, and the menu bar item became an extra rather than the only door. Nothing
  about capture changes: the panel is non-activating because of its style mask, not
  because of the activation policy. The app still will not become active on its own: showing the
  window is always accompanied by `NSApp.activate(ignoringOtherApps: true)`, or
  the window appears with a keyboard that does nothing. Unlike the capture
  panel, activation is wanted here — you open the main window in order to work
  in it.
- **Amended 2026-07-30:** the Dock icon is a setting rather than a decision —
  `SettingsStore.showsDockIcon`, a switch in Settings, applied live by
  `AppDelegate.applyActivationPolicy()`. It is **off by default**: a tool for capturing
  one line does not need a slot in the Dock and in `⌘Tab` all day. The notch problem the
  2026-07-29 amendment describes has not gone away — it is now carried by the hotkeys,
  which are registered before any window exists and report a conflict in Settings rather
  than failing silently. With the Dock icon off, `⌥Space` and `⌥⇧Space` are the way in.
  Switching live needs `NSApp.activate` afterwards or the menu bar is left undrawn and
  the settings window unresponsive, and Settings offers a restart beside the switch for
  what re-activation does not settle.
- A single reverse-chronological list of all entries. Days are separators in the
  flow. There is no folder sidebar and no split between "notes" and "tasks".
- Search in the toolbar filters the list by substring as you type (case- and
  diacritic-insensitive).
- Tags are chips above the list with entry counts; a click filters, a second
  click clears the filter. Search and tag filter compose.
- Keyboard: `↑↓` navigates, `␣` completes/reopens an entry, `⏎` edits the line
  in place (with the same tag completion), `⌘⌫` deletes, `⌘F` focuses search,
  `esc` clears search and filter.
- **Amended 2026-07-29, at the owner's request:** `e` also starts editing, and plain
  `⌫` also deletes. The mouse can do the same things — clicking the circle
  completes, double-clicking a row edits it, right-clicking offers all three —
  because a drawn checkbox that cannot be clicked is a broken affordance.
  Plain `⌫` was a deliberate risk while there was no undo; §12 now records that undo
  exists, which is the mitigation that risk was waiting for.
- **Leaving a row being edited commits the text, it does not discard it** (added
  2026-07-30). §8 does not allow typed text to disappear, and with undo in place an
  unwanted save is recoverable where lost typing would not be. `esc` still discards,
  because that is what asking to cancel means.
- **A link is live only under `⌘`** (added 2026-07-30). URLs and issue keys are
  coloured always, so a line reads as containing a reference, but the underline, the
  pointing-hand cursor and the click that follows the link all require `⌘` — the way
  editors do it. Without that, an ordinary click meant for selecting a row could
  launch a browser.
- **Visibility of completed entries:** an entry completed today stays visible,
  struck through, until the end of the day; from the next day it is hidden and
  reachable via the toolbar filter or search.
- **Amended 2026-07-29, at the owner's request:** the toolbar toggle became a
  three-way filter — *open only*, *open + done today* (the default above), and
  *everything*. "Open only" hides completed entries even from today, so a day's
  remaining work reads at a glance. Search un-hides completed entries in the default
  state, which is what "reachable via search" means, but deliberately not in
  *open only*: a completed search hit would read as the filter being broken. The
  choice is remembered across launches.
- Appearance: system fonts, `NSVisualEffectView` as the background, automatic
  light and dark themes.
- **Tags are coloured** (added 2026-07-30, at the owner's request). In the chip bar above
  the list the colour is a fill, because a chip *is* a button. Where a tag appears as text
  it is coloured semibold ink and never a pill: this list already decided that a reference
  gets colour and not a box (§7, links), and a pill in running text would promise that the
  tag is clickable, which it is not. A completed entry's tags go quiet along with the rest
  of the line. The stored markdown is untouched — §4.1 keeps the tag as plain text, and
  this is only how it is drawn.
- **Where the tags sit in a row is a setting** (added 2026-07-30, at the owner's request),
  remembered across launches. *At the end of the row* is the default: the tags come out of
  the text and become chips against the right edge, so the note reads without them and the
  tags form a column that can be scanned on its own. *In the text* leaves each tag where
  it was typed. Two consequences of the default are worth stating rather than discovering.
  Editing opens the **stored** line, tags and all, so the text changes shape under the
  cursor — the one place where what the row shows is not what the file holds. And a line
  that is nothing but tags (`#daily`) cannot be drawn this way at all without leaving an
  empty row, so such a line falls back to the inline layout. The trailing chips are not
  buttons: they sit inside a row whose click selects it and whose double-click starts an
  edit, and a target that swallows those would be worse than one that does nothing —
  filtering by tag stays on the chip bar above.
- **The palette is eight colours, and its constraints were measured, not chosen.** A tag
  is text, so each colour clears WCAG 4.5:1 against *both* window surfaces — which is why
  the light steps are deep and wine-like rather than bright, the way light editor themes
  are. Blue is excluded by a ±45° hue guard: it belongs to links, and a blue-ish tag reads
  as a link that does not work. Teal is absent because sRGB cannot give cyan enough chroma
  at that lightness to stop it reading as grey, and red and orange cannot both be
  canonical because they sit ~29° apart and collapse into one pair. Stated plainly: eight
  colours do **not** clear the pairwise-separation floors a chart palette must clear
  (worst pair ΔE 12.1 light, 11.2 dark, against a floor of 15), and under deuteranopia
  much of the set converges. That is a deliberate trade, sound only because a tag's own
  name is always written beside its colour — here colour is a scanning aid, never what
  carries identity.
- **Which colour a tag gets:** a hash of its folded name picks a first choice, and if that
  colour is already taken the tag moves to the least-used one; the result is recorded, so
  a tag's colour never shifts because a *different* tag appeared later. The first eight
  tags therefore get eight different colours. Hashing alone was tried and rejected on
  measurement: it put two of five real tags on one colour and averaged 3.9 distinct
  colours per five tags, spending the palette on collisions. The cost of recording is
  that the same tag can be a different colour in another folder or on another Mac; within
  one install it never moves, which is the property that matters, since the colour exists
  to be recognised tomorrow. Right-clicking a chip overrides the colour by hand, and
  *Automatic* removes the override rather than freezing today's answer.

## 8. Error handling

The general rule: **the app has no right to silently lose text in any
scenario.**

That rule implies two distinct entities that are easy to conflate under the
single word "draft":

- **Panel draft** — one line, unfinished and unconfirmed. Lives in
  `UserDefaults`, is overwritten by the next `esc`, and is restored into the
  field the next time the panel opens. Exactly one slot, which is all that is
  needed: there is only one panel.
- **Pending queue** — an array of entries confirmed with `⏎` that could not be
  appended to a file. It also survives a restart. An array, not a slot: three
  captures in a row with iCloud detached is three entries, and a single cell
  would lose two of them. Each element carries its own creation date and, when
  the queue is drained, is appended to **its own** day rather than today —
  otherwise yesterday's evening capture drifts into today and the day stops
  being an honest history. The queue drains as soon as the folder is available
  again, in insertion order.

| Failure | Behavior |
| --- | --- |
| Folder not chosen, moved, or not downloaded from the cloud | Banner with a "choose folder" button, read-only mode. Confirmed entries go to the pending queue and are appended as soon as the folder is available |
| File changed between read and write | mtime guard from §4.4: re-read, reapply by line text with ambiguity resolution |
| Line disappeared (deleted externally), or matches became ambiguous | Operation cancelled, quiet notification, file not rewritten |
| File contains unfamiliar markup | Not an error: lines are preserved byte for byte and not treated as entries (§4.3) |
| Write error (no space, no permission) | Entry goes to the pending queue, stays in the UI with an "unsaved" badge and a retry button |
| Crash or restart with typed but unconfirmed text | The panel draft is restored on the next open |
| Crash or restart with a non-empty queue | The queue survives the restart and drains on the first successful access to the folder |

## 9. Testing

### 9.1 `MarkdownDocument` — unit, the densest layer

- **Round-trip as a property:** for arbitrary input text,
  `serialize(parse(text)) == text` byte for byte — including unparsed lines,
  blank lines between days, CRLF, and a missing trailing newline.
- Parsing every entry form: `- `, `- [ ] `, `- [x] `, with varying amounts of
  whitespace after the dash.
- Tags: at the start, middle, and end of a line; accented letters; `-` and `_` inside;
  several tags in one line.
- Tags, leading context: `#` after `(`, `[`, `«` is a tag (`(#infra)`); `#`
  after a letter or digit is not; a URL anchor
  (`https://example.com/page#anchor`) is not.
- Tags, trailing context: `#infra,` and `#infra.` both yield `infra`;
  `#infra-api` yields `infra-api`.
- Inserting a new day: into an empty file, before existing days, between them,
  and at the end; idempotence of adding the same day twice.
- Line-ending style on insertion: a CRLF file gets CRLF, an LF file gets LF, no
  mixed file results; a new file gets LF.
- Completing and reopening an entry changes only the prefix of its own line.

### 9.2 `NotesRepository` — integration, on a temporary folder

- `append` into an existing day, into a new day of an existing month, into a new
  month file.
- `toggleDone`, `edit`, `delete` — plus a check that neighboring lines are
  untouched.
- File discovery: `YYYY-MM.md` files are read; `README.md`, `notes.md`,
  `2026-07 2.md`, and a subdirectory are not.
- Import: a folder holding a single `notes.md` spanning two months produces two
  `YYYY-MM.md` files with the same content, leaves `notes.md` untouched on disk,
  and imports nothing a second time on the next launch.
- mtime conflict: the file is swapped between read and write — the operation is
  applied to the current content.
- **Duplicates under an mtime conflict:** a day holds two identical lines, we
  target the second, and the file changes between read and write — exactly the
  second one is edited; if the identical lines have become fewer, the operation
  is cancelled and the file is unchanged.
- Vanished line: the operation is cancelled, the file is unchanged.
- Read-only or missing folder: an error is returned, the entry goes to the
  pending queue and is appended to its own day once access is restored.
- FSEvents: an external change to a file updates the entry set; our own write
  does not trigger a re-read; a batch of changes collapses into a single parse
  via the debounce.

### 9.3 UI — manual checklist

- The hotkey fires with fullscreen Zoom active and in a fullscreen terminal;
  after `⏎` focus is back in the originating app.
- Taken hotkey: settings show a conflict message rather than staying silent.
- Main window via `⌥⇧Space` from another app: the window is active and its
  keyboard works.
- `esc` with typed text: the panel closes, and the text is there on reopen.
- Light and dark themes, and a system theme change on a live window.

## 10. Implementation order

0. **Capture panel spike** (~30 lines, thrown away): `NSPanel`
   `.nonactivatingPanel` plus `RegisterEventHotKey`, hotkey → panel → type text
   → `⏎` → focus returned. Verify over fullscreen Zoom and a fullscreen
   terminal, with `LSUIElement` set. The result is the choice between the
   primary path and the fallback in §6, written into the spec before task 1. The
   blast radius of being wrong is bounded to `CapturePanel` — §5 keeps it apart
   from the parser, repository, and model — but getting the answer in half an
   hour is cheaper than getting it at step 5.
1. `MarkdownDocument` plus round-trip and parsing tests (§9.1) — no UI.
2. `NotesRepository` plus integration tests (§9.2): file discovery and import,
   the operations, the mtime guard with duplicates; FSEvents last.
3. `NotesModel` — entries, search, tag filter, visibility of completed entries.
4. App skeleton: `MenuBarExtra`, folder settings, building the `.app` bundle.
5. `HotKeyManager` + `CapturePanel` + `CaptureView` without completion — the
   main end-to-end scenario works.
6. Tag completion and `⌘1`–`⌘3` in the capture panel.
7. `MainWindowView`: list, days, keyboard navigation, completing an entry.
8. Search and tag chips in the main window.
9. Error handling from §8: folder banner, panel draft, pending queue, "unsaved"
   badge.
10. Visual polish: materials, themes, panel appearance animation.

## 11. Build and distribution

Built with SwiftPM; the `.app` bundle (`Info.plist`, app icon generated from
`images/icon.png`) is assembled by a script. `LSUIElement` is `true` again, but it is
now only the launch default — the activation policy is a setting, see the 2026-07-30
amendment in §7. Signing and notarization are out of scope: the
app is for personal use, and the bundle is ad-hoc signed, which is enough to run
it locally.

**Amended 2026-07-29:** this section originally gave the reason as "full Xcode is
not installed, only the Command Line Tools". Xcode 26.6 is now installed
(toolchain Swift 6.3.3), so that reason no longer holds — but the conclusion
does, for a different reason: there is no Developer ID certificate on this
machine, and getting one means joining the paid Apple Developer Program. Handing
the app to other people therefore still needs one thing this project has not
bought, rather than one thing it has not downloaded. `notarytool` is available
the moment a certificate exists, and none of this affects the architecture.

The package keeps `swift-tools-version: 6.2` rather than moving to 6.3: nothing
here needs the newer version, and the lower floor means the project still builds
from Command Line Tools alone.

The global hotkey is registered through `RegisterEventHotKey`, which does **not**
require Accessibility permissions — there is no permission prompt on first
launch.

## 12. Future work

**Added 2026-07-30, not deferred: undo.** `⌘Z` reverses the last change — a capture, a
completion, an edit, a delete — up to fifty steps back. It was not in the original plan
because §7 deleted with `⌘⌫` only; once plain `⌫` was added, one unmodified keystroke
could destroy a line, and §8 does not allow that to be unrecoverable. A restored line
returns to the end of its day rather than its old position: the position is gone from
the file with the line, and the text is what matters. There is no redo — the point is
rescuing a slip, and a slip is rarely worth repeating.

Deliberately deferred, ordered by expected value:

- ~~**Auto-links** — `ABC-1234` and URLs become clickable~~ — **done
  2026-07-30.** URLs need no configuration; issue keys need a URL template in
  settings, because only the reader knows which tracker their keys live in, and a
  guessed host makes every key a broken link. Nothing is added to the stored line:
  the app recognises what the text already says, so §2.3 still holds.
- Moving an open entry to today with one key.
- A shiftable day boundary (e.g. 04:00), so an evening session past midnight is
  not split across two days (§5.1).
- Export and statistics: how many entries were completed this week.
- Configurable file granularity (day / month / year).
- A full-text index, if the volume of notes ever grows enough for in-memory
  filtering to become noticeable.
- Signing and notarization for handing the app to other people.
