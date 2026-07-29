import SwiftUI
import DnotesCore

struct TagChipsView: View {
    let model: NotesModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.tagCounts, id: \.tag) { tag in
                    Button {
                        // A second click on the same chip clears the filter (§7).
                        model.selectedTag = model.selectedTag == tag.tag ? nil : tag.tag
                    } label: {
                        HStack(spacing: 4) {
                            Text("#\(tag.tag)")
                            Text("\(tag.count)").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            model.selectedTag == tag.tag
                                ? AnyShapeStyle(Color.accentColor.opacity(0.30))
                                : AnyShapeStyle(.quaternary),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
