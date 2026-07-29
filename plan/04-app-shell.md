# Tasks 13–14: App shell and the global hotkey

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

Design §10 steps 4 and 5. From here on the code is AppKit and SwiftUI, so the tests thin out and
the manual checks of §9.3 start carrying weight. What *can* be tested without a window still is:
`SettingsStore` and `HotKeyCombo` are plain value logic and get real tests.

---

### Task 13: App skeleton, composition root, `.app` bundle

**Files:**
- Create: `Sources/Dnotes/DnotesApp.swift`, `Sources/Dnotes/Composition.swift`,
  `Sources/Dnotes/SettingsStore.swift`, `Sources/Dnotes/HotKeyCombo.swift`,
  `Sources/Dnotes/SettingsView.swift`
- Create: `scripts/bundle.sh`, `Resources/Info.plist`
- Delete: `Sources/Dnotes/main.swift` (a SwiftUI `@main` type and a `main.swift` cannot coexist)
- Test: `Tests/DnotesCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `NotesModel`, `PendingQueue`, `MarkdownNotesRepository`.
- Produces: `SettingsStore`, `HotKeyCombo`, `Composition`, and a launchable `dnotes.app`.
  `HotKeyCombo` lands here rather than with `HotKeyManager` because `SettingsStore` persists it.

**`Composition` is the only file in the project that names `MarkdownNotesRepository.`** Everything
else takes `any NotesRepository`. Swapping the backend is an edit to this one file.

- [ ] **Step 1: Write the failing settings tests**

`Tests/DnotesCoreTests/SettingsStoreTests.swift` — note this test target only links `DnotesCore`,
so put `SettingsStore` and `HotKeyCombo` in `DnotesCore`, not in the executable target. The
executable keeps only what needs AppKit.

```swift
import Foundation
import Testing
@testable import DnotesCore

@MainActor
private func freshDefaults() -> UserDefaults {
    let suite = "dnotes.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test @MainActor func defaultsMatchTheSpec() {
    let settings = SettingsStore(defaults: freshDefaults())

    #expect(settings.folderURL.path.hasSuffix("Projects/diffora/dnotes"))
    #expect(settings.captureHotKey == .captureDefault)
    #expect(settings.mainWindowHotKey == .mainWindowDefault)
    #expect(settings.panelDraft.isEmpty)
    #expect(settings.showsCompleted == false)
}

@Test @MainActor func settingsSurviveARestart() {
    let defaults = freshDefaults()
    let first = SettingsStore(defaults: defaults)
    first.folderURL = URL(fileURLWithPath: "/tmp/notes")
    first.panelDraft = "half a thought"
    first.showsCompleted = true
    first.captureHotKey = HotKeyCombo(keyCode: 49, modifiers: HotKeyCombo.command)

    let second = SettingsStore(defaults: defaults)
    #expect(second.folderURL.path == "/tmp/notes")
    #expect(second.panelDraft == "half a thought")
    #expect(second.showsCompleted)
    #expect(second.captureHotKey == HotKeyCombo(keyCode: 49, modifiers: HotKeyCombo.command))
}

