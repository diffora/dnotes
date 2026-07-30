import AppKit
import SwiftUI
import DnotesCore

/// A borderless panel refuses key status unless this is overridden, which would
/// leave the field unable to receive a single keystroke.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Command shortcuts the panel answers itself. An `LSUIElement` app has no menu
    /// bar for the system to register shortcuts against, and these two are the app's
    /// only guaranteed way in when the menu bar item is not visible — so they are
    /// handled here, at the AppKit level, rather than hoping a SwiftUI
    /// `keyboardShortcut` gets delivered. Return true when handled.
    var onCommandShortcut: ((Character) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           let character = event.charactersIgnoringModifiers?.first,
           onCommandShortcut?(character) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Reports when its SwiftUI content wants a different size.
///
/// `sizingOptions = [.intrinsicContentSize]` only makes a hosting view *state* its size;
/// nothing resizes the window for it. Left alone, the panel keeps the height it was
/// built with, SwiftUI lays a taller list out inside it anyway, and the overflow is
/// drawn straight over the text field. This hook is how the window hears about it.
final class ContentSizedHostingView<Content: View>: NSHostingView<Content> {
    var onContentSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onContentSizeChange?()
    }
}

@MainActor
final class CapturePanel {
    /// The §6 fallback switch. `false` is the primary non-activating path; `true`
    /// activates the app and restores the previous one on close, which looks the
    /// same from outside at the cost of an activation cycle. Flip it if the panel
    /// turns out not to hold keyboard input on this system.
    static let usesActivationFallback = false

    private let model: NotesModel
    private let settings: SettingsStore
    private let onOpenSettings: () -> Void
    private let onOpenNotes: () -> Void
    private let panel: KeyablePanel
    private var previousApp: NSRunningApplication?

    /// What is in the field right now, mirrored up from the view so that *every* way
    /// of closing the panel can preserve it as a draft — not just `esc` (§8).
    private var currentText = ""

    init(model: NotesModel,
         settings: SettingsStore,
         onOpenSettings: @escaping () -> Void,
         onOpenNotes: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onOpenNotes = onOpenNotes

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 120),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let hosting = ContentSizedHostingView(rootView: CaptureView(
            model: model,
            settings: settings,
            onSubmit: { [weak self] text, keepOpen in self?.submit(text, keepOpen: keepOpen) },
            onCancel: { [weak self] draft in self?.cancel(keepingDraft: draft) },
            onTextChanged: { [weak self] text in self?.currentText = text }
        ))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        // Deferred by a turn of the run loop: during the invalidation itself the hosting
        // view still reports the size it is about to stop having.
        hosting.onContentSizeChange = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fitToContent() } }
        }

        panel.onCommandShortcut = { [weak self] character in
            guard let self else { return false }
            switch character {
            case ",":
                self.leave(for: self.onOpenSettings)
                return true
            case "l":
                self.leave(for: self.onOpenNotes)
                return true
            default:
                return false
            }
        }
    }

    /// Closing the panel to open a window: keep what was typed and get out of the
    /// way, or the new window appears underneath a floating panel.
    private func leave(for destination: () -> Void) {
        hide()
        destination()
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
        // Every exit preserves the field, not only `esc`: toggling the hotkey a second
        // time with something half-typed used to drop it, and unconfirmed text is
        // still text (§8).
        settings.panelDraft = currentText
        panel.orderOut(nil)
        // Focus goes back where it came from — that is the whole point (§6).
        if Self.usesActivationFallback { previousApp?.activate() }
        previousApp = nil
    }

    private func submit(_ text: String, keepOpen: Bool) {
        // Cleared before `hide()` reads it, so a saved entry does not come back as a
        // draft on the next open.
        currentText = ""
        settings.panelDraft = ""
        Task { await model.add(text) }
        if !keepOpen { hide() }
    }

    private func cancel(keepingDraft draft: String) {
        currentText = draft
        hide()
    }

    /// Grows and shrinks the panel with its content, holding the **top** edge still.
    ///
    /// The top edge is the whole point: the text field sits against it, and a field that
    /// slid down the screen every time a suggestion appeared would move out from under
    /// the eye that is reading it. The list is what grows, downward, the way a menu does.
    private func fitToContent() {
        guard let hosting = panel.contentView else { return }
        let height = hosting.fittingSize.height
        // The guard is also what stops a resize from feeding itself: laying out at the
        // new size invalidates the size again, and the second pass has nothing to do.
        guard height > 0, abs(panel.frame.height - height) > 0.5 else { return }

        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: panel.frame.width, height: height))
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    /// A capture panel belongs where a Spotlight window would be, not dead centre.
    private func positionNearTopOfScreen() {
        guard let screen = NSScreen.main else { panel.center(); return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - visible.height * 0.22
        ))
    }
}
