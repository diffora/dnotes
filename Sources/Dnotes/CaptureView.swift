import AppKit
import SwiftUI
import DnotesCore

struct CaptureView: View {
    let model: NotesModel
    let settings: SettingsStore
    let onSubmit: (String, Bool) -> Void
    let onCancel: (String) -> Void
    let onTextChanged: (String) -> Void

    @State private var text: String = ""
    @State private var completion = TagCompletionModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $text, prompt: Text("What happened?"))
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit { submit(keepOpen: NSEvent.modifierFlags.contains(.shift)) }
                .onExitCommand { onCancel(text) }
                .onChange(of: text) {
                    completion.update(text: text, available: model.tagCounts)
                    onTextChanged(text)
                }
                .onKeyPress(.tab) {
                    guard completion.isActive else { return .ignored }
                    text = completion.complete(in: text)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard completion.isActive else { return .ignored }
                    completion.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard completion.isActive else { return .ignored }
                    completion.moveSelection(by: 1)
                    return .handled
                }

            if completion.isActive {
                suggestionList
            } else {
                frequentTagHints
            }

            if !model.storeAvailable {
                Label("Folder unavailable — entries are kept and written when it is back",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ⌘1–⌘3 append a frequent tag; invisible buttons are the least intrusive
            // way to get a keyboard shortcut without a menu.
            ForEach(Array(model.topTags.enumerated()), id: \.element) { index, tag in
                Button("") { text = TagCompletionModel.appending(tag, to: text) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(width: 560)
        .onAppear {
            // A draft from a previous esc or crash is restored, not silently dropped.
            text = settings.panelDraft
            completion.update(text: text, available: model.tagCounts)
            focused = true
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(completion.suggestions.enumerated()), id: \.element.tag) { index, tag in
                row(title: "#\(tag.tag)", detail: "\(tag.count)",
                    selected: index == completion.selectedIndex)
            }
            if let name = completion.newTagName {
                row(title: "#\(name)", detail: "new tag",
                    selected: completion.selectedIndex == completion.suggestions.count)
            }
        }
    }

    /// One quiet row: the frequent tags of §6, plus the two ways out of the panel.
    /// The way out has to be written down somewhere — with the menu bar item hidden
    /// behind a full menu bar, this panel is the app's only reliable door.
    private var frequentTagHints: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.topTags.enumerated()), id: \.element) { index, tag in
                Text("⌘\(index + 1)  #\(tag)")
            }
            Spacer(minLength: 12)
            Text("⌘L notes")
            Text("⌘, settings")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func row(title: String, detail: String, selected: Bool) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(selected ? Color.accentColor.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }

    private func submit(keepOpen: Bool) {
        let captured = text
        guard !captured.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        text = ""
        completion.update(text: "", available: model.tagCounts)
        onSubmit(captured, keepOpen)
    }
}
