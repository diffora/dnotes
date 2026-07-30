# Manual checklist (design §9.3)

The parts of dnotes that a test cannot reach: global hotkeys, window activation,
appearance. Run this before calling a change done. Use a **scratch notes folder**
(Settings → Choose…), not the real one, for anything under "Storage".

Build and launch: `./scripts/bundle.sh && open dnotes.app`
Quit: `⌘Q`, the Dock icon's menu, or `pkill -f dnotes.app`.

## Capture — the primary scenario

- [x] `⌥Space` from another app: panel appears, typed characters land in the field. *(verified 2026-07-29)*
- [ ] `⏎` saves and closes; focus is back in Safari with the caret where it was.
- [x] The line is in `YYYY-MM.md` under today's heading, and nothing else changed. *(verified 2026-07-29: two captures, in order, two-line diff)*
- [ ] Hotkey fires with **fullscreen Zoom** active — the panel appears over it rather
      than switching Spaces, and typing reaches the field.
- [ ] Same in a **fullscreen terminal**.
- [ ] `⇧⏎` saves and keeps the panel open; three thoughts in a row are three lines.
- [ ] `esc` with typed text closes the panel; the text is there on the next open.
- [ ] `⌥Space` twice toggles the panel closed, and half-typed text is still there on
      the next open (every exit keeps the draft, not only `esc`).
- [ ] `⌘L` in the panel closes it and opens the notes window.
- [ ] `⌘,` in the panel closes it and opens Settings.
      These two are the app's only guaranteed way in when the menu bar item is hidden,
      so they matter more than the icon does.
- [ ] A taken hotkey shows a conflict message in Settings rather than dying silently.
      (Occupy `⌥Space` elsewhere, relaunch, check Settings, then undo.)
- [ ] Nothing ever prompts for Accessibility permission.

If typed characters do **not** reach the field, flip
`CapturePanel.usesActivationFallback` to `true` (§6 fallback) and re-run this section.

## Dock and menus (rewritten 2026-07-30, when the Dock icon became a setting)

Both states of "Show in Dock" have to be walked. The automated tests cover the stored
preference; nothing below can be unit-tested, because activation policy is global
AppKit state.

Dock icon **off** (the default):

- [ ] A fresh launch shows no Dock icon and no bounce, and the app is absent from `⌘Tab`.
- [ ] The menu bar icon is there, and `⌥Space` and `⌥⇧Space` both work — with no Dock
      icon these are the only way in, so a failure here means a locked-out app.
- [ ] `⌘C`, `⌘V`, `⌘A`, `⌘Z` work in the capture field and the inline row editor, and
      `⌘Q` quits. There is no drawn menu bar in this mode; the key equivalents still
      have to reach the key window.

Dock icon **on**:

- [ ] Turning the switch on makes the icon appear without a relaunch, and the Settings
      window still takes keystrokes afterwards.
- [ ] The Dock shows the app icon, and the app appears in `⌘Tab`.
- [ ] The menu bar at the top of the screen is drawn and its items work.
- [ ] Clicking the Dock icon with no window open opens the notes list.
- [ ] Turning the switch back off makes the icon disappear, and the Settings window
      still takes keystrokes.
- [ ] "Restart dnotes" appears only after the switch is touched, and relaunches into the
      chosen mode.

## Start at login (added 2026-07-30)

Nothing here is unit-tested: the state lives in the system, not in this app. That the
API works under ad-hoc signing and under this bundle id was measured on a harness; what
is left is the wiring.

- [ ] Settings → Startup → "Start dnotes at login" turns on, and the app appears in
      System Settings → General → Login Items.
- [ ] Turning it off removes it from that list.
- [ ] Switch it off in **System Settings** while dnotes' Settings window is open, then
      bring dnotes forward: the checkbox has followed the system rather than kept
      showing its own answer.
- [ ] Reboot with it on: dnotes is running, and `⌥Space` works without launching
      anything by hand.
- [ ] It is the copy in `/Applications` that started, not a build from a folder — this
      is what the caption warns about, and it is worth checking once.

- [ ] **Re-verify the primary scenario in both modes:** `⌥Space` from another app still
      does not steal focus, and `⏎` returns it. The panel is non-activating because of
      its style mask, not the activation policy — but this is the one assumption the
      whole app rests on, so it gets checked on both sides of the switch.

## Tagging

- [ ] Typing `#` opens the completion list with counts.
- [ ] Typing more narrows it; `↑↓` moves the highlight; `⇥` completes.
- [ ] An unknown tag offers a "new tag" row and `⇥` accepts what was typed.
- [ ] `⌘1`–`⌘3` append a frequent tag at the end without moving the caret.

### Completion layout (added 2026-07-30, after the panel drew over its own field)

The panel window used to keep its build-time height forever, so a list taller than
120pt overflowed on both sides of it. `ChipFlowTests` covers where rows break; the rest
is AppKit sizing and has to be looked at.

- [ ] `#` with a folder that has **many** tags: the chips wrap into rows, the panel
      grows downward, and the text field stays exactly where it was.
