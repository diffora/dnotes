import SwiftUI
import DnotesCore

struct SettingsView: View {
    let delegate: AppDelegate

    /// Lives here rather than on the delegate: the delegate is not observable, and the
    /// scope wanted is exactly this window's lifetime — the restart offer belongs to the
    /// switch that was just flipped, not to the app forever after.
    @State private var dockIconWasSwitched = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show in Dock", isOn: Binding(
                    get: { delegate.composition.settings.showsDockIcon },
                    set: { shows in
                        delegate.composition.settings.showsDockIcon = shows
                        delegate.applyActivationPolicy()
                        dockIconWasSwitched = true
                    }))
                Text("Without the Dock icon dnotes also leaves ⌘Tab and the menu bar at "
                     + "the top of the screen. The menu bar icon, \(captureKey) and "
                     + "\(notesKey) work either way — with the Dock icon off they are "
                     + "the way in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if dockIconWasSwitched {
                    HStack {
                        Text("The menu bar can take a relaunch to settle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart dnotes") { delegate.restart() }
                    }
                }
            }

            Section("Notes folder") {
                HStack {
                    Text(delegate.composition.settings.folderURL.path)
                        .font(.callout)
                        .truncationMode(.head)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") { delegate.chooseFolder() }
                }
            }

            Section("Issue links") {
                TextField("https://jira.example.com/browse/{key}",
                          text: Binding(get: { delegate.composition.settings.issueURLTemplate },
                                        set: { delegate.composition.settings.issueURLTemplate = $0 }))
                Text("Keys like ABC-1234 become links. \(EntryLinks.issueKeyPlaceholder) is "
                     + "replaced with the key; leave this empty to keep them as plain text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tags") {
                Picker("Show tags", selection: Binding(
                    get: { delegate.composition.settings.tagLayout },
                    set: { delegate.composition.settings.tagLayout = $0 })) {
                    ForEach(TagLayout.allCases, id: \.self) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                Text("Either way the line in the file is unchanged — a tag is part of the "
                     + "text. At the end of the row the text reads without its tags, but "
                     + "editing opens the stored line, tags included. Right-click a tag "
                     + "chip above the list to pick its colour by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                LabeledContent("Capture") {
                    Text(delegate.composition.settings.captureHotKey.displayString).monospaced()
                }
                if let error = delegate.captureHotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Notes window") {
                    Text(delegate.composition.settings.mainWindowHotKey.displayString).monospaced()
                }
                if let error = delegate.mainWindowHotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private var captureKey: String { delegate.composition.settings.captureHotKey.displayString }
    private var notesKey: String { delegate.composition.settings.mainWindowHotKey.displayString }
}
