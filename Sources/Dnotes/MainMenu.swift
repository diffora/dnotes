import AppKit

/// The application's main menu.
///
/// Not decoration: macOS dispatches `⌘`-key equivalents through the main menu
/// *before* offering them to windows, so without an Edit menu the capture field has
/// no copy, paste, select-all or undo, and there is no `⌘Q`. An app whose whole
/// purpose is typing text cannot be missing those.
///
/// The items use standard AppKit selectors with a `nil` target, which sends them down
/// the responder chain to whatever text field is focused — that is what makes them
/// work in the capture panel, the inline row editor and the search field alike,
/// without any of them knowing about this menu.
enum MainMenu {
    static func install(delegate: AppDelegate) {
        let main = NSMenu()
        main.addItem(appMenuItem(delegate: delegate))
        main.addItem(editMenuItem())
        main.addItem(windowMenuItem())
        NSApp.mainMenu = main
    }

    private static func appMenuItem(delegate: AppDelegate) -> NSMenuItem {
        let menu = NSMenu()

        add(to: menu, "Capture…", #selector(AppDelegate.toggleCapturePanel), target: delegate)
        add(to: menu, "Notes…", #selector(AppDelegate.showMainWindow), target: delegate, key: "l")
        menu.addItem(.separator())
        add(to: menu, "Settings…", #selector(AppDelegate.showSettings), target: delegate, key: ",")
        menu.addItem(.separator())
        add(to: menu, "Hide dnotes", #selector(NSApplication.hide(_:)), key: "h")
        add(to: menu, "Quit dnotes", #selector(NSApplication.terminate(_:)), key: "q")

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")

        add(to: menu, "Undo", Selector(("undo:")), key: "z")
        add(to: menu, "Redo", Selector(("redo:")), key: "Z")
        menu.addItem(.separator())
        add(to: menu, "Cut", #selector(NSText.cut(_:)), key: "x")
        add(to: menu, "Copy", #selector(NSText.copy(_:)), key: "c")
        add(to: menu, "Paste", #selector(NSText.paste(_:)), key: "v")
        add(to: menu, "Select All", #selector(NSText.selectAll(_:)), key: "a")

        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        add(to: menu, "Close", #selector(NSWindow.performClose(_:)), key: "w")
        add(to: menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")

        let item = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// A `nil` target means "walk the responder chain", which is what the Edit items
    /// need. The app items name the delegate explicitly, because it is not in the
    /// chain.
    private static func add(to menu: NSMenu,
                            _ title: String,
                            _ action: Selector,
                            target: AnyObject? = nil,
                            key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        // An uppercase key equivalent implies shift, which is how ⇧⌘Z is expressed.
        if key == key.uppercased(), key.count == 1, key.rangeOfCharacter(from: .letters) != nil {
            item.keyEquivalentModifierMask = [.command, .shift]
        }
        item.target = target
        menu.addItem(item)
    }
}
