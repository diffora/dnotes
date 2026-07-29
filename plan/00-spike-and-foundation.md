# Tasks 0–1: Spike and Foundation

> Part of the [dnotes implementation plan](README.md). Read [README.md](README.md#global-constraints) first — its Global Constraints apply to every task here.

---

### Task 0: Capture panel spike (thrown away)

Design §10 step 0 and §6. This answers the riskiest question in the project — *will a
`.nonactivatingPanel` accept keyboard input while another app stays active?* — before any
architecture is committed to it. The whole thing is deleted in Task 1; do not make it nice.

**Files:**
- Create: `spike/Package.swift`
- Create: `spike/Sources/spike/main.swift`
- Create: `spike/bundle.sh`
- Modify: `2026-07-29-dnotes-design.md` (§6, record the answer)

**Interfaces:**
- Consumes: nothing.
- Produces: one boolean written into the spec — `usesActivationFallback`. Task 14 reads it.

- [ ] **Step 1: Create the spike package**

```bash
mkdir -p spike/Sources/spike && cd spike
cat > Package.swift <<'EOF'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "spike",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "spike")]
)
EOF
```

- [ ] **Step 2: Write the spike**

`spike/Sources/spike/main.swift`:

```swift
import AppKit
import Carbon.HIToolbox

// A borderless panel refuses key status unless this is overridden.
final class SpikePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class Spike: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var panel: SpikePanel!
    var field: NSTextField!
    var hotKeyRef: EventHotKeyRef?
    var previousApp: NSRunningApplication?

    // Flip to true to try the §6 fallback path instead of the primary one.
    let usesActivationFallback = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        installHotKeyHandler()
        registerHotKey()
        NSLog("spike: ready, press ⌥Space")
    }

    func buildPanel() {
        panel = SpikePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 72),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        field = NSTextField(frame: NSRect(x: 20, y: 20, width: 520, height: 32))
        field.font = .systemFont(ofSize: 18)
        field.placeholderString = "type, then ⏎"
        field.delegate = self
        panel.contentView?.addSubview(field)
    }

    func registerHotKey() {
        let id = EventHotKeyID(signature: OSType(0x646E_7473), id: 1) // 'dnts'
        let status = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey), id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        NSLog("spike: RegisterEventHotKey status=\(status)")
    }

    func installHotKeyHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                let spike = Unmanaged<Spike>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async { spike.showPanel() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil
        )
    }

    func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication
        NSLog("spike: hotkey fired, front app was \(previousApp?.localizedName ?? "?")")
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        if usesActivationFallback { NSApp.activate(ignoringOtherApps: true) }
    }

    func hidePanel() {
        panel.orderOut(nil)
        if usesActivationFallback { previousApp?.activate() }
        NSLog("spike: hidden, front app now \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            NSLog("spike: captured %@", field.stringValue)
            field.stringValue = ""
            hidePanel()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hidePanel()
            return true
        default:
            return false
        }
    }
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // equivalent of LSUIElement for a bare binary
app.run()
```

- [ ] **Step 3: Build and run it**

```bash
cd spike && swift build && ./.build/debug/spike
```

Expected in the log: `RegisterEventHotKey status=0`. A non-zero status means the combination is
already taken — quit whatever holds `⌥Space` (Spotlight alternatives, Alfred, input switchers) and
re-run, because the spike answers nothing if the hotkey never fires.

- [ ] **Step 4: Run the four checks that decide the architecture**

With the spike running, leave the terminal and check each of these. Write down pass/fail:

1. From a normal app (e.g. Safari): `⌥Space` → panel appears → **typed characters land in the
   field** → `⏎` → panel closes → the caret is back where it was in Safari.
2. With Zoom (or any app) in **fullscreen**: the panel appears *over* the fullscreen window rather
   than switching Spaces.
3. With a **fullscreen terminal**: same, and typing still reaches the field.
4. `esc` closes the panel and focus stays with the originating app.

If check 1 fails — the panel appears but keystrokes go to the other app — set
`usesActivationFallback = true`, rebuild, and repeat all four. That is the §6 fallback path.

- [ ] **Step 5: Record the answer in the spec**

Edit `2026-07-29-dnotes-design.md` §6 and replace the "Fallback if the non-activating panel will
not hold keyboard input" bullet's last sentence ("The choice between the primary path and the
fallback is made by the spike in §10, before task 1.") with the actual result, in this form:

```markdown
- **Spike result (2026-07-XX):** the primary non-activating path holds keyboard input in all four
  §9.3 scenarios — `usesActivationFallback = false`. [or: the primary path does not hold keyboard
  input when <describe exactly what failed>; the app uses the activation fallback —
  `usesActivationFallback = true`.]
```

This sentence is the only output of the task that survives it.

- [ ] **Step 6: Commit the spec change**

The spike code is *not* committed — there is no repository yet, and Task 1 deletes it. Only the
spec edit is committed, and only after Task 1 has created the repository. Note the change and move
on; Task 1 step 8 commits it.

---

### Task 1: Git repository, SwiftPM package, working test harness

The deliverable is a repository where `./scripts/test.sh` runs one real test and prints a pass.
Everything after this task assumes that command works.

**Files:**
- Create: `.gitignore`, `Package.swift`, `scripts/test.sh`
- Create: `Sources/DnotesCore/DnotesCore.swift`, `Sources/Dnotes/main.swift`
- Test: `Tests/DnotesCoreTests/HarnessTests.swift`
- Delete: `spike/`
- Modify: `../.gitignore` (the surrounding `diffora` repo)

**Interfaces:**
- Consumes: nothing.
- Produces: the module names `DnotesCore` (library) and `Dnotes` (executable), and the command
  `./scripts/test.sh`, which every later task's test steps invoke.

- [ ] **Step 1: Detach `dnotes/` from the surrounding repo and initialise its own**

`~/Projects/diffora` is a git repository that currently tracks `dnotes/`. dnotes becomes its own
repository, so the parent stops tracking it. This removes nothing from disk — `--cached` only
touches the index.

```bash
cd ~/Projects/diffora
git rm -r --cached dnotes --quiet
printf 'dnotes/\n' >> .gitignore
cd ~/Projects/diffora/dnotes
git init
```

The parent repo is left with staged changes and **is not committed here** — that is the owner's
call. Everything below happens inside `~/Projects/diffora/dnotes`.

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.build/
.swiftpm/
*.app/
.DS_Store
```

Note what is deliberately *not* ignored: `notes.md` and the `YYYY-MM.md` files. The notes are the
point of putting this folder under version control.

- [ ] **Step 3: Write `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "dnotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "dnotes", targets: ["Dnotes"]),
        .library(name: "DnotesCore", targets: ["DnotesCore"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "DnotesCore"),
        .executableTarget(name: "Dnotes", dependencies: ["DnotesCore"]),
        .testTarget(name: "DnotesCoreTests", dependencies: ["DnotesCore"]),
    ]
)
```

The framework search path for swift-testing is deliberately **not** here — see step 4.

- [ ] **Step 4: Write `scripts/test.sh`**

Command Line Tools ship `Testing.framework`, but SwiftPM does not add the search path on its own
(that is Xcode's job, and Xcode is not installed — §11). Putting the flags in `Package.swift` as
`unsafeFlags` builds fine and then runs **zero tests silently**, which is worse than failing. A
wrapper script is the supported path.

```bash
#!/bin/sh
# Runs the test suite. Full Xcode is not installed, so swift-testing has to be
# pointed at the copy that ships with Command Line Tools — see plan/README.md.
set -eu

