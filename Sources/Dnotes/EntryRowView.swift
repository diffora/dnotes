import SwiftUI
import DnotesCore

struct EntryRowView: View {
    let entry: NoteEntry
    let issueURLTemplate: String
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
                    text: entry.text,
                    issueURLTemplate: issueURLTemplate,
                    isDone: entry.isDone,
                    onClick: { clicks in
                        if clicks >= 2 { onBeginEdit() } else { onSelect() }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
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

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}
