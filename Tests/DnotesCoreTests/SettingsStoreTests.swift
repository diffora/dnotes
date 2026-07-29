import Foundation
import Testing
@testable import DnotesCore

@Test @MainActor func defaultsMatchTheSpec() {
    let settings = SettingsStore(defaults: makeTestDefaults())

    #expect(settings.folderURL.path.hasSuffix("Projects/diffora/dnotes"))
    #expect(settings.captureHotKey == .captureDefault)
    #expect(settings.mainWindowHotKey == .mainWindowDefault)
    #expect(settings.panelDraft.isEmpty)
    #expect(settings.completionFilter == .completedToday)
}

@Test @MainActor func settingsSurviveARestart() {
    let defaults = makeTestDefaults()
    let first = SettingsStore(defaults: defaults)
    first.folderURL = URL(fileURLWithPath: "/tmp/notes")
    first.panelDraft = "half a thought"
    first.completionFilter = .openOnly
    first.captureHotKey = HotKeyCombo(keyCode: 49, modifiers: HotKeyCombo.command)

    let second = SettingsStore(defaults: defaults)
    #expect(second.folderURL.path == "/tmp/notes")
    #expect(second.panelDraft == "half a thought")
    #expect(second.completionFilter == .openOnly)
    #expect(second.captureHotKey == HotKeyCombo(keyCode: 49, modifiers: HotKeyCombo.command))
}

@Test @MainActor func theOldShowsCompletedBooleanStillMeansSomething() {
    // Someone upgrading had already expressed a preference; losing it silently would
    // be a small betrayal for no gain.
    let defaults = makeTestDefaults()
    defaults.set(true, forKey: "dnotes.showsCompleted")

    #expect(SettingsStore(defaults: defaults).completionFilter == .all)
}

@Test func hotKeyCombosRenderTheWayMenusDo() {
    #expect(HotKeyCombo.captureDefault.displayString == "⌥Space")
    #expect(HotKeyCombo.mainWindowDefault.displayString == "⌥⇧Space")
    #expect(HotKeyCombo(keyCode: 0, modifiers: HotKeyCombo.command).displayString == "⌘A")
}