- [ ] The text field is never drawn outside the panel's rounded background — this is
      the bug itself, so check it at several tag counts (1, 5, 20, everything).
- [ ] Past about five rows of chips the list scrolls instead of the panel growing, and
      the panel never reaches the bottom of the screen.
- [ ] `↑↓` past the visible rows scrolls the selection into view rather than moving a
      highlight nobody can see.
- [ ] Narrowing the filter shrinks the panel again, and deleting the `#` returns it to
      the single hint row it started at.
- [ ] `⏎` with no tag at all still saves the line.
- [ ] A URL with an anchor (`https://example.com/page#anchor`) does not open completion.

## Main window

- [ ] `⌥⇧Space` from another app: the window is active and `↑↓` works without a click.
- [ ] Days are separators in one reverse-chronological flow; today's says "Today".
- [ ] Clicking the circle completes the line — the file gains `- [x] `; clicking again
      reopens it and the file goes back to `- `.
- [ ] Double-clicking a row edits it in place; `⏎` commits, `esc` cancels.
- [ ] Right-clicking a row offers Complete/Reopen, Edit and Delete.
- [ ] Hovering a row highlights it, so it reads as clickable.
- [ ] `↑↓` move the selection; it clamps at the ends instead of wrapping, and with
      nothing selected `↓` starts at the top and `↑` at the bottom.
- [ ] `␣` completes the selected line — the file gains `- [x] `; `␣` again reopens it
      and the file goes back to `- `.
- [ ] `e` starts editing the selected row, same as `⏎`.
- [ ] `⌫` deletes the selected row and the selection lands on the row that took its
      place, so a run of deletes needs no mouse in between. **No undo** — see below.
- [ ] Typing in the search box still types `e` and backspaces normally, i.e. the list's
      plain-key bindings do not leak into text fields.
- [ ] While editing a row, `e` and `⌫` edit the text rather than acting on the list.
- [ ] `⏎` edits in place; `⏎` commits, `esc` cancels and leaves the text as it was.
- [ ] Editing a row and then clicking another one **saves** the typed text rather than
      dropping it, and the edit field closes. `⌘Z` reverses it if that was not wanted.
- [ ] `⌘⌫` deletes the selected line and only that line.
- [ ] `⌘F` focuses search; typing narrows the list; `émile` matches `Émile`,
      `cafe` matches `CAFÉ`.
- [ ] A completed entry from an earlier day is hidden but still found by search.
- [ ] Clicking a chip filters; clicking it again clears; other chips keep their counts.
- [ ] `esc` clears search and chip.
- [ ] The completed toggle brings earlier completed entries back.

## Storage and errors (§8) — scratch folder

- [ ] Point the folder at a path that does not exist → banner appears, list is empty,
      nothing crashes.
- [ ] With the folder gone, capture three lines → banner says "3 unsaved entries".
- [ ] Quit and relaunch → still 3.
- [ ] Recreate the folder → the queue drains on its own, and the lines land under the
      day they were captured on, in the order they were typed.
- [ ] `chmod 500` the folder, capture a line → it queues; `chmod 755`, hit Retry → it lands.
- [ ] Edit a month file in an editor → the change shows up in the app within a second.
- [ ] The app's own writes do not make the list flicker.
- [ ] Delete a line externally, then press `␣` on it in the app → a quiet message and
      the file is **not** rewritten.
- [ ] Put `> a quote` and a markdown table in a month file → they do not appear as
      entries, and editing a neighbouring line leaves them byte for byte intact.
- [ ] `git diff` in the notes folder shows only the lines actually changed.

## Undo, empty state and links (added 2026-07-30)

- [ ] Delete a row, then `⌘Z` — the line is back, at the end of its day.
- [ ] `⌘Z` also reverses a completion, an edit and a capture.
- [ ] `⌘Z` repeated walks several changes back, and stops when there is nothing left.
- [ ] While editing a row, `⌘Z` undoes typing rather than the list's last change.
- [ ] With an empty folder the window says "No notes yet" and names the capture hotkey.
- [ ] With a search that matches nothing it says "Nothing matches" instead.
- [ ] A URL in an entry is underlined and opens in the browser on click.
- [ ] With an issue URL template set in Settings, `ABC-1234` becomes a link too;
      with the field empty it stays plain text.
- [ ] A link is coloured but not underlined until ⌘ is held.
- [ ] Holding ⌘ and hovering a link underlines it and shows the pointing hand; the
      underline appears and disappears as ⌘ goes down and up, without moving the mouse.
- [ ] ⌘-clicking a link opens it. Clicking it *without* ⌘ selects the row instead —
      a stray click can never launch a browser.
- [ ] Clicking the words next to a link still selects the row; double-clicking them
      still edits it.
- [ ] A long entry that wraps onto two lines gets the hand cursor on the right part of
      each line, not offset.

## Appearance

- [ ] Light and dark themes both read correctly.
- [ ] Switching the system theme with the window open updates it live.
