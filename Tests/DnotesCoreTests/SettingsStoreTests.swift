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

// MARK: - Dock icon

@MainActor
@Test func theDockIconIsOffUntilSomebodyAsksForIt() {
    #expect(SettingsStore(defaults: makeTestDefaults()).showsDockIcon == false)
}

@MainActor
@Test func theDockIconChoiceSurvivesARestartInBothDirections() {
    let defaults = makeTestDefaults()

    SettingsStore(defaults: defaults).showsDockIcon = true
    #expect(SettingsStore(defaults: defaults).showsDockIcon == true)

    SettingsStore(defaults: defaults).showsDockIcon = false
    #expect(SettingsStore(defaults: defaults).showsDockIcon == false)
}

// MARK: - tag layout

@MainActor
@Test func tagLayoutDefaultsToTrailingAndIsRemembered() {
    let defaults = UserDefaults(suiteName: "dnotes.tests.\(UUID().uuidString)")!
    #expect(SettingsStore(defaults: defaults).tagLayout == .trailing)

    SettingsStore(defaults: defaults).tagLayout = .inline
    #expect(SettingsStore(defaults: defaults).tagLayout == .inline)
}

/// A value written by another build, or edited by hand, must not leave the list in a
/// layout that does not exist.
@MainActor
@Test func anUnknownStoredTagLayoutFallsBackToTheDefault() {
    let defaults = UserDefaults(suiteName: "dnotes.tests.\(UUID().uuidString)")!
    defaults.set("sideways", forKey: "dnotes.tagLayout")
    #expect(SettingsStore(defaults: defaults).tagLayout == .trailing)
}
