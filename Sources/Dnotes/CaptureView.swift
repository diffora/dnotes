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

    /// Chips flowing left to right, not one tag per line.
    ///
    /// A line per tag made the list as tall as the tag count, and the panel window does
    /// not grow past `maxSuggestionHeight` — which is why a long list used to be drawn
    /// straight over the text field. Chips put fifteen tags where three used to fit, and
    /// the scroll view takes whatever is left over.
    private var suggestionList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ChipWrapLayout {
                    ForEach(Array(completion.suggestions.enumerated()), id: \.element.tag) { index, tag in
                        chip(title: "#\(tag.tag)", detail: "\(tag.count)",
                             color: settings.color(for: tag.tag).color,
                             selected: index == completion.selectedIndex)
                            .id(index)
                    }
                    if let name = completion.newTagName {
                        chip(title: "#\(name)", detail: "new",
                             color: settings.color(for: name).color,
                             selected: completion.selectedIndex == completion.suggestions.count)
                            .id(completion.suggestions.count)
                    }
                }
            }
            // Without `fixedSize` a scroll view takes every point offered, so the panel
            // would stand at its full height for a single suggestion.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: Self.maxSuggestionHeight)
            // ↑↓ can walk the selection past the visible rows, and a selection that
            // cannot be seen is indistinguishable from no selection at all.
            .onChange(of: completion.selectedIndex) {
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(completion.selectedIndex, anchor: .center)
                }
            }
        }
    }

    /// About five rows of chips. Past that the list scrolls rather than the panel
    /// growing: this window is anchored near the top of the screen, and a panel that
    /// keeps growing downward eventually runs off the bottom of it.
    private static let maxSuggestionHeight: CGFloat = 132

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

    /// The same chip the main window draws above its list, so a tag looks like itself
    /// wherever it appears. Selection gets both a stronger fill and a border: every chip
    /// is tinted, so the tint alone cannot carry the difference.
    private func chip(title: String, detail: String, color: Color, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(detail).foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(selected ? 0.32 : 0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
    }

    private func submit(keepOpen: Bool) {
        let captured = text
        guard !captured.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        text = ""
        completion.update(text: "", available: model.tagCounts)
        onSubmit(captured, keepOpen)
    }
}
