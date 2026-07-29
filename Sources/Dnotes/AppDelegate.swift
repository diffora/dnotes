import AppKit
import SwiftUI
import DnotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let composition = Composition()
    let hotKeys = HotKeyManager()

    /// Non-nil when the combination is already taken; shown in Settings. A silently
    /// dead hotkey is unacceptable — you would find out at the exact moment the
    /// thought is already lost (§6).
    private(set) var captureHotKeyError: String?
    private(set) var mainWindowHotKeyError: String?

    private var statusItem: NSStatusItem?
    private var capturePanel: CapturePanel?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private lazy var list = NotesListModel(notes: composition.model)
    private var listKeys: ListKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install(delegate: self)
        installStatusItem()
        Task { await composition.start() }
        registerHotKeys()
    }

    // MARK: - menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = MenuBarIcon.makeImage()
        item.button?.toolTip = "dnotes — ⌥Space to capture"

        let menu = NSMenu()
        add(to: menu, title: "Capture…", action: #selector(toggleCapturePanel))
        add(to: menu, title: "Notes…", action: #selector(showMainWindow))
        menu.addItem(.separator())
        add(to: menu, title: "Settings…", action: #selector(showSettings))
        menu.addItem(.separator())
        add(to: menu, title: "Quit dnotes", action: #selector(quitFromMenu), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    /// The delegate is not in the responder chain, so every item needs an explicit
    /// target or the menu comes up greyed out.
    private func add(to menu: NSMenu, title: String, action: Selector, keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
    }

    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    /// Clicking the Dock icon of an app with no open window has to do something, or
    /// the icon looks broken. The list is the reasonable answer.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showMainWindow() }
        return true
    }

    // MARK: - hotkeys

    func registerHotKeys() {
        captureHotKeyError = register(composition.settings.captureHotKey,
                                      id: HotKeyID.capture) { [weak self] in
            self?.toggleCapturePanel()
        }
        mainWindowHotKeyError = register(composition.settings.mainWindowHotKey,
                                         id: HotKeyID.mainWindow) { [weak self] in
            self?.showMainWindow()
        }
    }

    private func register(_ combo: HotKeyCombo,
                          id: UInt32,
                          handler: @escaping @MainActor () -> Void) -> String? {
        do {
            try hotKeys.register(combo, id: id, handler: handler)
            return nil
        } catch {
            return "\(combo.displayString) is in use by another app — pick another combination."
        }
    }

    // MARK: - windows

    @objc func toggleCapturePanel() {
        if capturePanel == nil {
            capturePanel = CapturePanel(
                model: composition.model,
                settings: composition.settings,
                onOpenSettings: { [weak self] in self?.showSettings() },
                onOpenNotes: { [weak self] in self?.showMainWindow() }
            )
        }
        capturePanel?.toggle()
    }

    @objc func showMainWindow() {
        // The hotkey fires while another app is frontmost, so the window would
        // otherwise come up behind it with a keyboard that does nothing (§7). Still
        // needed now that the app is `.regular`: having a Dock icon does not make an
        // inactive app active.
        NSApp.activate(ignoringOtherApps: true)

        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = makeWindow(title: "Notes", width: 640, height: 520)
        window.contentView = NSHostingView(rootView: MainWindowView(
            model: composition.model,
            list: list,
            settings: composition.settings,
            onChooseFolder: { [weak self] in self?.chooseFolder() }
        ))
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
        // Arrow keys, space, e and delete are taken before the scroll view can treat
        // the arrows as scrolling.
        listKeys = ListKeyMonitor(window: window, list: list)
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = makeWindow(title: "dnotes Settings", width: 500, height: 420)
        window.styleMask.remove(.resizable)
        window.contentView = NSHostingView(rootView: SettingsView(delegate: self))
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    private func makeWindow(title: String, width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = composition.settings.folderURL
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await composition.changeFolder(to: url) }
    }
}
