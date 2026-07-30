import SwiftUI
import DnotesCore

struct SettingsView: View {
    let delegate: AppDelegate

    var body: some View {
        Form {
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
}
