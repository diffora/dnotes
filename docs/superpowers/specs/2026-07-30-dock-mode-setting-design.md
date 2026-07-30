# Dock mode as a setting

Design, 2026-07-30. Amends §7 and §11 of `2026-07-29-dnotes-design.md`.

## The problem

Whether the app has a Dock icon is currently a constant. `main.swift` calls
`setActivationPolicy(.regular)` unconditionally and `Info.plist` sets
`LSUIElement` to `false`. That was a deliberate choice on 2026-07-29 — with a full
menu bar, this machine places the status item left of the notch, where the
frontmost app's menus win, so the status item was not a reliable door into the
app and the Dock icon became the reliable one.

The owner wants the choice back, and wants dockless to be the default: an app for
capturing one line at a time does not need a slot in ⌘Tab or a permanent Dock
icon, and it is reached by hotkey anyway.

## Decisions

**The default becomes dockless.** A fresh install, and any existing install that
has never expressed a preference, starts with no Dock icon.

**The known cost, stated where it will be found.** With no Dock icon, and the
status item possibly hidden behind the notch, `⌥Space` (capture) and `⌥⇧Space`
(notes list) are the only dependable way to reach the app. That is acceptable —
those hotkeys are the primary interface, they are registered before any window
exists, and a conflict on either is already surfaced in Settings rather than
failing silently. It is recorded here because it is the exact reason §7 chose the
Dock icon in the first place, and a future reader must not rediscover it by
losing access to the app.

**The setting takes effect immediately, with a restart button as the escape
hatch.** Activation policy can be changed at runtime, and making the user
relaunch to see a checkbox take effect is worse than the AppKit quirks that come
with switching live.

**Only the Dock is configurable.** The status item stays unconditional. Making
both optional would allow a state in which the app has no visible presence at
all, and guarding against that state costs more than the option is worth.

## The setting

`SettingsStore` gains:

```swift
/// No Dock icon by default: the app is reached by hotkey, and a capture tool does
/// not need a slot in ⌘Tab. Turning this on restores a regular app — see §7 of the
/// design doc for why the Dock icon was once the only reliable door.
public var showsDockIcon: Bool {
    didSet { defaults.set(showsDockIcon, forKey: "dnotes.showsDockIcon") }
}
```

Read in `init` as `defaults.object(forKey:) as? Bool ?? false` — not
`defaults.bool(forKey:)`, which cannot tell "absent" from "false". They mean the
same thing today because the default is `false`, but the distinction is what lets
the default change later without silently overwriting a stored preference.

`Info.plist` sets `LSUIElement` to `true`, matching the new default, so the
common case launches without a Dock icon ever appearing. The plist is the launch
default; the setting is the authority, and code reconciles them at startup.

## Startup

`main.swift` builds the delegate before choosing a policy, so the setting is read
through `SettingsStore` and not through a second, parallel `UserDefaults` lookup:

```swift
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
delegate.applyActivationPolicy()
application.run()
```

## Switching at runtime

One method on `AppDelegate`, used by both startup and Settings:

```swift
/// Reconciles the activation policy with the setting.
///
/// The re-activation is not optional. Promoting `.accessory` → `.regular` leaves
/// AppKit without a drawn menu bar until the app becomes active again, and
/// demoting `.regular` → `.accessory` can drop the key window — either way the
/// window the user just clicked in ends up with a keyboard that does nothing.
func applyActivationPolicy() {
    NSApp.setActivationPolicy(composition.settings.showsDockIcon ? .regular : .accessory)
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
}
```

At startup there is no settings window and no user to disturb, so the same call
is correct there.

## Settings UI

A new section in `SettingsView`, above "Shortcuts":

- `Toggle("Show in Dock")` bound to `settings.showsDockIcon`, whose setter also
  calls `delegate.applyActivationPolicy()`.
- A caption: without the Dock icon the app leaves ⌘Tab and the menu bar at the
  top of the screen; the menu bar icon and both hotkeys work either way.
- A "Restart dnotes" button, shown **only after the toggle has been changed in
  this session** (one `Bool` on the delegate). A restart button that is always
  present reads as an admission that the app does not work; one that appears next
  to the switch that might have unsettled the menu bar reads as a remedy.

Restart is `NSWorkspace.openApplication` with
`configuration.createsNewApplicationInstance = true`, followed by
`NSApp.terminate(nil)` in the completion handler — terminating first would leave
nothing to launch the new instance.

## What does not change

- **The capture panel.** It is non-activating because of its style mask, not the
  activation policy. This is the assumption the whole app rests on, so it is
  re-checked manually under both settings rather than assumed.
- **`MainMenu`.** An `.accessory` app does not draw a menu bar, but AppKit still
  dispatches ⌘-key equivalents through `NSApp.mainMenu` for the key window, so
  copy, paste, select-all, undo and `⌘Q` keep working in the notes window and the
  inline editor.
- **The status item, the hotkeys, and `applicationShouldHandleReopen`.** The
  reopen handler is dead code while dockless and correct the moment the Dock icon
  is turned on; it costs nothing to leave alone.

## Testing

Unit (`SettingsStoreTests`):

- `showsDockIcon` defaults to `false` when nothing is stored.
- A stored `true` survives a fresh `SettingsStore` over the same defaults.
- A stored `false` is read as `false` and not confused with absence.

Activation policy is AppKit global state and is not unit-tested. It goes to
`docs/manual-checklist.md`, replacing the "Dock and menus" section written on
2026-07-29:

- Fresh launch with no stored preference: no Dock icon, absent from ⌘Tab, menu
  bar icon present, both hotkeys work.
- Toggling "Show in Dock" on: the icon appears without a relaunch, the app enters
  ⌘Tab, the menu bar at the top of the screen is drawn and usable, and the
  Settings window still takes keystrokes.
- Toggling it back off: the icon disappears, and the Settings window still takes
  keystrokes.
- Clicking the Dock icon with no window open opens the notes list.
- `⌘C`, `⌘V`, `⌘A`, `⌘Z` in the capture field and the inline row editor, and
  `⌘Q`, under **both** settings.
- **The primary scenario under both settings:** `⌥Space` from another app does
  not steal focus, and `⏎` returns it.
- The "Restart dnotes" button appears only after the toggle is touched, and
  relaunches into the chosen mode.

## Documentation

- §7 of the design doc: an amendment dated 2026-07-30 recording that the Dock
  icon became a setting defaulting to off, and that the notch problem the
  2026-07-29 amendment describes is now carried by the hotkeys.
- §11: `LSUIElement` is `true` again, and no longer the whole story.
- `plan/README.md`: the "`LSUIElement` is `false`" note is updated in place rather
  than left to contradict the code.
