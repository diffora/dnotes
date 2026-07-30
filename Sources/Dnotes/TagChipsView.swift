import SwiftUI
import DnotesCore

struct TagChipsView: View {
    let model: NotesModel
    let settings: SettingsStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.tagCounts, id: \.tag) { tag in
                    chip(for: tag)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func chip(for tag: TagCount) -> some View {
        let color = settings.color(for: tag.tag).color
        let isSelected = model.selectedTag == tag.tag

        return Button {
            // A second click on the same chip clears the filter (§7).
            model.selectedTag = isSelected ? nil : tag.tag
        } label: {
            HStack(spacing: 4) {
                Text("#\(tag.tag)")
                Text("\(tag.count)").foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            // Here the colour becomes a fill, unlike in the list where it stays ink:
            // a chip is a button, and giving it the shape the tag does not have is what
            // says "this one is clickable, that one is a word".
            .background(color.opacity(isSelected ? 0.32 : 0.16), in: Capsule())
            // Selection has to read without relying on the tint alone — every chip is
            // tinted now, so the *difference* between filtered and not needs its own
            // channel.
            .overlay(
                Capsule().strokeBorder(color.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { colorMenu(for: tag.tag) }
    }

    /// The manual half of the colour rule: automatic by default, overridable where the
    /// automatic answer happens to be inconvenient — two tags you use together landing
    /// on the same colour, most likely.
    @ViewBuilder
    private func colorMenu(for tag: String) -> some View {
        let isAuto = settings.tagColorOverrides[TagPalette.fold(tag)] == nil
        let current = settings.colorSlot(for: tag)

        Button {
            settings.setColorSlot(nil, for: tag)
        } label: {
            Label("Automatic", systemImage: isAuto ? "checkmark" : "")
        }

        Divider()

        ForEach(Array(TagPalette.colors.enumerated()), id: \.offset) { slot, entry in
            Button {
                settings.setColorSlot(slot, for: tag)
            } label: {
                // A swatch, because eight colour names nobody chose are eight words to
                // decode; the name rides along for VoiceOver and for the odd case of two
                // slots that look alike in one theme.
                Label {
                    Text(entry.name)
                } icon: {
                    Image(systemName: !isAuto && slot == current
                          ? "largecircle.fill.circle" : "circle.fill")
                        .foregroundStyle(entry.color)
                }
            }
        }
    }
}