cd "$(dirname "$0")/.."

FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
    echo "Testing.framework not found in $FRAMEWORKS" >&2
    echo "Check 'xcode-select -p'." >&2
    exit 1
fi

# -disable-cross-import-overlays: CLT ships _Testing_Foundation.framework without
# its .swiftmodule, so the Testing+Foundation cross-import overlay cannot be built.
# Disabling it costs nothing — the overlay only adds Foundation conveniences.
exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$@"
```

```bash
chmod +x scripts/test.sh
```

- [ ] **Step 5: Write the failing harness test**

`Tests/DnotesCoreTests/HarnessTests.swift`:

```swift
import Testing
@testable import DnotesCore

@Test func harnessRunsAgainstTheLibrary() {
    #expect(DnotesCore.version == "0.1.0")
}
```

- [ ] **Step 6: Run it and watch it fail**

Run: `./scripts/test.sh`
Expected: FAIL, `cannot find 'DnotesCore' in scope` — the enum does not exist yet.

- [ ] **Step 7: Write the minimum to make it pass**

`Sources/DnotesCore/DnotesCore.swift`:

```swift
/// Namespace for library-wide constants.
public enum DnotesCore {
    public static let version = "0.1.0"
}
```

`Sources/Dnotes/main.swift` — a placeholder so the executable target links; Task 12 replaces it:

```swift
import DnotesCore

print("dnotes \(DnotesCore.version)")
```

Run: `./scripts/test.sh`
Expected: PASS — `Test run with 1 test in 0 suites passed`.

- [ ] **Step 8: Delete the spike and commit**

```bash
rm -rf spike
git add -A
git commit -m "chore: swiftpm package, git repo and swift-testing harness

Command Line Tools only (no Xcode), so tests run through scripts/test.sh,
which points swift-testing at the framework CLT ships. Records the capture
panel spike result in the design doc."
```

Verify the spike is gone and the tree is clean: `git status --short` prints nothing.