@Test func hotKeyCombosRenderTheWayMenusDo() {
    #expect(HotKeyCombo.captureDefault.displayString == "⌥Space")
    #expect(HotKeyCombo.mainWindowDefault.displayString == "⌥⇧Space")
    #expect(HotKeyCombo(keyCode: 0, modifiers: HotKeyCombo.command).displayString == "⌘A")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./scripts/test.sh --filter SettingsStore`
Expected: FAIL, `cannot find 'SettingsStore' in scope`.

- [ ] **Step 3: Implement `HotKeyCombo`**

`Sources/DnotesCore/HotKeyCombo.swift`:

```swift
import Foundation

/// A global hotkey as Carbon wants it: a virtual key code and a modifier mask.
/// Carbon's constants are hard-coded rather than imported so this type stays in
/// `DnotesCore`, where it can be tested without AppKit.
public struct HotKeyCombo: Codable, Equatable, Sendable {
    public static let command: UInt32 = 1 << 8   // cmdKey
    public static let shift: UInt32 = 1 << 9     // shiftKey
    public static let option: UInt32 = 1 << 11   // optionKey
    public static let control: UInt32 = 1 << 12  // controlKey

    public static let spaceKeyCode: UInt32 = 49  // kVK_Space

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let captureDefault = HotKeyCombo(keyCode: spaceKeyCode, modifiers: option)
    public static let mainWindowDefault = HotKeyCombo(keyCode: spaceKeyCode,
                                                      modifiers: option | shift)

    /// Modifier order follows the menu-bar convention: ⌃⌥⇧⌘.
    public var displayString: String {
        var out = ""
        if modifiers & Self.control != 0 { out += "⌃" }
        if modifiers & Self.option != 0 { out += "⌥" }
        if modifiers & Self.shift != 0 { out += "⇧" }
        if modifiers & Self.command != 0 { out += "⌘" }
        return out + Self.keyName(keyCode)
    }

    static func keyName(_ keyCode: UInt32) -> String {
        if let named = namedKeys[keyCode] { return named }
        return letterKeys[keyCode] ?? "key \(keyCode)"
    }

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape",
    ]

    private static let letterKeys: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    ]
}
```

- [ ] **Step 4: Implement `SettingsStore`**

`Sources/DnotesCore/SettingsStore.swift`:

```swift
import Foundation
import Observation

/// Everything the app remembers between launches, except the pending queue.
/// The app is not sandboxed (§11), so a folder is a plain path — no bookmarks.
@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folderURL = Self.readFolder(defaults)
        captureHotKey = Self.readCombo(defaults, "dnotes.captureHotKey") ?? .captureDefault
        mainWindowHotKey = Self.readCombo(defaults, "dnotes.mainWindowHotKey") ?? .mainWindowDefault
        panelDraft = defaults.string(forKey: "dnotes.panelDraft") ?? ""
        showsCompleted = defaults.bool(forKey: "dnotes.showsCompleted")
    }

    public var folderURL: URL {
        didSet { defaults.set(folderURL.path, forKey: "dnotes.folderPath") }
    }

    public var captureHotKey: HotKeyCombo {
        didSet { write(captureHotKey, "dnotes.captureHotKey") }
    }

    public var mainWindowHotKey: HotKeyCombo {
        didSet { write(mainWindowHotKey, "dnotes.mainWindowHotKey") }
    }

    /// One line, typed but not confirmed. Exactly one slot, which is all that is
    /// needed: there is only one panel (§8).
    public var panelDraft: String {
        didSet { defaults.set(panelDraft, forKey: "dnotes.panelDraft") }
    }

    public var showsCompleted: Bool {
        didSet { defaults.set(showsCompleted, forKey: "dnotes.showsCompleted") }
    }

    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/diffora/dnotes")
    }

    private func write(_ combo: HotKeyCombo, _ key: String) {
        defaults.set(try? JSONEncoder().encode(combo), forKey: key)
    }

    private static func readFolder(_ defaults: UserDefaults) -> URL {
        guard let path = defaults.string(forKey: "dnotes.folderPath"), !path.isEmpty else {
            return defaultFolder
        }
        return URL(fileURLWithPath: path)
    }

    private static func readCombo(_ defaults: UserDefaults, _ key: String) -> HotKeyCombo? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyCombo.self, from: data)
    }
}
```

- [ ] **Step 5: Run the settings tests**

Run: `./scripts/test.sh --filter SettingsStore`
Expected: PASS.

- [ ] **Step 6: Write the composition root**

`Sources/Dnotes/Composition.swift`:

```swift
import AppKit
import DnotesCore

/// The only place in the app that names a concrete backend. Everything else takes
/// `any NotesRepository`, so replacing markdown files with something else is an edit
/// to this file.
@MainActor
final class Composition {
    let settings: SettingsStore
    let pending: PendingQueue
    let repository: MarkdownNotesRepository
    let model: NotesModel

    init(defaults: UserDefaults = .standard) {
        settings = SettingsStore(defaults: defaults)
        pending = PendingQueue(defaults: defaults)
        repository = MarkdownNotesRepository(folder: settings.folderURL)
        model = NotesModel(repository: repository, pending: pending)
        model.showsCompleted = settings.showsCompleted
    }

    func start() async {
        await model.load()
        repository.startObserving()
    }

    func changeFolder(to url: URL) async {
        settings.folderURL = url
        try? await repository.setFolder(url)
        await model.load()
    }
}
```

- [ ] **Step 7: Write the app entry point and settings screen**

`Sources/Dnotes/DnotesApp.swift`:

```swift
import SwiftUI
import DnotesCore

@main
struct DnotesApp: App {
    @State private var composition = Composition()

    var body: some Scene {
        MenuBarExtra("dnotes", systemImage: "square.and.pencil") {
            Button("Capture…") { /* wired in Task 15 */ }
                .keyboardShortcut(.space, modifiers: .option)
            Button("Notes…") { /* wired in Task 17 */ }
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit dnotes") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }

        Settings {
            SettingsView(composition: composition)
        }
    }

    init() {
        // LSUIElement is set in Info.plist, but a binary run straight out of
        // .build has no bundle, and this keeps the two paths behaving alike.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
```

`Sources/Dnotes/SettingsView.swift`:

```swift
import SwiftUI
import DnotesCore

struct SettingsView: View {
    let composition: Composition
    @State private var folderError: String?

    var body: some View {
        Form {
            Section("Notes folder") {
                HStack {
                    Text(composition.settings.folderURL.path)
                        .font(.callout)
                        .truncationMode(.head)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }
                if let folderError {
                    Text(folderError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = composition.settings.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await composition.changeFolder(to: url)
            folderError = composition.model.storeAvailable ? nil : composition.model.lastError
        }
    }
}
```

Delete `Sources/Dnotes/main.swift` — `@main` and `main.swift` cannot coexist in one target.

- [ ] **Step 8: Write the bundle script**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>dnotes</string>
    <key>CFBundleDisplayName</key>     <string>dnotes</string>
    <key>CFBundleIdentifier</key>      <string>com.diffora.dnotes</string>
    <key>CFBundleExecutable</key>      <string>dnotes</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <!-- Menu bar app: no Dock icon, never becomes active on its own (§7, §11). -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
```

`scripts/bundle.sh`:

```bash
#!/bin/sh
# Assembles dnotes.app from the SwiftPM binary. Signing and notarization are out of
# scope (design §11) — this is a personal build.
set -eu

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-release}"

swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/dnotes"

APP="dnotes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/dnotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "built $APP"
echo "run it with: open $APP"
```

```bash
chmod +x scripts/bundle.sh
```

- [ ] **Step 9: Build the bundle and check it launches**

```bash
./scripts/bundle.sh && open dnotes.app
```

Expected: a menu-bar icon appears, **no Dock icon and no window**. The menu opens, "Settings…"
shows the folder picker, "Quit dnotes" quits. If a Dock icon appears, `LSUIElement` did not take —
check that `Info.plist` landed at `dnotes.app/Contents/Info.plist`.

- [ ] **Step 10: Commit**

```bash
git add Sources Resources scripts Tests Package.swift
git commit -m "feat: app shell — menu bar, settings, composition root, bundle script

Composition is the one file that names MarkdownNotesRepository; everything
else takes any NotesRepository, so a backend swap is a one-file edit."
```

---

### Task 14: `HotKeyManager` and hotkey conflict reporting

**Files:**
- Create: `Sources/Dnotes/HotKeyManager.swift`
- Modify: `Sources/Dnotes/SettingsView.swift` (hotkey rows and the conflict message)
- Modify: `Sources/Dnotes/DnotesApp.swift` (register on launch via an app delegate)

**Interfaces:**
- Consumes: `HotKeyCombo` (Task 13).
- Produces:
  ```swift
  enum HotKeyError: Error, Equatable { case registrationFailed(OSStatus) }
  @MainActor final class HotKeyManager {
      func register(_ combo: HotKeyCombo, id: UInt32, handler: @escaping @MainActor () -> Void) throws
      func unregister(id: UInt32)
  }
  ```
  Task 15 registers the capture hotkey against it; Task 17 registers the main-window one.

**A silently dead hotkey is unacceptable** (§6): you would find out about the conflict at the exact
moment the thought is already lost. `RegisterEventHotKey` returns non-`noErr` when the combination
is taken, and that goes straight into the settings screen next to the field.

`RegisterEventHotKey` needs **no Accessibility permission** (§11) — there is no prompt on first
launch, and none should be added.

- [ ] **Step 1: Implement the manager**

`Sources/Dnotes/HotKeyManager.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import DnotesCore

