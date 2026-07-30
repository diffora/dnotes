import AppKit

// A plain NSApplication rather than a SwiftUI `App` with `MenuBarExtra`: the scene
// version produced no status item at all, and the rest of the shell is already
// AppKit (NSPanel for capture, NSWindow for the list). One pattern beats two, and
// the icon's lifetime becomes something this code owns outright.
//
// The activation policy is a setting now (`SettingsStore.showsDockIcon`, off by
// default), so it is applied here rather than fixed: `Info.plist` only decides how the
// process starts, and the delegate has the stored answer. The delegate is built first
// for exactly that reason — the setting is read through the store, not through a second
// `UserDefaults` lookup that could drift from it.
//
// The capture panel is non-activating either way: that comes from the panel's style
// mask, not from the activation policy.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
delegate.applyActivationPolicy()
application.run()
