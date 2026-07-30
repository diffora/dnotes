import SwiftUI
import DnotesCore

struct EntryRowView: View {
    let entry: NoteEntry
    let issueURLTemplate: String
    let tagColor: (String) -> NSColor
    let tagLayout: TagLayout
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingText: String
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onBeginEdit: () -> Void
    let onCommitEdit: (String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // A drawn checkbox that cannot be clicked is a broken affordance, so the
            // circle is the button. `.plain` because the default macOS button style
            // would put a bezel around it in the middle of a list row.
            Button(action: onToggle) {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isDone
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(isHovered ? AnyShapeStyle(.secondary)
                                                               : AnyShapeStyle(.tertiary)))
                    .font(.system(size: 13))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(entry.isDone ? "Reopen (␣)" : "Complete (␣)")

            if isEditing {
                // Bound to the list model, not to local state: leaving the row has to be
                // able to commit what was typed (§8).
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { onCommitEdit(editingText) }
                    .onExitCommand(perform: onCancelEdit)
                    .onAppear { focused = true }
            } else {
                // AppKit draws this so a link gets the pointing-hand cursor and takes
                // its own clicks; everything else comes back through `onClick`.
                EntryText(
                    text: shownText,
                    issueURLTemplate: issueURLTemplate,
                    isDone: entry.isDone,
                    tagColor: tagColor,
                    onClick: { clicks in
                        if clicks >= 2 { onBeginEdit() } else { onSelect() }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !isEditing, !trailingTags.isEmpty {
                trailingChips
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // Clicks on the text itself are routed by EntryText, which has to take them to
        // tell a link from ordinary words. These cover the rest of the row — the
        // padding and the space after the text. Both are *simultaneous* gestures on
        // purpose: a plain `.onTapGesture` next to a count-2 gesture makes SwiftUI hold
        // the single tap until the double-click timeout expires, which reads as a lag
        // before the row highlights.
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSelect() })
        .simultaneousGesture(TapGesture(count: 2).onEnded { onBeginEdit() })
        .contextMenu {
            Button(entry.isDone ? "Reopen" : "Complete", action: onToggle)
            Button("Edit…", action: onBeginEdit)
            Divider()
            Button("Delete", action: onDelete)
        }
    }

    // MARK: - which layout this row is drawn in

    /// The text the row shows. In the trailing layout the tags come out of it — unless
    /// that would leave nothing to show, which is what a note like `#daily` would do.
    /// A blank row with a chip floating on the right reads as a bug, so such a line keeps
    /// its tags inline and simply looks like the other layout. Better an exception nobody
    /// notices than an empty row.
    private var shownText: String {
        guard tagLayout == .trailing else { return entry.text }
        let stripped = TagScanner.stripping(entry.text)
        return stripped.isEmpty ? entry.text : stripped
    }

    private var trailingTags: [String] {
        guard tagLayout == .trailing, !TagScanner.stripping(entry.text).isEmpty else { return [] }
        return entry.tags
    }

    /// Deliberately not buttons. The chip bar above the list filters on click; these are
    /// the same tag in the same shape, so making them clickable too would be consistent —
    /// but they sit inside a row whose own clicks select it and whose double-click starts
    /// an edit, and a target that swallows those is worse than one that does nothing.
    private var trailingChips: some View {
        HStack(spacing: 4) {
            ForEach(entry.tags, id: \.self) { tag in
                // The `#` stays, even though the pill shape already says "tag" and
                // dropping it would read calmer: it is what the chip bar above shows and
                // what the line in the file actually contains, and a chip that quietly
                // renames `#perf` to `perf` starts to look like a field of its own.
                Text("#\(tag)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.isDone
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(Color(nsColor: tagColor(tag))))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        entry.isDone
                            ? AnyShapeStyle(.quaternary)
                            : AnyShapeStyle(Color(nsColor: tagColor(tag)).opacity(0.16)),
                        in: Capsule()
                    )
                    // Without this a run of tags on a narrow window squeezes the note's
                    // text down to nothing; the chips give way first.
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        // Aligned with the first line of a wrapped entry rather than centred on it: the
        // chips belong to the line the text starts on, not to the middle of a paragraph.
        .padding(.top, 1)
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}
