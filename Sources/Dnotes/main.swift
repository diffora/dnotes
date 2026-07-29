import AppKit

// A plain NSApplication rather than a SwiftUI `App` with `MenuBarExtra`: the scene
// version produced no status item at all, and the rest of the shell is already
// AppKit (NSPanel for capture, NSWindow for the list). One pattern beats two, and
// the icon's lifetime becomes something this code owns outright.
//
// `.regular`, not `.accessory`: the app keeps a Dock icon and appears in ⌘Tab, which
// is the owner's call after a full menu bar turned out to hide the status item (§7 is
// amended in the design doc). The capture panel stays non-activating regardless —
// that behaviour comes from the panel's style mask, not from the activation policy.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