enum HotKeyError: Error, Equatable {
    case registrationFailed(OSStatus)
}

/// One Carbon event handler for the whole app, plus a table of registrations.
@MainActor
final class HotKeyManager {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    static let signature = OSType(0x646E_7473)   // 'dnts'

    func register(_ combo: HotKeyCombo,
                  id: UInt32,
                  handler: @escaping @MainActor () -> Void) throws {
        installEventHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { throw HotKeyError.registrationFailed(status) }
        refs[id] = ref
        handlers[id] = handler
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers[id] = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let pressed = id.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { manager.handlers[pressed]?() }
                }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
    }
}

enum HotKeyID {
    static let capture: UInt32 = 1
    static let mainWindow: UInt32 = 2
}
```

- [ ] **Step 2: Register on launch and surface failures**

Add an app delegate to `Sources/Dnotes/DnotesApp.swift`:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let composition = Composition()
    let hotKeys = HotKeyManager()
    /// Non-nil when the combination is already taken; shown in Settings.
    var captureHotKeyError: String?
    var mainWindowHotKeyError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await composition.start() }
        registerHotKeys()
    }

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
            // Say so out loud rather than leaving a dead key (§6).
            return "\(combo.displayString) is in use by another app — pick another combination."
        }
    }

    func toggleCapturePanel() { /* Task 15 */ }
    func showMainWindow() { /* Task 17 */ }
}
```

and adopt it in the `App`:

```swift
@main
struct DnotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    ...
}
```

- [ ] **Step 3: Show the conflict in Settings**

Add to `SettingsView`'s `Form`:

```swift
            Section("Shortcuts") {
                LabeledContent("Capture") {
                    Text(composition.settings.captureHotKey.displayString)
                        .monospaced()
                }
                if let error = delegate.captureHotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Notes window") {
                    Text(composition.settings.mainWindowHotKey.displayString)
                        .monospaced()
                }
                if let error = delegate.mainWindowHotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
```

Editing a combination is deliberately not built here: the two defaults work, and a recorder control
is a task of its own. What matters for §6 is that a *taken* combination says so.

- [ ] **Step 4: Check it by hand**

```bash
./scripts/bundle.sh && open dnotes.app
```

1. Console shows no hotkey error and Settings shows no red text.
2. Now occupy `⌥Space` in System Settings → Keyboard → Shortcuts (or any launcher), relaunch, and
   confirm Settings shows the conflict message rather than staying silent. Undo afterwards.
3. Nothing prompts for Accessibility permission at any point.

- [ ] **Step 5: Commit**

```bash
git add Sources/Dnotes
git commit -m "feat: global hotkey registration with conflict reporting

RegisterEventHotKey needs no Accessibility permission; a taken combination
is surfaced in Settings instead of leaving a silently dead key (§6)."
```
